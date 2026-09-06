---
name: sales-demos-alloy
description: "Deploy Grafana Alloy on an OpenShift cluster to push metrics and logs to Grafana Cloud. Runs playbooks/deploy_alloy.yml. TRIGGER when: the user wants to deploy Alloy, set up Grafana Cloud observability, push metrics/logs to Grafana, or instrument a cluster. SKIP: if the user only wants to query Grafana Cloud (that is the MCP server from /sales-demos-mcp) or configure dashboards (Phase 2/3)."
---

# sales-demos-alloy

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

Run these before doing anything else. Every one must pass.

```bash
ENV=${ENV:-sandbox}
VAULT_ID="sales.demos@$HOME/secrets/.vault_pass_sales_demos"

# 1. Vault password file exists
test -s "$HOME/secrets/.vault_pass_sales_demos" \
  && echo "✅ vault password file" \
  || echo "❌ ~/secrets/.vault_pass_sales_demos missing"

# 2. secrets.yml exists and is vault-encrypted
head -c 15 playbooks/group_vars/all/secrets.yml 2>/dev/null | grep -q '^\$ANSIBLE_VAULT' \
  && echo "✅ secrets.yml is vault-encrypted" \
  || echo "❌ secrets.yml missing or NOT encrypted — see /sales-demos-first-time"

# 3. This environment's credentials are filled in
ansible-vault view playbooks/group_vars/all/secrets.yml --vault-id "$VAULT_ID" 2>/dev/null \
  | python3 -c "
import sys, yaml, os
env = os.environ.get('ENV', 'sandbox')
d = yaml.safe_load(sys.stdin) or {}
e = (d.get('env_secrets') or {}).get(env, {})
bad = [k for k, v in e.items() if 'CHANGEME' in str(v)]
print(('❌ ' + env + ' still has placeholders: ' + ', '.join(bad)) if bad
      else ('✅ ' + env + ' credentials filled in'))
"

# 4. Grafana Cloud push credentials are filled in
ansible-vault view playbooks/group_vars/all/secrets.yml --vault-id "$VAULT_ID" 2>/dev/null \
  | python3 -c "
import sys, yaml
d = yaml.safe_load(sys.stdin) or {}
keys = ['grafana_cloud_prom_push_url', 'grafana_cloud_prom_username',
        'grafana_cloud_loki_push_url', 'grafana_cloud_loki_username',
        'grafana_cloud_push_api_key']
bad = [k for k in keys if d.get(k, 'CHANGEME') == 'CHANGEME' or k not in d]
print(('❌ Grafana push credentials missing or CHANGEME: ' + ', '.join(bad)) if bad
      else '✅ Grafana Cloud push credentials filled in')
"

# 5. kubernetes.core and its python client are installed
ansible-galaxy collection list kubernetes.core 2>/dev/null | grep -q kubernetes.core \
  && echo "✅ kubernetes.core" \
  || echo "❌ kubernetes.core — ansible-galaxy collection install -r collections/requirements.yml"
python3 -c "import kubernetes" 2>/dev/null \
  && echo "✅ python kubernetes client" \
  || echo "❌ python kubernetes client — pip install kubernetes"

# 6. No project-local ansible.cfg
test -f ansible.cfg \
  && echo "❌ project-local ansible.cfg present — it shadows ~/.ansible.cfg" \
  || echo "✅ no project-local ansible.cfg"
```

If any check fails, stop and tell the user exactly which one and the fix shown
beside it. Do not attempt the run with a failing prerequisite.

## Confirm the cluster is reachable

Reuses the same credential-resolution pattern as `ocpvirt-setup`.

```bash
ENV=${ENV:-sandbox}
VAULT_ID="sales.demos@$HOME/secrets/.vault_pass_sales_demos"

OCP_URL=$(ansible -i inventory --limit "$ENV" aap -m debug --vault-id "$VAULT_ID" \
  -a 'msg={{ openshift_api_url }}' 2>/dev/null \
  | sed -n 's/.*"msg": "\(.*\)"/\1/p')

OCP_TOKEN=$(ansible-vault view playbooks/group_vars/all/secrets.yml \
  --vault-id "$VAULT_ID" 2>/dev/null \
  | ENV="$ENV" python3 -c \
    'import sys,yaml,os; print(yaml.safe_load(sys.stdin)["env_secrets"][os.environ["ENV"]]["openshift_api_token"])')

case "$OCP_URL" in https://*) ;; *) echo "❌ could not resolve $ENV API URL"; esac
case "$OCP_TOKEN" in
  sha256~*) echo "✅ resolved $ENV credentials (OAuth token)" ;;
  eyJ*.*.*)  echo "✅ resolved $ENV credentials (ServiceAccount token)" ;;
  *) echo "❌ could not resolve $ENV token" ;;
esac
```

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

```bash
utilities/run-in-ee.sh playbooks/deploy_alloy.yml \
  -i inventory --limit sandbox -e target_env=sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

## Verify on the cluster

**A green playbook run is not proof.** Ask the cluster.

```bash
# Alloy pods running?
oc --kubeconfig .kube/sandbox.kubeconfig get daemonset alloy -n grafana-alloy

# Alloy logs — look for "metrics sent" / errors
oc --kubeconfig .kube/sandbox.kubeconfig logs -n grafana-alloy -l app.kubernetes.io/name=alloy --tail=50
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
| Alloy pods `CrashLoopBackOff` | Config syntax error or bad credentials | Check logs: `oc logs -n grafana-alloy -l app.kubernetes.io/name=alloy` |
| Federation returns 403 | SA missing `cluster-monitoring-view` | The playbook creates the CRB — re-run it |
| AAP metrics scrape fails | Gateway auth or TLS issue | Check Alloy logs; verify `aap_username`/`aap_password` in vault |
| Docker Hub rate limit on `grafana/alloy` pull | Too many pulls from this IP | Wait, or mirror the image to quay.io |

Never paste a live cluster hostname or token into a commit message, issue, or
PR. This repo is public — see `CLAUDE.md`.
