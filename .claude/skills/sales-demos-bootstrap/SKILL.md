---
name: sales-demos-bootstrap
description: >-
  Full environment bootstrap from a single AAP URL — repoint local.yml,
  verify vault, run setup.yml (all 11 stages with timing including probe),
  set up MCP servers, and verify everything.
  TRIGGER when: user provides a new RHDP environment URL and wants it fully
  set up, or says "bootstrap", "new environment", "fresh cluster".
  SKIP: if only one component needs updating — use the specific skill instead.
---

# sales-demos-bootstrap

Takes a single AAP URL and drives every step needed to bring a new RHDP
environment from bare to demo-ready, including the post-setup tasks that
`setup.yml` cannot do (MCP server registration, cluster probing, settings
updates).

**This skill orchestrates other skills and playbooks.** It contains no
playbook logic of its own — it calls `setup.yml`, invokes
[`/sales-demos-mcp`](https://github.com/ericcames/sales.demos/blob/main/.claude/skills/sales-demos-mcp/SKILL.md),
runs `probe_env.yml`, and updates gitignored local files. The playbooks do the
work; this skill sequences them.

## When to use this vs the pieces

| Situation | Use |
|---|---|
| Brand new RHDP environment, want everything | **This skill** |
| Only AAP config changed (edited group_vars) | [`/sales-demos-config`](https://github.com/ericcames/sales.demos/blob/main/.claude/skills/sales-demos-config/SKILL.md) |
| Only the portal needs redeploying | [`/sales-demos-portal`](https://github.com/ericcames/sales.demos/blob/main/.claude/skills/sales-demos-portal/SKILL.md) |
| MCP servers need reconnecting | [`/sales-demos-mcp`](https://github.com/ericcames/sales.demos/blob/main/.claude/skills/sales-demos-mcp/SKILL.md) |
| Cluster already set up, just verify | [`/sales-demos-verify-env`](https://github.com/ericcames/sales.demos/blob/main/.claude/skills/sales-demos-verify-env/SKILL.md) |
| First time on this machine | [`/sales-demos-first-time`](https://github.com/ericcames/sales.demos/blob/main/.claude/skills/sales-demos-first-time/SKILL.md) |

## Step 1 — Parse the AAP URL

Extract the cluster ID from the URL the user provides. The pattern is:

```
aap-aap.apps.cluster-<id>.dyn.redhatworkshops.io
```

Derive:
- `aap_hostname`: `aap-aap.apps.cluster-<id>.dyn.redhatworkshops.io`
- `openshift_api_url`: `https://api.cluster-<id>.dyn.redhatworkshops.io:6443`
- `openshift_apps_domain`: `apps.cluster-<id>.dyn.redhatworkshops.io`

## Step 2 — Ask which environment

Ask: **sandbox, demo, or edge?** Default to `sandbox` if the user does not
specify.

Edge is different — it is a persistent bare-metal SNO, not an RHDP
provisioning. If the user says edge, confirm they mean the NUC at
`192.168.0.253` and not a new RHDP environment.

## Step 3 — Update local.yml

Write the three identity values to `inventory/group_vars/<env>/local.yml`.
This file is gitignored — it overrides `connection.yml` without touching a
tracked file.

```bash
ENV=sandbox  # or demo

cat > inventory/group_vars/"$ENV"/local.yml <<YAML
---
# Repointed by /sales-demos-bootstrap on $(date +%F)
aap_hostname: "aap-aap.apps.cluster-<id>.dyn.redhatworkshops.io"
openshift_api_url: "https://api.cluster-<id>.dyn.redhatworkshops.io:6443"
openshift_apps_domain: "apps.cluster-<id>.dyn.redhatworkshops.io"
YAML
```

If `local.yml` already exists, read it first and preserve any extra keys
(like `available_memory_gb` or SSH key overrides).

## Step 4 — Verify vault credentials

The vault must already contain credentials for this environment. Assert that
`env_secrets.<env>` has `openshift_api_token`, `aap_password`, and
`kubeadmin_password`:

```bash
VAULT_ID="sales.demos@$HOME/secrets/.vault_pass_sales_demos"

ansible-vault view playbooks/group_vars/all/secrets.yml \
  --vault-id "$VAULT_ID" 2>/dev/null \
  | ENV="$ENV" python3 -c '
import sys, yaml, os
env = os.environ["ENV"]
data = yaml.safe_load(sys.stdin)
secrets = data.get("env_secrets", {}).get(env, {})
for key in ["openshift_api_token", "aap_password", "kubeadmin_password"]:
    status = "present" if secrets.get(key) else "MISSING"
    print(f"  {key}: {status}")
'
```

If any are missing, tell the user to run
[`/sales-demos-first-time`](https://github.com/ericcames/sales.demos/blob/main/.claude/skills/sales-demos-first-time/SKILL.md)
to populate the vault, and **stop**. Do not proceed with missing credentials.

## Step 5 — Run preflight

```bash
./utilities/preflight.sh "${ENV}" --k8s
```

If any check fails, stop and tell the user which one failed and the fix.

## Step 6 — Test cluster reachability

Resolve the API URL and token, then confirm the cluster answers:

```bash
VAULT_ID="sales.demos@$HOME/secrets/.vault_pass_sales_demos"

OCP_URL=$(ansible -i inventory --limit "$ENV" aap -m debug --vault-id "$VAULT_ID" \
  -a 'msg={{ openshift_api_url }}' 2>/dev/null \
  | sed -n 's/.*"msg": "\(.*\)"/\1/p')

OCP_TOKEN=$(ansible-vault view playbooks/group_vars/all/secrets.yml \
  --vault-id "$VAULT_ID" 2>/dev/null \
  | ENV="$ENV" python3 -c \
    'import sys,yaml,os; print(yaml.safe_load(sys.stdin)["env_secrets"][os.environ["ENV"]]["openshift_api_token"])')

python3 - <<'PY'
import os, ssl, json, urllib.request
ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
req = urllib.request.Request(os.environ["OCP_URL"].rstrip("/") + "/apis",
                             headers={"Authorization": "Bearer " + os.environ["OCP_TOKEN"]})
resp = json.load(urllib.request.urlopen(req, context=ctx, timeout=20))
print(f"Cluster is reachable — {len(resp['groups'])} API groups")
PY
```

If the cluster does not answer, stop. The token may be expired — tell the
user to get a fresh one from the OpenShift console (*Copy login command*).

## Step 7 — Run setup.yml

This is the main event. All 11 stages, ~25-30 minutes. Wrap in
`python3 subprocess.run()` for Claude Code's blocking IO.

```bash
mkdir -p ~/ansible-logs
export ANSIBLE_LOG_PATH=~/ansible-logs/sales-demos-bootstrap-${ENV}-$(date +%F-%H%M).log
```

```python
import subprocess, os
result = subprocess.run(
    ["ansible-playbook", "playbooks/setup.yml",
     "-i", "inventory", "--limit", os.environ["ENV"],
     "-e", f"target_env={os.environ['ENV']}",
     "--vault-id", f"sales.demos@{os.path.expanduser('~/secrets/.vault_pass_sales_demos')}"],
    capture_output=False
)
```

Tell the user this takes ~25-30 minutes. The timing summary at the end shows
per-stage elapsed times.

If it fails, check the log at `$ANSIBLE_LOG_PATH` and see the failure table
in
[`/sales-demos-setup`](https://github.com/ericcames/sales.demos/blob/main/.claude/skills/sales-demos-setup/SKILL.md).

## Step 8 — Set up MCP servers

Invoke
[`/sales-demos-mcp`](https://github.com/ericcames/sales.demos/blob/main/.claude/skills/sales-demos-mcp/SKILL.md)
to generate kubeconfigs, AAP bearer tokens, and register all MCP servers for
the new cluster.

## Step 9 — Update local.yml with probe results

`setup.yml` stage 10 already ran `probe_env.yml` and printed the recommended
`available_memory_gb`. Update `local.yml` with that value so Terraform uses the
real capacity, not a hardcoded guess.

## Step 10 — Verify env-urls

`setup.yml` stage 9 already generated the env-urls file. Verify it exists and
references the new cluster:

```bash
grep "$ENV" env-urls.yml 2>/dev/null || echo "env-urls.yml missing or does not reference $ENV"
```

## Step 11 — Update settings.local.json

Check `~/.claude/settings.local.json` (or `.claude/settings.local.json` in
the repo) for WebFetch domain allowlists referencing old cluster IDs. If
found, update them to the new cluster's domain. This is a local file and is
not committed.

## Step 12 — Final verification

The MCP servers need a Claude Code restart to take effect. Tell the user:

> Restart Claude Code to pick up the new MCP servers, then verify with
> lightweight calls:
>
> - `mcp__openshift-<env>__namespaces_list` (fieldSelector=metadata.name=default)
> - `mcp__aap-<env>__me_list`
>
> Report **Live** if data comes back, **Dead** if it errors.

## Step 13 — Print summary

Print a final summary covering:

- The timing summary from setup.yml (per-stage and total)
- All deployed URLs:
  - AAP: `https://<aap_hostname>`
  - Portal: `https://rhaap-portal-aap-portal.<apps_domain>`
  - AO: `https://ao-eda.<apps_domain>` (if installed)
  - MCP: deployed in-cluster
- `available_memory_gb` from the probe
- What is ready and what needs a restart

## What this does NOT do

- **Does not commit `connection.yml`.** Uses `local.yml` (gitignored) so there
  is nothing to push. Committing `connection.yml` is a separate step for when
  the environment is stable and you want AAP job templates to use it.
- **Does not commit anything.** All changes are to gitignored files (`local.yml`,
  kubeconfigs, bearer tokens, `settings.local.json`).
- **Does not create vault credentials.** That is
  [`/sales-demos-first-time`](https://github.com/ericcames/sales.demos/blob/main/.claude/skills/sales-demos-first-time/SKILL.md).
  Run it first if the vault is empty for this environment.
- **Does not deploy to AAP job templates.** AAP reads from the SCM checkout,
  which uses the committed `connection.yml`. To make AAP job templates target the
  new cluster, commit the updated `connection.yml` and let the project sync
  pick it up.
- **Does not run link_hub.yml.** Attaching the Galaxy credential to the
  organization is opt-in and separate — see
  [`/pah-link-aap`](https://github.com/ericcames/sales.demos/blob/main/.claude/skills/pah-link-aap/SKILL.md).

## If it fails

Most failures are in the `setup.yml` run (step 7). See the failure table in
[`/sales-demos-setup`](https://github.com/ericcames/sales.demos/blob/main/.claude/skills/sales-demos-setup/SKILL.md).

| Symptom | Cause | Fix |
|---|---|---|
| Vault credentials missing (step 4) | New environment, vault not updated | Run [`/sales-demos-first-time`](https://github.com/ericcames/sales.demos/blob/main/.claude/skills/sales-demos-first-time/SKILL.md) |
| Cluster unreachable (step 6) | Token expired or environment not provisioned | Get a fresh token from the OpenShift console |
| `setup.yml` fails (step 7) | See the setup skill's failure table | Check `$ANSIBLE_LOG_PATH` |
| MCP servers fail (step 8) | Kubeconfig or token stale | Re-run [`/sales-demos-mcp`](https://github.com/ericcames/sales.demos/blob/main/.claude/skills/sales-demos-mcp/SKILL.md) |

Never paste a live cluster hostname or token into a commit message, issue, or
PR. This repo is public — see `CLAUDE.md`.
