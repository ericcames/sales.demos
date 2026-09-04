---
name: sales-demos-ee-build
description: "Build, verify, and publish the custom execution environment this repo's AAP job templates run on — the image that carries the terraform CLI plus the pinned collections. Wraps utilities/build-ee.sh, then registers the new tag in AAP config-as-code. TRIGGER when: the user asks to build, rebuild, bump, or publish the EE, add a collection to the EE, change the terraform version, re-pin the base image, or hits EE errors (ImagePullBackOff on a job template, 'terraform: command not found' in a job, 'couldn't resolve module/action' at runtime but not locally, or an ansible-builder assemble failure). SKIP: if the user only wants collections installed on their laptop — that is collections-sync — or is registering an EE that already exists in quay."
---

# sales-demos-ee-build

Builds the image AAP runs this repo's playbooks on:
`quay.io/zigfreed/sales-demos-ee`, defined by `execution-environment.yml` at the
repo root.

**Why it exists.** Phase 3 (#4) drives `terraform/ocpvirt/` by shelling out to
the terraform CLI. No stock execution environment ships that binary. That is the
entire reason for a custom image — everything else in it could have come from
`ee-supported-rhel9` unchanged.

Like `collections-sync`, this skill has **no playbook**, and that is deliberate.
The "skill wraps a playbook" contract in `CLAUDE.md` exists so anything touching
a demo environment is runnable from AAP too. This builds a container on your
laptop and pushes it to a registry; it must never run from AAP, and there is
nothing for a job template to call.

## Never reimplement the build here

`utilities/build-ee.sh` is the build. It stages `~/.ansible.cfg`, builds,
verifies the image as UID 1000, and optionally pushes. Do not run
`ansible-builder` directly and do not paste its flags into a chat command —
the staging step is not optional, and skipping it produces an image with no
Automation Hub token and a confusing galaxy failure.

## Preflight Check

```bash
# 1. Build tooling
command -v ansible-builder >/dev/null && echo "✅ ansible-builder $(ansible-builder --version)" || echo "❌ ansible-builder missing"
command -v podman          >/dev/null && echo "✅ $(podman --version)"                        || echo "❌ podman missing"

# 2. ~/.ansible.cfg is a REAL FILE, not a symlink — ansible-builder's COPY does
#    not follow symlinks, and the Hub token would silently not reach the build.
test -L ~/.ansible.cfg && echo "❌ ~/.ansible.cfg is a symlink — replace it with a real file" \
  || { test -f ~/.ansible.cfg && echo "✅ ~/.ansible.cfg is a real file" || echo "❌ ~/.ansible.cfg missing"; }

# 3. It carries an Automation Hub token
grep -q '^\[galaxy_server\.' ~/.ansible.cfg 2>/dev/null \
  && echo "✅ ~/.ansible.cfg has galaxy_server entries" \
  || echo "❌ no [galaxy_server.*] section — certified collections will not install"

# 4. Registry logins. registry.redhat.io is needed to PULL the base image;
#    quay.io only to push.
podman login --get-login registry.redhat.io >/dev/null 2>&1 \
  && echo "✅ logged in to registry.redhat.io" || echo "❌ podman login registry.redhat.io"
podman login --get-login quay.io >/dev/null 2>&1 \
  && echo "✅ logged in to quay.io" || echo "⚠️  not logged in to quay.io (only needed for --push)"

# 5. No project-local ansible.cfg — it would shadow ~/.ansible.cfg machine-wide
test -f ansible.cfg && echo "❌ project-local ansible.cfg present — delete it" || echo "✅ no project-local ansible.cfg"
```

## Build

```bash
./utilities/build-ee.sh
```

Builds and verifies without publishing. The verify step runs **as UID 1000**,
which is who AAP runs a job as, and checks two things: that `terraform version`
executes, and that every collection pinned in `collections/requirements.yml` is
present at exactly that version.

Report the verify output verbatim. A build that says `Complete!` has not been
verified — the `==> Verified` line is the one that matters.

## Publish

```bash
./utilities/build-ee.sh --push
```

Then set the new tag in `inventory/group_vars/aap/controller_execution_environments.yml`
and apply it:

```bash
ansible-playbook playbooks/validate.yml -i inventory --limit sandbox -e target_env=sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos   # check mode first
ansible-playbook playbooks/config.yml   -i inventory --limit sandbox -e target_env=sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

## Tags are immutable. Never re-push one.

Job templates pin a tag with `pull: missing`. Re-pushing a tag that AAP already
references changes what a job template runs without changing anything you can
see in git — the worst possible failure, because it surfaces mid-demo. Publish a
new tag and bump the reference.

Bump rule, following the convention already used for `quay.io/zigfreed` images:

| Change | Bump |
|---|---|
| Rebuild for CVEs, no content change | patch — `v1.0.1` |
| Add or bump a collection, bump terraform | minor — `v1.1.0` |
| New base image | major — `v2.0.0` |

Override the tag per build with `EE_IMAGE`:

```bash
EE_IMAGE=quay.io/zigfreed/sales-demos-ee:v1.1.0 ./utilities/build-ee.sh --push
```

The `description:` in `controller_execution_environments.yml` enumerates base
image, terraform version, and collections — it **is** the manifest AAP shows in
the UI. Keep it in step on every bump; it is the only place a demo operator can
see what is in the image.

## Changing what goes in

- **A collection** — add it to `collections/requirements.yml` (pinned, via
  `collections-sync`), not to the EE definition. One pinned list feeds both the
  laptop and the image; that equality is what makes the skill path and the job
  template path agree.
- **Terraform version** — change the version *and* the sha256 together in
  `execution-environment.yml`, from
  `https://releases.hashicorp.com/terraform/<version>/terraform_<version>_SHA256SUMS`.
- **Base image** — re-pin the digest, never a tag:
  ```bash
  skopeo inspect docker://registry.redhat.io/ansible-automation-platform-27/ee-supported-rhel9:latest | jq -r .Digest
  ```

## Gotchas — learned from the build, do not "simplify" away

1. **`systemd-python` fails the build, and the fix is to EXCLUDE it, not compile
   it.** ansible-builder introspects *every* collection in the image, including
   ones the base ships that this repo never asked for. `ee-supported-rhel9`
   ships `ansible.eda`, whose `requirements.txt` lists `systemd-python` for its
   journald event source. There is no wheel, so pip builds from source and dies
   with `Cannot find libsystemd or libsystemd-journal` — the UBI base has no
   `systemd-devel` and no subscription to get it. `dependencies.exclude.python`
   handles it. Nothing here has a journald event source.

   Note this is the **opposite** of the fix in `aap.lightspeed.patching`, which
   installs `python3.11-devel` and compiles it. That EE is on `ee-minimal`, where
   the dependency arrives through a collection it genuinely uses. Do not port
   that advice here.

2. **`package_manager_path: /usr/bin/microdnf` is required.** `ee-supported-rhel9`
   ships microdnf, not dnf; ansible-builder defaults to `/usr/bin/dnf` and the
   build fails at the first system-package step without it.

3. **The base image is pinned by digest, not tag.** `latest` moves, and this
   repository publishes no immutable tag matching what `latest` resolves to —
   its `version`/`release` labels are not in `RepoTags`. The digest is the only
   thing that names one build.

4. **Every `append_final` step runs as root**, because ansible-builder emits
   `USER 1000` after them. An in-Containerfile `terraform version` therefore
   proves nothing about the runtime user. That is why `build-ee.sh` re-runs it
   with `--user 1000` after the build.

5. **`.ee-build/` is gitignored and must stay that way.** It holds a copy of
   `~/.ansible.cfg` — a live Automation Hub token. It is also deliberately not
   at the repo root: an `ansible.cfg` there would shadow `~/.ansible.cfg` and
   break certified collection installs across every repo on the machine.

6. **The published image carries no credential.** The token reaches the galaxy
   build stage only; the final image is built `FROM base` and copies the
   installed collections, not the config file.
