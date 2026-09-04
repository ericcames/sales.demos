---
name: pah-sync
description: "Populate this environment's Private Automation Hub as code — all Red Hat certified and validated collections windowed to their 3 newest versions, plus the ericcames and mlowcher61 community namespaces at their current version only. Regenerates the pinned lists from upstream, runs playbooks/sync_hub.yml, then asks the hub what actually landed. TRIGGER when: the user asks to populate, sync, fill or refresh Private Automation Hub or PAH, wants certified or validated collections in their hub, asks why a hub is empty or a collection is missing from it, wants to refresh hub/*-requirements.yml, or hits a hub sync that reports success with no content. SKIP: if the user wants to point AAP projects AT the hub via organization Galaxy credentials — that is issue #69 and deliberately not done yet — or wants to mirror the execution environment image, which is sales-demos-ee-build."
---

# pah-sync

Populates the Private Automation Hub that ships with every AAP environment,
from configuration in git rather than from the web UI.

This skill contains **no logic**. The work is
[`playbooks/sync_hub.yml`](../../../playbooks/sync_hub.yml) and
[`utilities/refresh-hub-requirements.py`](../../../utilities/refresh-hub-requirements.py).

**Every build already does most of this.** `config.yml` — stage 2 of
`setup.yml` — applies the same remotes and repositories and *starts* a sync
without waiting. What this skill adds is waiting for it and then proving it.

## What lands in the hub

| Repository | Content | Versions |
|---|---|---|
| `rh-certified` | every Red Hat certified collection (214) | 3 newest of each |
| `validated` | every Red Hat validated collection (47) | 3 newest of each |
| `community` | the `ericcames` and `mlowcher61` namespaces (15) | current only |

The lists are committed: `hub/certified-requirements.yml`,
`hub/validated-requirements.yml`, `hub/community-requirements.yml`.

**Pulp has no "keep N versions" control**, which is why those files exist. A
requirements entry of a bare `namespace.name` syncs *every* published version,
and some certified collections have 40+. Each entry instead carries an explicit
version or a `>=` floor. `retain_repo_versions` is not a substitute — it prunes
repository snapshots, not collection versions.

## This is laptop-only, and there is no job template

Unlike every phase of the OpenShift Virtualization demo, this has one entry
point. The Red Hat offline token lives in `~/.ansible.cfg` and nowhere else, and
an execution environment has no such file.

A vaulted fallback was built and verified working, then removed on purpose: it
bought one job template at the cost of a second copy of a rotating credential.
`config.yml` has always been in the same position — you cannot use AAP to
bootstrap itself.

**Never suggest running this from AAP.** It will not error; it will configure the
remotes with an empty token, sync anonymously, and leave the hub empty behind a
green run.

## Preflight Check

```bash
ENV=${ENV:-sandbox}
VAULT_ID="sales.demos@$HOME/secrets/.vault_pass_sales_demos"

# 1. The vault password file exists. Without it secrets.yml cannot be
#    decrypted and aap_password will look simply undefined.
test -s "$HOME/secrets/.vault_pass_sales_demos" \
  && echo "✅ vault password file" \
  || echo "❌ ~/secrets/.vault_pass_sales_demos missing"

# 2. secrets.yml exists locally and is vault-encrypted, not plaintext.
#    It is gitignored (#130); a fresh clone will not have it.
head -c 15 playbooks/group_vars/all/secrets.yml 2>/dev/null | grep -q '^\$ANSIBLE_VAULT' \
  && echo "✅ secrets.yml is vault-encrypted" \
  || echo "❌ secrets.yml missing or NOT encrypted — see /sales-demos-first-time"

# 3. The Red Hat OFFLINE token resolves. This is the one that matters: an empty
#    token does not fail the sync, it just syncs nothing.
python3 - <<'PY'
import configparser, os
c = configparser.ConfigParser(); c.read(os.path.expanduser("~/.ansible.cfg"))
t = c.get("galaxy_server.rh_certified", "token", fallback="")
print("✅ offline token present ({} chars)".format(len(t))) if len(t) > 100 else \
  print("❌ no offline token in ~/.ansible.cfg [galaxy_server.rh_certified] —"
        " get one at https://console.redhat.com/ansible/automation-hub/token")
PY

# 4. The three generated lists exist and parse.
python3 - <<'PY'
import yaml, pathlib
for k in ("certified", "validated", "community"):
    p = pathlib.Path("hub") / f"{k}-requirements.yml"
    try:
        n = len(yaml.safe_load(p.read_text())["collections"])
        print(f"✅ {p} — {n} collections")
    except Exception as e:
        print(f"❌ {p} — {e}; run utilities/refresh-hub-requirements.py")
PY

# 5. No project-local ansible.cfg. It would shadow ~/.ansible.cfg — which is
#    where the offline token lives — and break this entirely.
test -f ansible.cfg && echo "❌ project-local ansible.cfg present — delete it" \
  || echo "✅ no project-local ansible.cfg"
```

