---
name: sales-demos-dashboard
description: "Push Grafana Cloud dashboards (dashboard-as-code). Runs playbooks/deploy_dashboard.yml. TRIGGER when: the user wants to push, deploy, or update the Grafana dashboard, apply dashboard-as-code, or set up the cluster health dashboard. SKIP: if the user only wants to query Grafana Cloud (that is the MCP server from /sales-demos-mcp) or deploy Alloy (that is /sales-demos-alloy)."
---

# sales-demos-dashboard

Push Grafana Cloud dashboards defined as committed JSON. Issue
[#275](https://github.com/ericcames/sales.demos/issues/275).

## There is an AAP path now too (#318)

`AAP Observability - 2 Deploy Dashboards` runs the same playbook from AAP, so
this no longer has to come off a laptop. Use whichever suits; the skill is still
the quicker loop while iterating on dashboard JSON.

**It is not per-environment, and that surprises people.** One Grafana Cloud
serves both environments, so the template exists in both controllers and pushes
to the *same* folder — running it from demo also updates what sandbox sees.

This skill contains **no logic**. All the work is in
[`playbooks/deploy_dashboard.yml`](../../../playbooks/deploy_dashboard.yml). See
`CLAUDE.md` → *Skills and playbooks*.

## What it does

1. Creates a "Sales Demos" folder in Grafana Cloud (idempotent)
2. Reads `playbooks/files/grafana/cluster-health.json`
3. Pushes the dashboard via the Grafana HTTP API with `overwrite: true`

The dashboard covers cluster nodes, KubeVirt VMs, AAP platform health, and
logs. A `cluster` template variable makes it work for both sandbox and demo.

## Preflight Check

Run these before doing anything else. Every one must pass.

```bash
VAULT_ID="sales.demos@$HOME/secrets/.vault_pass_sales_demos"

# 1. Vault password file exists
test -s "$HOME/secrets/.vault_pass_sales_demos" \
  && echo "pass: vault password file" \
  || echo "FAIL: ~/secrets/.vault_pass_sales_demos missing"

# 2. secrets.yml exists and is vault-encrypted
head -c 15 playbooks/group_vars/all/secrets.yml 2>/dev/null | grep -q '^\$ANSIBLE_VAULT' \
  && echo "pass: secrets.yml is vault-encrypted" \
  || echo "FAIL: secrets.yml missing or NOT encrypted — see /sales-demos-first-time"

# 3. Grafana Cloud Editor SA token is filled in
ansible-vault view playbooks/group_vars/all/secrets.yml --vault-id "$VAULT_ID" 2>/dev/null \
  | python3 -c "
import sys, yaml
d = yaml.safe_load(sys.stdin) or {}
keys = ['grafana_cloud_url', 'grafana_cloud_editor_sa_token']
bad = [k for k in keys if d.get(k, 'CHANGEME') == 'CHANGEME' or k not in d]
print(('FAIL: missing or CHANGEME: ' + ', '.join(bad)) if bad
      else 'pass: Grafana Cloud dashboard credentials filled in')
"

# 4. Dashboard JSON exists
test -f playbooks/files/grafana/cluster-health.json \
  && echo "pass: dashboard JSON exists" \
  || echo "FAIL: playbooks/files/grafana/cluster-health.json missing"
```

If any check fails, stop and tell the user exactly which one and the fix shown
beside it. Do not attempt the run with a failing prerequisite.

### If the Editor SA token is missing

The user must create it manually in Grafana Cloud:

1. Administration > Service Accounts > Add
2. Name: `sales-demos-editor`, Role: **Editor**
3. Add token > copy the `glsa_...` value
4. Add to vault as `grafana_cloud_editor_sa_token`

This is separate from the Viewer SA token used by the MCP server.

## Run

```bash
mkdir -p ~/ansible-logs
export ANSIBLE_LOG_PATH=~/ansible-logs/deploy-dashboard-$(date +%F-%H%M).log

ansible-playbook playbooks/deploy_dashboard.yml -i inventory \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

**Always set `ANSIBLE_LOG_PATH`** — logs live outside the repo, in
`~/ansible-logs/`. Tell the user the path.

**No `--limit` needed.** This playbook targets localhost because Grafana Cloud
is a single external service. Do NOT pass `--limit sandbox` or `--limit demo`
— localhost is not in those groups and the play will skip with "no hosts
matched".

**`-i inventory` is required** even though the play targets localhost, because
Ansible needs the inventory path to resolve `group_vars/all/` for vault
variable loading.

This takes under 30 seconds.

## Verify via Grafana MCP

Use the Grafana MCP server to confirm the dashboard was pushed:

1. **Queries match:** `get_dashboard_panel_queries` with uid
   `sales-demos-cluster-health` — returns every panel's query expression. This
   is the fastest way to confirm a specific panel change landed.
2. **Dashboard exists:** `search_dashboards` with query `cluster health` —
   should return "Sales Demos - Cluster Health" in the "Sales Demos" folder.
3. **Full model:** `get_dashboard_by_uid` with uid
   `sales-demos-cluster-health` — returns the complete dashboard. Use
   `get_dashboard_property` with a JSONPath to check a specific field without
   pulling the whole model (e.g., `$.panels[*].options.textMode`).

Then open the dashboard URL printed by the playbook and confirm panels render
with live data.

## v1/v2 schema note

The playbook pushes via the legacy v1 API (`POST /api/dashboards/db`). This
Grafana Cloud stack stores dashboards in `v0alpha1` format
(`status.conversion.storedVersion`) and converts to v2 on read. The v1 write
path has been reliable for all fields so far, but if a future panel option
appears wrong in the live dashboard despite the v1 API returning the correct
value, check the v2 apiserver directly:

```
GET /apis/dashboard.grafana.app/v2/namespaces/stacks-1820169/dashboards/sales-demos-cluster-health
```

Compare `resourceVersion` and `generation` between the v2 response and what
the Grafana UI is rendering — a mismatch indicates read replica lag or a
stale client session, not a write failure.

## When it finishes

Report the dashboard URL and tell the user the dashboard is live in Grafana
Cloud. Remind them to select the `cluster` variable (e.g., `sandbox`) to see
data.

## If it fails

| Symptom | Cause | Fix |
|---|---|---|
| Assertion fails on `grafana_cloud_editor_sa_token` | Token not in vault | Create the Editor SA in Grafana Cloud UI, add to vault |
| `401 Unauthorized` | Token expired or revoked | Regenerate in Grafana Cloud > Service Accounts |
| `403 Forbidden` | Token has Viewer role, not Editor | Create a new SA with Editor role |
| `412 Precondition Failed` on folder creation | Folder already exists and was modified | Already handled by the playbook (accepts 200, 409, 412) |
| `Attempting to decrypt but no vault secrets found` | `--vault-id` missing | Add `--vault-id sales.demos@~/secrets/.vault_pass_sales_demos` |
| `no hosts matched` / skipping | `--limit` was passed | Remove `--limit` — this play targets localhost |

Never paste a Grafana Cloud URL or token into a commit message, issue, or PR.
This repo is public — see `CLAUDE.md`.
