#!/usr/bin/env bash
# ===========================================================================
# run-in-ee.sh — run a playbook inside the execution environment AAP uses,
# instead of beside it on the laptop. Issue #120.
#
#   utilities/run-in-ee.sh playbooks/probe_env.yml -i inventory --limit sandbox \
#     -e target_env=sandbox \
#     --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
#
#   utilities/run-in-ee.sh --with-hub-token playbooks/sync_hub.yml ...
#
# EVERYTHING AFTER THE PLAYBOOK IS PASSED THROUGH UNCHANGED, and that equality
# is the whole point. Take the `ansible-playbook` line out of any skill, put
# this in front of it, and it runs in the image AAP runs — same flags, same
# --vault-id, same ~/ path. If the two ever have to be written differently,
# something here is wrong.
#
# WHY THIS EXISTS. `ansible-playbook` on the laptop resolves
# ~/.ansible/collections and the system python. An AAP job template resolves
# whatever the EE baked in. Those are two dependency sets and only one is what
# production uses. CI cannot tell them apart -- the lint gate executes nothing
# -- so a local run is this repo's only pre-merge verification, and by default
# it verifies the wrong one.
#
# That is not hypothetical. #122 found python3-devel, pulled in by the
# collections' own bindep files, repointing /usr/bin/python3 from the base's
# 3.12 to RHEL 9's 3.9 -- whose site-packages has no kubernetes and no yaml.
# The image built clean, pushed clean, and passed every check build-ee.sh had.
# A laptop run could not have seen it. Running the playbook inside the image is
# the only pre-merge check that would have.
#
# IT IS A VERIFICATION PATH, NOT A REPLACEMENT. `ansible-playbook` stays the
# documented everyday command in every skill. This is what you run before a PR
# merges, and when a job template fails in a way a laptop run will not
# reproduce. See /sales-demos-verify-ee.
#
# ---------------------------------------------------------------------------
# WHAT CROSSES INTO THE CONTAINER, AND WHY IT IS A MOUNT AND NOT A BAKED LAYER
#
# The published image carries NO credential. execution-environment.yml stages
# ~/.ansible.cfg into the galaxy build stage only; the final image is built
# FROM base and copies the installed collections out, not that file. Measured:
# no /etc/ansible at all, and `ansible --version` reports `config file = None`.
# Guarding that in the build is #172.
#
# So anything this needs is mounted at RUN time, from the laptop, read-only,
# and nothing is persisted. A bind mount is the same single file #22 and #68
# made authoritative -- not a second stored copy of a rotating credential,
# which is the thing those issues refused.
#
# The mounts are here rather than in a committed ansible-navigator.yml on
# purpose: a tracked config would put a credential directory path in a public
# repo, would apply silently to anyone running ansible-navigator in this
# directory, and would become a second source of truth for the EE tag.
#
# WHY ~/ PATHS RESOLVE. ansible-navigator runs the EE as root (rootless podman
# maps container root to the invoking host user, which is what lets it read a
# 0700 directory) with HOME=/root, and bind-mounts the project at its own host
# path. So mounting ~/secrets at /root/secrets makes
# `--vault-id sales.demos@~/secrets/.vault_pass_sales_demos` resolve to the same
# file inside as outside. Navigator already does exactly this for ~/.ssh, which
# it mounts to both /root/.ssh and /home/runner/.ssh. Measured with
# `ansible-navigator exec --ll debug`, not assumed; the dual mount below is
# belt-and-braces in case that user ever changes.
# ===========================================================================
set -euo pipefail

WITH_HUB_TOKEN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-hub-token) WITH_HUB_TOKEN=1; shift ;;
    -h|--help) sed -n '2,65p' "${BASH_SOURCE[0]}"; exit 0 ;;
    --) shift; break ;;
    *) break ;;
  esac
done

PLAYBOOK="${1:-}"
if [[ -z "$PLAYBOOK" ]]; then
  echo "usage: utilities/run-in-ee.sh [--with-hub-token] <playbook> [ansible-playbook args...]" >&2
  echo "       utilities/run-in-ee.sh --help" >&2
  exit 2
fi
shift

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [[ ! -f "$PLAYBOOK" ]]; then
  echo "❌ playbook '$PLAYBOOK' not found, relative to $REPO_ROOT" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# The image. The TAG comes from what AAP actually runs, so the verification
