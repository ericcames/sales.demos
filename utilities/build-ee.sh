#!/usr/bin/env bash
# ===========================================================================
# build-ee.sh — build, verify, and publish the sales.demos execution
# environment described by ../execution-environment.yml. (#31)
#
# Use this instead of calling ansible-builder directly. It does three things
# ansible-builder will not do for you:
#
#   1. Stages ~/.ansible.cfg into .ee-build/ so the galaxy stage can install
#      certified collections. The EE definition cannot reference ~/.ansible.cfg
#      itself: an absolute /home/<user>/ path breaks for teammates, and a
#      tracked ansible.cfg at the repo root would shadow ~/.ansible.cfg and
#      break certified installs everywhere else on the machine.
#   2. Asserts ~/.ansible.cfg is a REAL FILE. ansible-builder's COPY does not
#      follow symlinks, so a symlinked config silently yields an image with no
#      Hub token and a confusing galaxy failure.
#   3. Smoke-tests the built image as the unprivileged runtime user (UID 1000),
#      which the in-Containerfile checks cannot do — every append_final step
#      runs as root, before `USER 1000`.
#
#   ./utilities/build-ee.sh              # build + verify
#   ./utilities/build-ee.sh --push       # build + verify + push to quay
#   EE_IMAGE=quay.io/zigfreed/sales-demos-ee:v1.1.0 ./utilities/build-ee.sh
#
# Publishing is a separate, explicit flag. A build is cheap and local; a push
# overwrites a tag other people's AAP instances pull from.
#
# After pushing a NEW tag, update it in
# inventory/group_vars/aap/controller_execution_environments.yml
# so AAP actually uses it. Never re-push an existing tag — job templates pinned
# to it would silently change underneath a demo.
# ===========================================================================
set -euo pipefail

# Default tag follows the aap_config convention: quay.io/zigfreed/<demo>-ee:vX.Y.Z
EE_IMAGE="${EE_IMAGE:-quay.io/zigfreed/sales-demos-ee:v1.1.0}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

push=0
for arg in "$@"; do
  case "$arg" in
    --push) push=1 ;;
    -h|--help) sed -n '2,32p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "error: unknown argument '$arg' (expected --push)" >&2; exit 2 ;;
  esac
done

die() { echo "error: $*" >&2; exit 1; }

# --- Preflight ------------------------------------------------------------
command -v ansible-builder >/dev/null || die "ansible-builder not found (pip install ansible-builder)"
command -v podman          >/dev/null || die "podman not found"

cfg="$HOME/.ansible.cfg"
[ -e "$cfg" ] || die "$cfg does not exist — it holds the Automation Hub token the galaxy build stage needs."
[ -L "$cfg" ] && die "$cfg is a SYMLINK. ansible-builder's COPY does not follow symlinks, so the
       build would produce an image with no Hub token. Replace it with a real file:
         cp --remove-destination \"\$(readlink -f '$cfg')\" '$cfg'"
[ -f "$cfg" ] || die "$cfg is not a regular file"
grep -q '^\[galaxy_server\.' "$cfg" || die "$cfg has no [galaxy_server.*] section — certified collections will fail to install."

# registry.redhat.io is authenticated even for the base image pull.
podman login --get-login registry.redhat.io >/dev/null 2>&1 \
  || die "not logged in to registry.redhat.io — run: podman login registry.redhat.io"

# --- Stage the real ansible.cfg into the (gitignored) build context -------
mkdir -p .ee-build
cp "$cfg" .ee-build/ansible.cfg
chmod 600 .ee-build/ansible.cfg
trap 'rm -f "$repo_root/.ee-build/ansible.cfg"' EXIT

# --- Build ----------------------------------------------------------------
echo "==> Building $EE_IMAGE"
# PYCMD IS PINNED TO python3.12 ON PURPOSE, AND THE BUILD FAILS WITHOUT IT (#122).
#
# assemble installs the system packages the collections' bindep files ask for,
# and that list includes python3-devel. On RHEL 9 that package pulls in
# python3-3.9, which REPOINTS /usr/bin/python3 from the base image's 3.12 to
# 3.9 -- and 3.9 carries no pip. The next thing assemble does is
# `$PYCMD -m pip install -r requirements.txt`, so with the default
# PYCMD=/usr/bin/python3 the build dies with:
#
#   /usr/bin/python3: No module named pip
#
# Naming the interpreter explicitly makes it immune to whatever bindep drags
# in. Measured on the 2.7 base: after `microdnf install python3-devel`,
# `/usr/bin/python3 -m pip` is broken while `/usr/bin/python3.12 -m pip` works.
#
# THIS WAS ALWAYS LATENT, not something the 2.7 base introduced. The 2.6 build
# never hit it because introspection found no python requirements, so assemble
# never reached that pip call. Nothing published is affected either -- the
# clobber happens in the throwaway builder stage, and the final image is
# assembled from a fresh base (verified: v1.0.0 has python3 -> 3.12, pip works).
ansible-builder build \
  --file execution-environment.yml \
  --context .ee-build/context \
  --tag "$EE_IMAGE" \
  --build-arg PYCMD=/usr/bin/python3.12 \
  --verbosity 2

# --- Verify ---------------------------------------------------------------
# Ask the image, not the build log. Both checks below are hard requirements of
# Phase 3: terraform must execute as the runtime user, and every pinned
# collection must actually be present at the pinned version.
#
# Both run as --user 1000, because that is who AAP runs a job as. A binary that
# works as root and not as 1000 would pass the Containerfile's own check and
# then fail in front of a customer.
echo "==> Verifying $EE_IMAGE as the runtime user (UID 1000)"

