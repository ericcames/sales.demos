---
name: collections-sync
description: "Pin, install, and verify the Ansible collections this repo depends on. Writes exact versions into collections/requirements.yml, installs them to the recommended path (~/.ansible/collections), then checks that what is installed matches what is pinned and fails loudly on drift. TRIGGER when: the user asks to install or update collections, add a collection to the repo, pin or bump a collection version, or when a playbook fails with 'couldn't resolve module/action' or a collection-version error. SKIP: if the user is adding a Python package rather than an Ansible collection, or only wants to run the CI lint gate."
---

# collections-sync

Keeps `collections/requirements.yml` honest: every collection pinned to an
exact version, installed to the recommended path, and verified to match.

Unlike the `ocpvirt-*` skills this one has **no playbook**, and that is
deliberate — it touches your laptop's collection path, never a demo
environment. The "skill wraps a playbook" contract in `CLAUDE.md` exists so
that anything touching an environment is runnable from AAP too. Nothing here
should ever run from AAP.

## The rules this enforces

1. **Every collection is pinned to an exact version. Nothing floats.** A
   floating version means two laptops resolve different code and a demo that
   worked yesterday breaks on the next install.
2. **Pins are set to versions that were actually run**, not the newest
   published. Bump deliberately, re-run the affected phase against `sandbox`,
   then commit the new pin.
3. **Collections install to the recommended path only** — Ansible's default
   `~/.ansible/collections`. Never into the repo.
4. **Never create a project-local `ansible.cfg`.** Ansible picks one cfg file
   and does not merge. A local one shadows `~/.ansible.cfg`, which holds the
   working Automation Hub token, and breaks certified content installs. Use CLI
   flags or environment variables instead.

## Preflight Check

```bash
# 1. No project-local ansible.cfg — this is the one that silently breaks things
test -f ansible.cfg \
  && echo "❌ project-local ansible.cfg present — it shadows ~/.ansible.cfg and breaks certified installs; delete it" \
  || echo "✅ no project-local ansible.cfg"

# 2. ~/.ansible.cfg has a real Automation Hub token
grep -q 'galaxy_server.rh_certified' ~/.ansible.cfg 2>/dev/null \
  && grep -A3 'galaxy_server.rh_certified' ~/.ansible.cfg | grep -qE '^token=.+' \
  && echo "✅ ~/.ansible.cfg has an rh_certified token" \
  || echo "❌ ~/.ansible.cfg missing an rh_certified token — certified collections will not install"

# 3. requirements.yml exists
test -s collections/requirements.yml \
  && echo "✅ collections/requirements.yml" \
  || echo "❌ collections/requirements.yml missing"

# 4. Collections are not vendored into the repo
{ test -d collections/ansible_collections || test -n "$(git ls-files .ansible/)"; } \
  && echo "❌ collections vendored in the repo — they belong in ~/.ansible/collections (#8)" \
  || echo "✅ no collections vendored in the repo"

# 5. Confirm the recommended install path
ansible-config dump 2>/dev/null | grep -i '^COLLECTIONS_PATHS' \
  || echo "❌ could not read COLLECTIONS_PATHS"
```

The first entry of `COLLECTIONS_PATHS` is the recommended path and where
`ansible-galaxy` installs by default. Expect `/home/<user>/.ansible/collections`.

## Audit: what is pinned vs what is installed

Run this first, always. It is read-only and tells you whether there is anything
to do.

```bash
python3 - <<'PY'
import subprocess, yaml, sys, re
req = yaml.safe_load(open("collections/requirements.yml"))["collections"]

out = subprocess.run(["ansible-galaxy", "collection", "list"],
                     capture_output=True, text=True).stdout
# First occurrence wins — that is COLLECTIONS_PATHS resolution order.
installed = {}
for line in out.splitlines():
    m = re.match(r"^([a-z0-9_]+\.[a-z0-9_]+)\s+([0-9][^\s]*)\s*$", line)
    if m and m.group(1) not in installed:
        installed[m.group(1)] = m.group(2)

bad = 0
for c in req:
    name = c["name"] if isinstance(c, dict) else c
    want = c.get("version") if isinstance(c, dict) else None
    have = installed.get(name)
    if want is None:
        print(f"UNPINNED  {name:38} installed {have or '(none)'}"); bad += 1
    elif have is None:
        print(f"MISSING   {name:38} pinned {want}, not installed"); bad += 1
    elif have != want:
        print(f"DRIFT     {name:38} pinned {want}, installed {have}"); bad += 1
    else:
        print(f"OK        {name:38} {want}")
print("\n" + ("Everything pinned and installed as specified."
              if not bad else f"{bad} item(s) need attention."))
sys.exit(0 if not bad else 1)
PY
```

## Pin

For each `UNPINNED` entry, add the installed version to
`collections/requirements.yml` as `version: "<exact>"`. If a collection is not
installed at all, install it first so the pin records a version that actually
resolved:

```bash
ansible-galaxy collection install <namespace.name>
ansible-galaxy collection list <namespace.name>
```

Never invent a version number and never pin to a range (`>=`, `*`). Show the
user the diff before writing it.

## Install

```bash
ansible-galaxy collection install -r collections/requirements.yml
```

Installs to the recommended path. Add `--force` only when bumping a pin
downward — `ansible-galaxy` will not downgrade otherwise, which is exactly the
case that produces a silent `DRIFT` result afterwards.

## Verify

**Re-run the audit block above after installing.** This step is the point of
the skill: `ansible-galaxy` can resolve a different version than requested
without failing, and a downgrade is skipped outright. Do not report success on
the install command's exit code.

Report the audit output verbatim. If anything is still `DRIFT` or `MISSING`,
say so plainly rather than describing the install as done.

## When a pin changes

A version bump is a behaviour change, not housekeeping. Per `CLAUDE.md`:

- Open an issue first, labelled (`gh label list --repo ericcames/sales.demos`).
- Re-run the affected phase against `sandbox` and verify against the cluster —
  the CI lint gate cannot tell you a collection bump broke a playbook.
- Note the bump in `CHANGELOG.md`.
- Keep it to one concern per PR. A bump that fixes a specific bug ships on its
  own, not bundled with unrelated pins.
