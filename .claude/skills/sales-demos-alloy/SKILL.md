---
name: sales-demos-alloy
description: "Deploy Grafana Alloy on an OpenShift cluster to push metrics and logs to Grafana Cloud. Runs playbooks/deploy_alloy.yml. TRIGGER when: the user wants to deploy Alloy, set up Grafana Cloud observability, push metrics/logs to Grafana, or instrument a cluster. SKIP: if the user only wants to query Grafana Cloud (that is the MCP server from /sales-demos-mcp) or configure dashboards (Phase 2/3)."
---

# sales-demos-alloy

## There is an AAP path now too (#318)

`AAP Observability - 1 Deploy Alloy` runs the same playbook from AAP, per
environment. Deploy Alloy *before* pushing dashboards — a dashboard on a cluster
with no Alloy renders twelve empty panels, which is why the templates are
numbered.

Deploy Grafana Alloy on an OpenShift cluster to push metrics and logs to
Grafana Cloud. Issue [#265](https://github.com/ericcames/sales.demos/issues/265).

This skill contains **no logic**. All the work is in
[`playbooks/deploy_alloy.yml`](../../../playbooks/deploy_alloy.yml). See
`CLAUDE.md` → *Skills and playbooks*.

## What it does

Deploys Grafana Alloy as a DaemonSet in the `grafana-alloy` namespace:

1. **Prometheus federation** — federates selected series from the cluster's
   Prometheus endpoint (`prometheus-k8s`): KubeVirt VM metrics, node health,
   pod/container resource usage (namespace-filtered).
2. **AAP controller scrape** — scrapes `/api/controller/v2/metrics/` via the
   gateway (`aap.aap.svc`) with basic auth for `awx_*` and `django_*` metrics.
3. **Kubernetes API log streaming** — streams pod logs from four namespaces
   (`aap`, `sales-demos-<env>`, `openshift-cnv`, `grafana-alloy`) without
   hostPath volumes or elevated SCCs.

Everything pushes to Grafana Cloud's Prometheus (remote-write) and Loki
(push) endpoints.

**Budget:** ~2,098 Prometheus series (measured 2026-09-06) out of the 10k
free-tier limit.

## Reversal

```bash
ansible-playbook playbooks/deploy_alloy.yml -i inventory --limit sandbox \
  -e target_env=sandbox -e alloy_state=absent \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

Removes the DaemonSet, ConfigMap, Secrets, namespace, and all cluster-scoped
RBAC resources.

## Preflight Check

```bash
./utilities/preflight.sh "${ENV:-sandbox}" --k8s --grafana
```

If any check fails, stop and tell the user exactly which one and the fix shown
beside it. Do not attempt the run with a failing prerequisite.

## Collect inputs

Only one input, and it has a default:

| Variable | Default | Meaning |
|---|---|---|
| `ENV` (inventory limit) | `sandbox` | Which environment to target — `sandbox` or `demo` |

Everything else — Grafana Cloud endpoints, AAP credentials, cluster connection
— resolves from the vault and group_vars automatically.

## Run

```bash
mkdir -p ~/ansible-logs
export ANSIBLE_LOG_PATH=~/ansible-logs/deploy-alloy-sandbox-$(date +%F-%H%M).log

ansible-playbook playbooks/deploy_alloy.yml -i inventory --limit sandbox \
  -e target_env=sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

**Always set `ANSIBLE_LOG_PATH`** — logs live outside the repo, in
`~/ansible-logs/`. Tell the user the path.

**Never pipe through `tee`.** The exit status comes from `tee`, not
`ansible-playbook`.

**`--limit` is mandatory.** Without it the play matches every environment.

This takes about 2 minutes. The playbook is idempotent — a re-run converges.

## Verify it in the EE before merging a change

See `/sales-demos-verify-ee` for why and how. The one command:

```bash
utilities/run-in-ee.sh playbooks/deploy_alloy.yml \
  -i inventory --limit sandbox -e target_env=sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

## Verify on the cluster

**A green playbook run is not proof.** Ask the cluster.

```
# Alloy pods running?
mcp__openshift-<env>__resources_get  apps/v1 DaemonSet alloy
  namespace: grafana-alloy

# Alloy logs — look for "metrics sent" / errors
mcp__openshift-<env>__pods_log
  namespace: grafana-alloy
  labelSelector: app.kubernetes.io/name=alloy
  tailLines: 50
```

## Verify via Grafana MCP

Once data flows, use the Grafana MCP server to confirm:

1. **Metrics arriving:** `list_prometheus_metric_names` with regex
   `node_cpu_seconds_total` — should return results.
2. **AAP metrics arriving:** `list_prometheus_metric_names` with regex
   `awx_.*` — should return AAP-specific metrics.
3. **Scrape targets healthy:** `query_prometheus` with expr `up` — should
   show targets with value `1`.
4. **Logs arriving:** `list_loki_label_names` — should show `namespace`,
   `pod`, `container` labels.
5. **Series budget:** `query_prometheus` with expr
   `count({__name__!=""})` — should be under 10,000.

## When it finishes

Report the summary the playbook prints **and** the verification results, then
tell the user the cluster is now pushing metrics and logs to Grafana Cloud.

## If it fails

| Symptom | Cause | Fix |
|---|---|---|
| `401` / `Unauthorized` on the first task | RHDP bearer token expired | Refresh `openshift_api_token` in the vault |
| `Attempting to decrypt but no vault secrets found` | `--vault-id` missing | Add `--vault-id sales.demos@~/secrets/.vault_pass_sales_demos` |
| Grafana Cloud push credentials assertion fails | Push keys not set in vault | `ansible-vault edit` and fill in the 5 `grafana_cloud_*` push keys |
| Alloy pods `CrashLoopBackOff` | Config syntax error or bad credentials | Check logs: `mcp__openshift-<env>__pods_log` in `grafana-alloy` namespace |
| Federation returns 403 | SA missing `cluster-monitoring-view` | The playbook creates the CRB — re-run it |
| AAP metrics scrape fails | Gateway auth or TLS issue | Check Alloy logs; verify `aap_username`/`aap_password` in vault |
| Docker Hub rate limit on `grafana/alloy` pull | Too many pulls from this IP | Wait, or mirror the image to quay.io |

Never paste a live cluster hostname or token into a commit message, issue, or
PR. This repo is public — see `CLAUDE.md`.