podman run --rm --user 1000 --entrypoint /usr/local/bin/terraform "$EE_IMAGE" version \
  || die "terraform does not run as UID 1000 in $EE_IMAGE"

# The collection comparison is done on the HOST: it keeps requirements.yml out
# of the container (no bind mount, no SELinux relabel of a tracked file) and
# avoids quoting a Python program through two shells.
installed_json="$(podman run --rm --user 1000 --entrypoint ansible-galaxy \
                    "$EE_IMAGE" collection list --format json 2>/dev/null)" \
  || die "could not list collections in $EE_IMAGE"

python3 - "$installed_json" <<'PY' || die "image verification failed — see above"
import json, sys, yaml

installed = {}
for _path, colls in json.loads(sys.argv[1]).items():
    for name, info in colls.items():
        installed.setdefault(name, info["version"])

bad = False
for c in yaml.safe_load(open("collections/requirements.yml"))["collections"]:
    name, want = c["name"], str(c["version"])
    have = installed.get(name)
    if have is None:
        print("MISSING  %s (pinned %s)" % (name, want)); bad = True
    elif have != want:
        print("DRIFT    %s installed %s, pinned %s" % (name, have, want)); bad = True
    else:
        print("ok       %s %s" % (name, have))

sys.exit(1 if bad else 0)
PY

# --- The published image must carry NO credential -------------------------
# #172. execution-environment.yml stages ~/.ansible.cfg -- which holds the Red
# Hat offline token -- via prepend_galaxy, so it lands in the GALAXY BUILD STAGE
# only. The final image is built FROM base and copies the installed collections
# out, not that file.
#
# THAT WAS TRUE WHEN MEASURED AND NOTHING ENFORCED IT. Move that ADD from
# prepend_galaxy to append_final, add a COPY for some other reason, or let a
# future base image ship its own /etc/ansible/ansible.cfg, and a token-bearing
# image would build, verify green on every check above, and push to a PUBLIC
# registry. We would learn about it from a scraper.
#
# This is the same reasoning as check 2 in utilities/check-no-secrets.sh: the
# mechanism that keeps the secret out is not trusted, it is verified.
#
# Four checks, because no one of them is sufficient. Each was proven against a
# deliberately poisoned image before being written here, not reasoned about.
echo "==> Verifying $EE_IMAGE carries no credential"

# 1. The path the staged config would land on.
podman run --rm --user 1000 --entrypoint /bin/bash "$EE_IMAGE" \
     -c 'test ! -e /etc/ansible/ansible.cfg' \
  || die "$EE_IMAGE contains /etc/ansible/ansible.cfg — the Hub token may be baked in"

# 2. Any config Ansible would ACTUALLY load, wherever it lives -- this one also
#    covers a config placed somewhere unexpected, or reached via ANSIBLE_CONFIG.
active_cfg="$(podman run --rm --user 1000 --entrypoint ansible "$EE_IMAGE" --version 2>/dev/null \
              | sed -n 's/^ *config file *= *//p')"
[ "$active_cfg" = "None" ] \
  || die "$EE_IMAGE loads a config file ($active_cfg) — it should have none"

# 3. A config file present but INERT, which check 2 cannot see. Scoped to *.cfg
#    because a README is never config: two upstream collection READMEs document
#    a [galaxy_server.*] section with a `token=<SuperSecretToken>` placeholder,
#    and a looser grep flags both. The value must also not be a <placeholder>
#    or a {{ template }}, which is what rules out infra.aap_configuration's
#    ansible.cfg.j2.
leaked="$(podman run --rm --user 1000 --entrypoint /bin/bash "$EE_IMAGE" -c '
  find /etc /root /home /runner /opt /usr/share/ansible -name "*.cfg" -type f 2>/dev/null |
  while read -r f; do
    grep -qs "^\[galaxy_server\." "$f" &&
    grep -qsE "^[[:space:]]*token[[:space:]]*=[[:space:]]*[^[:space:]<{]" "$f" && echo "$f"
  done' 2>/dev/null || true)"
[ -z "$leaked" ] \
  && : \
  || die "$EE_IMAGE has a galaxy_server token in: $leaked"

# 4. A layer that ADDs the config and a LATER layer that deletes it. Checks 1-3
#    all pass on such an image -- the merged filesystem is genuinely clean -- and
#    the credential is still sitting in the layer blob in plaintext. Verified by
#    building exactly that image and recovering the token from a 224-byte layer,
#    so this is the one check with a failure mode nothing else here can see.
hist="$(podman history --no-trunc --format '{{.CreatedBy}}' "$EE_IMAGE" \
        | grep -iE '(ADD|COPY).*(/etc/ansible|ansible\.cfg)' || true)"
[ -z "$hist" ] \
  || die "$EE_IMAGE has a layer copying a config in, even if the file is gone now: $hist"

echo "    no /etc/ansible/ansible.cfg, no active config, no galaxy_server token, no config layer"

echo "==> Verified"

# --- Publish --------------------------------------------------------------
if [ "$push" -eq 1 ]; then
  registry="${EE_IMAGE%%/*}"
  podman login --get-login "$registry" >/dev/null 2>&1 \
    || die "not logged in to $registry — run: podman login $registry"
  echo "==> Pushing $EE_IMAGE"
  podman push "$EE_IMAGE"
  echo "==> Pushed. Now set this image in"
  echo "    inventory/group_vars/aap/controller_execution_environments.yml"
  echo "    then apply it: ansible-playbook playbooks/config.yml -i inventory --limit sandbox ..."
else
  echo
  echo "Built locally and not pushed. To publish:"
  echo "  ./utilities/build-ee.sh --push"
fi