If any check fails, stop and tell the user which one and the fix shown beside
it. Do not attempt the run with a failing prerequisite.

## Refreshing the pinned lists

Only when you want to pick up new upstream releases. The sync itself does not
need it.

```bash
python3 utilities/refresh-hub-requirements.py
git diff hub/
```

Takes about 25 seconds for all three. Review the diff and commit it — that diff
*is* the record of what changed upstream, and it is the strongest artifact this
use case produces.

Two other modes:

```bash
python3 utilities/refresh-hub-requirements.py --check       # drift only, writes nothing
python3 utilities/refresh-hub-requirements.py --audit-pins  # offline, no network
```

`--audit-pins` answers a question [#69](https://github.com/ericcames/sales.demos/issues/69)
depends on: would every collection in `collections/requirements.yml` actually
resolve from the hub? **Two currently would not** — `ansible.controller` and
`ansible.platform` are pinned below their version window. That breaks nothing
today, because no organization has a Galaxy credential.

## Run

```bash
mkdir -p ~/ansible-logs
export ANSIBLE_LOG_PATH=~/ansible-logs/pah-sync-sandbox-$(date +%F-%H%M).log

ansible-playbook playbooks/sync_hub.yml -i inventory --limit sandbox \
  -e target_env=sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

> **Always set `ANSIBLE_LOG_PATH`.** A sync produces a lot of output and you will
> want it after the fact.
>
> **Never pipe the run through `tee`.** It breaks the callback's output handling.
>
> **`--limit` is mandatory.** Without it the run targets both environments, and
> the guard in `tasks/assert_target_environment.yml` fails it.

**Measured 4.4 minutes** (264s) for all three repositories on sandbox — 214
certified, 47 validated, 15 community. Treat that as a floor: that run followed
earlier failed attempts so Pulp may have had artifacts cached, and a genuinely
cold cluster on a slow link will take longer. The playbook allows 90 minutes.

### Useful knobs

```bash
# Configure the remotes and repositories, start no sync at all
-e hub_sync_enabled_override=false

# Start the sync but do not wait for it (what config.yml does)
-e hub_sync_wait_override=false
```

Run `playbooks/validate.yml` first if you only want to see what would change —
it is `config.yml` in check mode, and it explicitly forces `hub_sync_enabled:
false` so it cannot start a sync.

**That guard is load-bearing, so do not remove it.** `ansible.hub` 1.1.0's
`collection_repository_sync` checks for check mode with a parameter that is not
in its argument_spec, so the check never fires and the sync runs for real. The
group_vars guard uses `not ansible_check_mode`, which is only True for a CLI
`--check` — a play-level `check_mode: true` leaves it False.

Note also that **check mode cannot validate content**: `uri` does not run under
`--check`, so `sync_hub.yml` skips its verification block entirely there.

## Verify it in the EE before merging a change

The `ansible-playbook` command above runs on your laptop, against
`~/.ansible/collections` and your system python. An AAP job template runs this
same playbook inside `sales-demos-ee`. **Those are two dependency sets and CI
can see neither** — the lint gate executes nothing. Run it in the image as well:

```bash
utilities/run-in-ee.sh --with-hub-token playbooks/sync_hub.yml \
  -i inventory --limit sandbox -e target_env=sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

Everything after the playbook is unchanged from the command above — the wrapper
adds the image and two read-only mounts and nothing else.
`--with-hub-token` mounts `~/.ansible.cfg` read-only for the run. The wrapper
refuses to start this playbook without it: the token lookup **raises** on a
missing file rather than returning empty.

Full detail, including how to diff the two runs: `/sales-demos-verify-ee`.

## Curating the `approved` repository

The three synced repositories are mirrors and **a sync cannot remove anything**.
The fourth repository, `approved`, has no remote — its contents are reconciled
from `hub/approved-collections.yml`, and that reconcile adds *and* removes.

```bash
# Regenerate the curated list from this repo's pins (no network)
python3 utilities/refresh-hub-requirements.py --write-approved

# Make the repository equal the file
ansible-playbook playbooks/curate_hub.yml -i inventory --limit sandbox \
  -e target_env=sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

Seeded with the nine collections in `collections/requirements.yml` at their exact
pinned versions — what this repo itself depends on, which is what would make
[#69](https://github.com/ericcames/sales.demos/issues/69) safe.

**If it refuses with "not present anywhere in this hub"**, that version is
missing — usually because it sits below the certified version window. Run
`--audit-pins`, then regenerate and re-sync: the generator lowers a floor to any
version this repo has pinned.

**This is the repository to point consumers at**, not the mirrors.

## Verify against the hub, not the recap

**A green playbook run is not proof.** The playbook already asserts all of this
when it waits, but run it by hand if you are debugging:

```bash
HOST=$(grep -oP '(?<=^aap_hostname: ")[^"]+' inventory/group_vars/sandbox/connection.yml)
PW=$(ansible-vault view playbooks/group_vars/all/secrets.yml \
       --vault-id sales.demos@~/secrets/.vault_pass_sales_demos \
     | python3 -c 'import sys,yaml; print(yaml.safe_load(sys.stdin)["env_secrets"]["sandbox"]["aap_password"])')

for repo in rh-certified validated community; do
  n=$(curl -sk -u "admin:$PW" \
    "https://$HOST/api/galaxy/v3/plugin/ansible/content/$repo/collections/index/?limit=1" \
    | python3 -c 'import sys,json; print(json.load(sys.stdin)["meta"]["count"])')
  echo "$repo: $n collections"
done
```

Three things must hold, and the third is the one people skip:

1. **Every repository is non-empty.** ~214 in `rh-certified`, ~47 in `validated`,
   15 in `community`.
2. **Each community collection is present at exactly its pinned version and no
   other.** Presence alone proves nothing — a full-history sync would also pass
   an existence check.
3. **The certified window bounded the sync.** Count versions of a long-lived
   collection like `amazon.aws` or `redhat.rhel_system_roles`: three, not thirty.
   **Without this there is no evidence the window did anything** — an unwindowed
   sync produces an equally green run and an equally populated hub.

## If it fails

| Symptom | Cause | Fix |
|---|---|---|
| Run is green, repositories are **empty** | The offline token expired. It authenticates and then returns nothing — this is the signature failure. | Regenerate at `https://console.redhat.com/ansible/automation-hub/token`, update `~/.ansible.cfg` `[galaxy_server.rh_certified]` |
| `The Red Hat offline token did not resolve` | No token in `~/.ansible.cfg`, or you are running inside an execution environment | Add the token. If in an EE, stop — this playbook is laptop-only |
| A repository has **thousands** of versions | The remote lost its `requirements_file` | Check `inventory/group_vars/aap/hub_collection_remotes.yml`, re-apply |
| `hub/<x>-requirements.yml is missing or empty` | Never generated, or a failed refresh | `python3 utilities/refresh-hub-requirements.py` |
| Repository created but stays empty, no error | The role gate. The item needs `sync: true` | `-e hub_sync_enabled_override=true`, and check `hub_collection_repositories.yml` |
| A community collection installs but its dependencies do not | `sync_dependencies: false` on the community remote, deliberately | Add the dependency to `hub/community-requirements.yml`, or accept it |
| `Attempting to decrypt but no vault secrets found` | `--vault-id` missing | Add it; see the Run block |

Never paste a live cluster hostname, password or token into a commit message,
issue, or PR. This repo is public.
