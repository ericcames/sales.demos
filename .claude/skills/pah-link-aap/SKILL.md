---
name: pah-link-aap
description: "Point this environment's AAP project syncs at its own Private Automation Hub, so collections resolve from the curated `approved` repository instead of the internet. Mints a read-scoped gateway token from credentials the environment already holds, creates the Galaxy credential, assigns it to the organization, and proves it with a real project sync. Fully reversible. TRIGGER when: the user asks to point AAP at PAH, wants project syncs to resolve from the hub, asks why a populated hub is not being used, wants organization Galaxy credentials, asks about issue #69, or wants to undo that link. SKIP: if the hub is empty or has not been populated and curated yet — that is pah-sync — or if the user wants to mirror the execution environment image, which is sales-demos-ee-build."
---

# pah-link-aap

Closes [#69](https://github.com/ericcames/sales.demos/issues/69). The hub is
populated by [`pah-sync`](../pah-sync/SKILL.md) and curated by
`curate_hub.yml`; until this runs, **nothing points at it**.

This skill contains **no logic**. The work is
[`playbooks/link_hub.yml`](../../../playbooks/link_hub.yml).

## What it does, and what it risks

Creates a `Sales Demos - PAH Galaxy` credential aimed at
`https://<aap_hostname>/api/galaxy/content/approved/` and assigns it to the
`IT Service Automation` organization.

**A Galaxy credential on the organization makes EVERY project sync in it resolve
from PAH.** If `approved` is short one collection, the sync fails and every job
template fails with it. Say that out loud before running this in front of anyone.

Three things bound it:

| Bound | Where |
|---|---|
| Refuses to link an empty `approved` | the playbook, before it mints anything |
| Reversal proven, not just written | `-e hub_galaxy_link_state=absent` |
| `sandbox` before `demo` | your discipline, not the code |

## One distribution, not four

`approved` only. Not the three mirrors as fallbacks, and not public Galaxy.

The mirrors' contents are decided by Red Hat and the community; `approved`'s are
declared in `hub/approved-collections.yml`. Pointing at a mirror "just in case"
gives up the only claim this use case makes — *your teams install what you
approved* — in exchange for hiding the failure this playbook is designed to
surface.

## The token is a gateway token, not a PAH API token

**This is the trap, and it cost a failed run.** The obvious mint is the hub's own
API token endpoint, `POST /api/galaxy/v3/auth/token/`. It exists on AAP 2.7 and
issues a perfectly real 40-character token. **The gateway does not accept it.**

Measured on sandbox 2026-09-04, against the hub's collection index:

| Credential | Result |
|---|---|
| basic auth (`admin` / password) | `200` |
| galaxy_ng token, `Authorization: Token` | `403` |
| galaxy_ng token, `Authorization: Bearer` | `403` |
| **gateway token, either scheme** | **`200`** |

A Galaxy credential built from a galaxy_ng token fails the project sync with
`HTTP Code: 403, Message: Authentication credentials were not provided` — which
reads like a credential that was never attached rather than one that was
rejected, and sends you looking in entirely the wrong place.

So the mint is `POST /api/gateway/v1/tokens/`, the same endpoint
[`utilities/make-aap-mcp.sh`](../../../utilities/make-aap-mcp.sh) already uses.
Scope is `read`: a project sync only downloads, and a gateway token inherits the
creating user's permissions.

**Nothing is stored.** The token is minted from `aap_username` / `aap_password`,
which already rotate with the environment, and never written to disk. That is the
answer to #69's gate 3 — the credential dies with the RHDP environment, so the
question was never *where to keep it* but *how to mint it again*.

**Gateway tokens accumulate**, unlike the galaxy_ng ones, so the playbook retires
the tokens it minted on earlier runs before minting a fresh one. Exactly one
should ever exist. The unlink deletes it.

## Preflight Check

```bash
ENV=${ENV:-sandbox}

# 1. The vault password file exists.
test -s "$HOME/secrets/.vault_pass_sales_demos" \
  && echo "✅ vault password file" \
  || echo "❌ ~/secrets/.vault_pass_sales_demos missing — see /sales-demos-first-time"

# 2. secrets.yml exists locally and is vault-encrypted. It is gitignored (#130).
head -c 15 playbooks/group_vars/all/secrets.yml 2>/dev/null | grep -q '^\$ANSIBLE_VAULT' \
  && echo "✅ secrets.yml is vault-encrypted" \
  || echo "❌ secrets.yml missing or NOT encrypted — see /sales-demos-first-time"

# 3. The environment answers at all. An expired RHDP environment fails here
#    rather than three minutes into a run (#RHDP envs expire silently).
HOST=$(grep -oP '(?<=^aap_hostname: ")[^"]+' inventory/group_vars/$ENV/connection.yml)
curl -sk --max-time 15 "https://$HOST/api/gateway/v1/ping/" \
  | grep -q '"status":"good"' \
  && echo "✅ $ENV reachable ($HOST)" \
  || echo "❌ $ENV is not answering — check the environment is still alive"

# 4. The curated list is complete. --write-approved refuses to write a set
#    missing a transitive dependency, so a clean run here means the file is
#    the full closure rather than just the nine pins.
python3 utilities/refresh-hub-requirements.py --write-approved

# 5. No project-local ansible.cfg.
test -f ansible.cfg && echo "❌ project-local ansible.cfg present — delete it" \
  || echo "✅ no project-local ansible.cfg"
```

If any check fails, stop and tell the user which one and the fix beside it.

**Then confirm `approved` is populated** — this skill's whole premise:

```bash
ansible-playbook playbooks/curate_hub.yml -i inventory --limit $ENV \
  -e target_env=$ENV \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

It is idempotent, so running it here costs nothing and removes the only
interesting failure mode. If it has never run against this environment, it will
report `Added N` — that is expected on a fresh hub, not a warning.

## Dry run first

```bash
ansible-playbook playbooks/link_hub.yml -i inventory --limit sandbox \
  -e target_env=sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos --check
```

`--check` mints nothing and creates nothing, **but still verifies the curated
repository** — the read-only gates carry `check_mode: false` on purpose, so this
is a real preflight rather than a play that skips its own checks.

## Run

```bash
mkdir -p ~/ansible-logs
export ANSIBLE_LOG_PATH=~/ansible-logs/pah-link-sandbox-$(date +%F-%H%M).log

ansible-playbook playbooks/link_hub.yml -i inventory --limit sandbox \
  -e target_env=sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

> **`--limit` is mandatory.** Without it the run targets both environments and
> `tasks/assert_target_environment.yml` fails it.
>
> **Never pipe through `tee`** — it breaks the callback's output handling.

**It ends with a real project sync.** That is not decoration: it is the only step
that proves the hub can actually serve what a project needs. A failure there is
the playbook working, not the playbook broken.

### Reversing it

```bash
ansible-playbook playbooks/link_hub.yml -i inventory --limit sandbox \
  -e target_env=sandbox -e hub_galaxy_link_state=absent \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

Unassigns the credential, deletes it, and retires the gateway token. Project
syncs go back to resolving from the execution environment, as they did before
#69. **Run this the moment anything looks wrong** — it is quick and it is proven.

## Verify against AAP, not the recap

```bash
HOST=$(grep -oP '(?<=^aap_hostname: ")[^"]+' inventory/group_vars/sandbox/connection.yml)
PW=$(ansible-vault view playbooks/group_vars/all/secrets.yml \
       --vault-id sales.demos@~/secrets/.vault_pass_sales_demos \
     | python3 -c 'import sys,yaml; print(yaml.safe_load(sys.stdin)["env_secrets"]["sandbox"]["aap_password"])')

# The organization carries exactly one Galaxy credential, pointed at `approved`
curl -sk -u "admin:$PW" \
  "https://$HOST/api/controller/v2/organizations/?name=IT%20Service%20Automation" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["results"][0]["related"]["galaxy_credentials"])'