# image cannot drift from the production one -- that drift is the entire defect
# this script exists to close, and hardcoding a second copy of the tag here
# would reintroduce it.
#
# The REGISTRY differs deliberately. AAP pulls the PAH mirror
# ({{ aap_hostname }}/sales_demos_ee:<tag>), which needs the
# "Sales Demos - PAH Registry" credential and an environment that is up. quay
# carries the same mirrored content and needs neither. The digest audit trail
# in controller_execution_environments.yml is how you prove they match:
#   skopeo inspect --no-creds docker://quay.io/zigfreed/sales-demos-ee:<tag>
#
# EE_IMAGE overrides the whole thing, matching utilities/build-ee.sh, which is
# how you test an image you have built but not yet registered.
# ---------------------------------------------------------------------------
EE_REGISTERED="inventory/group_vars/aap/controller_execution_environments.yml"
if [[ -z "${EE_IMAGE:-}" ]]; then
  EE_TAG="$(sed -n 's|^ *image: *"{{ *aap_hostname *}}/sales_demos_ee:\([^"]*\)".*|\1|p' \
            "$EE_REGISTERED" | head -1)"
  if [[ -z "$EE_TAG" ]]; then
    echo "❌ could not read the EE tag from $EE_REGISTERED" >&2
    echo "   Expected a line of the form:" >&2
    echo '     image: "{{ aap_hostname }}/sales_demos_ee:vX.Y.Z"' >&2
    echo "   Fix that file, or set EE_IMAGE explicitly. This does NOT fall back" >&2
    echo "   to a hardcoded tag -- a guess here would verify the wrong image," >&2
    echo "   which is the exact failure this script exists to prevent." >&2
    exit 1
  fi
  EE_IMAGE="quay.io/zigfreed/sales-demos-ee:${EE_TAG}"
fi

# ---------------------------------------------------------------------------
# Preflight. Each of these gets its own message: a missing vault password and a
# missing container runtime fail very differently, and "podman: not found"
# buried in a navigator traceback tells you nothing.
# ---------------------------------------------------------------------------
command -v podman >/dev/null 2>&1 || {
  echo "❌ podman not found — ansible-navigator needs a container runtime." >&2
  exit 1
}
command -v ansible-navigator >/dev/null 2>&1 || {
  echo "❌ ansible-navigator not found. Install it the same way the other" >&2
  echo "   ansible tools here are installed:" >&2
  echo "     python3 -m pip install --user ansible-navigator" >&2
  echo "   A launcher in ~/.local/bin can survive its package — if" >&2
  echo "   'ansible-navigator --version' raises ModuleNotFoundError, reinstall." >&2
  exit 1
}

# SALES_DEMOS_VAULT_PASS is read by inventory/group_vars/aap/main.yml and
# utilities/make-kubeconfig.sh too, so one export moves all three together
# rather than leaving them disagreeing (#131).
VAULT_PASS="${SALES_DEMOS_VAULT_PASS:-$HOME/secrets/.vault_pass_sales_demos}"
if [[ ! -s "$VAULT_PASS" ]]; then
  echo "❌ $VAULT_PASS missing — without it the secrets file cannot be decrypted." >&2
  echo "   Build it with /sales-demos-first-time, step 2, or set" >&2
  echo "   SALES_DEMOS_VAULT_PASS if yours lives somewhere else." >&2
  exit 1
fi
VAULT_DIR="$(cd "$(dirname "$VAULT_PASS")" && pwd)"

if ! podman image exists "$EE_IMAGE" && ! podman pull -q "$EE_IMAGE" >/dev/null 2>&1; then
  echo "❌ $EE_IMAGE is not present locally and could not be pulled." >&2
  echo "   Build it with /sales-demos-ee-build, or 'podman login quay.io'." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Mounts. The vault directory goes in twice: once at /root/secrets so a ~/
# relative --vault-id resolves, once at its literal host path so a $HOME
# expanded one does. Both read-only. Nothing else crosses by default.
# ---------------------------------------------------------------------------
MOUNTS=("${VAULT_DIR}:/root/secrets:ro,z" "${VAULT_DIR}:/home/runner/secrets:ro,z")
if [[ "$VAULT_DIR" != "/root/secrets" && "$VAULT_DIR" != "/home/runner/secrets" ]]; then
  MOUNTS+=("${VAULT_DIR}:${VAULT_DIR}:ro,z")
fi

# ---------------------------------------------------------------------------
# The Automation Hub offline token, opt-in and off by default.
#
# Off by default because most playbooks have no business seeing it. Every one
# not named below runs with no token reachable inside the container at all,
# which is the point of a flag rather than an unconditional mount.
#
# WHICH PLAYBOOKS NEED IT, AND WHY IT IS MORE THAN THE HUB ONES. Anything that
# evaluates `automation_hub_token` needs it, and that is wider than it looks:
# inventory/group_vars/aap/hub_collection_remotes.yml templates the token, and
# dispatch touches that variable on any full config apply. So config.yml,
# validate.yml and setup.yml are on this list alongside sync_hub.yml and
# curate_hub.yml. Measured, not reasoned about -- validate.yml under this
# wrapper without the flag dies at ok=9.
#
# THE TWO FAILURE MODES ARE DIFFERENT AND BOTH ARE BAD:
#
#   config/validate/setup  fail LOUDLY, with a message that names neither the
#                          token nor the cause:
#                            AnsibleParserError: Invalid filename: 'None'
#                          The ini lookup does NOT return '' for a missing
#                          file, which is what group_vars/aap/main.yml used to
#                          say -- it raises.
#
#   sync_hub/curate_hub    would fail SILENTLY if it did return '': the hub
#                          remotes get configured with no credential,
#                          authenticate as anonymous, and the sync reports
#                          success having moved nothing. #68 added an assert
#                          for exactly that, but refusing here is better than
#                          relying on it.
#
# Refusing rather than warning, in both cases, because a wrong answer that
# looks right is the failure this whole repo keeps designing against.
# ---------------------------------------------------------------------------
case "$PLAYBOOK" in
  *sync_hub.yml|*curate_hub.yml|*config.yml|*validate.yml|*setup.yml)
    if [[ "$WITH_HUB_TOKEN" -eq 0 ]]; then
      echo "❌ $PLAYBOOK evaluates automation_hub_token, which is read from" >&2
      echo "   ~/.ansible.cfg and nowhere else (#22, #68). An execution" >&2
      echo "   environment has no such file — verified: the published image" >&2
      echo "   has no /etc/ansible at all and reports 'config file = None'." >&2
      echo >&2
      echo "   Re-run with --with-hub-token to mount it read-only for this run:" >&2
      echo "     utilities/run-in-ee.sh --with-hub-token $PLAYBOOK ..." >&2
      echo >&2
      echo "   Without it the run does NOT quietly skip the token. It either" >&2
      echo "   dies with \"Invalid filename: 'None'\", or -- for the hub" >&2
      echo "   playbooks -- would configure remotes with no credential and" >&2
      echo "   report SUCCESS having synced nothing." >&2
      exit 1
    fi
    ;;
esac

if [[ "$WITH_HUB_TOKEN" -eq 1 ]]; then
  cfg="$HOME/.ansible.cfg"
  if [[ ! -f "$cfg" ]]; then
    echo "❌ $cfg not found — it holds the Red Hat offline token (#22)." >&2
    exit 1
  fi
  if ! grep -q '^\[galaxy_server\.' "$cfg"; then
    echo "❌ $cfg has no [galaxy_server.*] section, so it carries no token." >&2
    exit 1
  fi
  MOUNTS+=("${cfg}:/root/.ansible.cfg:ro,z" "${cfg}:/home/runner/.ansible.cfg:ro,z")
fi

# Run logs belong in ~/ansible-logs, OUTSIDE this repo -- it is public (#26).
# Navigator otherwise drops ansible-navigator.log in the working directory.
LOG_DIR="${SALES_DEMOS_LOG_DIR:-$HOME/ansible-logs}"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/ansible-navigator.log"

# ---------------------------------------------------------------------------
# The ansible-core comparison. Pinned collections are NOT a pinned environment,
# and nothing else in this repo says so out loud (#173).
#
# collections/requirements.yml pins every collection exactly, and build-ee.sh
# verifies every pin matched -- both were green while validate.yml passed here
# and failed inside the image, because the divergence was entirely UNDERNEATH
# the collections: core 2.18.18rc1 on the laptop against 2.16.19 in the EE.
# Two minors apart, and the laptop on a release candidate.
#
# So print both, every run, and flag a mismatch. This is deliberately a NOTE and
# not a failure: the whole purpose of this wrapper is to run the EE's dependency
# set rather than the laptop's, so a difference here is expected and is the
# reason to be running it. What is not acceptable is the difference being
# invisible, which is what let #173 sit unexplained.
# ---------------------------------------------------------------------------
LAPTOP_CORE="$(ansible --version 2>/dev/null | sed -n '1s/.*\[core \([^]]*\)\].*/\1/p')"
EE_CORE="$(podman run --rm "$EE_IMAGE" ansible --version 2>/dev/null \
           | sed -n '1s/.*\[core \([^]]*\)\].*/\1/p')"

# Say exactly what crosses into the container before it does. An SE running
# this in front of a customer should be able to point at this block and say
# "that is everything, and none of it is in the image".
echo "==> execution environment : $EE_IMAGE"
echo "==> playbook              : $PLAYBOOK"
echo "==> ansible-core          : ${EE_CORE:-unknown} in the EE, ${LAPTOP_CORE:-unknown} on this laptop"
if [[ -n "$EE_CORE" && -n "$LAPTOP_CORE" && "$EE_CORE" != "$LAPTOP_CORE" ]]; then
  echo "                            NOTE: these differ. The EE's is the one AAP runs."
  echo "                            Collection pins can all match and still leave this gap (#173)."
fi
echo "==> log                   : $LOG_FILE"
echo "==> mounts (read-only):"
for m in "${MOUNTS[@]}"; do echo "      $m"; done
if [[ "$WITH_HUB_TOKEN" -eq 0 ]]; then
  echo "      (no Automation Hub token — pass --with-hub-token if a playbook needs it)"
fi
echo

MOUNT_ARGS=()
for m in "${MOUNTS[@]}"; do MOUNT_ARGS+=(--execution-environment-volume-mounts "$m"); done

# --playbook-artifact-enable false: the artifact is a JSON replay of the whole
# run, written to the working directory, and it contains resolved variables.
# In a public repo that is exactly the file you do not want appearing.
exec ansible-navigator run "$PLAYBOOK" \
  --execution-environment-image "$EE_IMAGE" \
  --pull-policy missing \
  --mode stdout \
  --playbook-artifact-enable false \
  --log-file "$LOG_FILE" \
  "${MOUNT_ARGS[@]}" \
  -- "$@"