# Exactly one token with this playbook's description — never two
curl -sk -u "admin:$PW" \
  "https://$HOST/api/gateway/v1/tokens/?description=sales.demos%20PAH%20Galaxy%20(%2369)" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["count"], "token(s)")'
```

Or ask over MCP, which is the cheaper path:
`mcp__aap-sandbox__organizations_list` and `mcp__aap-sandbox__credentials_list`.

**The strongest check is the one the playbook already ran**: read the project
update's stdout and confirm `Fetch galaxy collections from
collections/requirements.yml` is `changed` and green. The download URLs in a
verbose run name `/api/galaxy/v3/plugin/ansible/content/approved/` — that is what
"no internet egress" looks like in evidence rather than in prose.

### The clean-container version of the same claim

```bash
EE=quay.io/zigfreed/sales-demos-ee:v1.1.0    # tag from controller_execution_environments.yml
podman run --rm -v "$PWD/collections/requirements.yml:/tmp/req.yml:ro,Z" \
  -e T="<a read-scoped gateway token>" -e H="$HOST" "$EE" bash -lc '
    ansible-galaxy collection install -r /tmp/req.yml \
      -s "https://$H/api/galaxy/content/approved/" --api-key "$T" \
      -p /tmp/out --force --ignore-certs'
```

Every artifact should download from `/content/approved/`. This is #69's gate 2
in its literal wording, and it needs a container because a laptop already has the
collections installed and will report "nothing to do".

## If it fails

| Symptom | Cause | Fix |
|---|---|---|
| `'approved' is empty, so pointing AAP at it would break every project sync` | The curated repository was never populated on this environment | Run `curate_hub.yml`, then re-run |
| Project sync: `Could not satisfy the following requirements: * <ns>.<name>` | `approved` is missing a **transitive** dependency | `python3 utilities/refresh-hub-requirements.py --write-approved`, commit, `curate_hub.yml`, re-run. This is exactly how `ansible.eda` was found |
| Project sync: `403 ... Authentication credentials were not provided` | The credential's token is not one the gateway accepts | You are minting a galaxy_ng token. It must be a gateway token — see above |
| Two tokens with the playbook's description | A run was interrupted between the retire and the mint | Delete the older one; the next clean run also fixes it |
| Every job template suddenly fails at project sync | Whatever the cause, do not debug it live | `-e hub_galaxy_link_state=absent`, then investigate |
| `Attempting to decrypt but no vault secrets found` | `--vault-id` missing | Add it; see the Run block |

Never paste a live cluster hostname, password or token into a commit message,
issue, or PR. This repo is public.
