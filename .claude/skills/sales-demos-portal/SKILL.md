---
name: sales-demos-portal
description: "Deploy the AAP self-service portal (Red Hat Developer Hub with the AAP plugin) via Helm chart into an RHDP environment. Runs playbooks/portal.yml, which creates the OAuth application, deploys the chart, and syncs the org list. TRIGGER when: the user wants to deploy the self-service portal, asks about RHDH or Developer Hub, or wants non-admin users to launch templates from a browser. SKIP: if the portal is already deployed and the user wants to use it, or if the user wants to install OpenShift Virtualization — that is ocpvirt-setup."
---

# sales-demos-portal

Deploy the AAP self-service portal into an RHDP environment. Takes about 11
minutes end to end.

This skill contains **no logic**. All the work is in
[`playbooks/portal.yml`](../../../playbooks/portal.yml). See `CLAUDE.md` →
*Skills and playbooks*.

## What it does

1. Creates a gateway OAuth application (delete + recreate — never PATCH
   `client_secret`, the gateway hashes differently and gives `invalid_client`).
2. Creates the `aap-portal` namespace, a durable service token, and three
   Secrets the chart expects.
3. Deploys `redhat-rhaap-portal` 2.1.0 via Helm.
4. Updates the OAuth redirect URI to the actual portal Route.
5. Syncs the org list from AAP so all organizations are visible.
6. Patches the portal ConfigMap: 1-minute sync interval, permissions disabled
   so non-admin users can see and launch templates.

## Preflight Check

Run these before doing anything else. Every one must pass.

```bash
ENV=${ENV:-sandbox}
VAULT_ID="sales.demos@$HOME/secrets/.vault_pass_sales_demos"

# 1. The vault password file exists.
test -s "$HOME/secrets/.vault_pass_sales_demos" \
  && echo "✅ vault password file" \
  || echo "❌ ~/secrets/.vault_pass_sales_demos missing — without it secrets.yml cannot be decrypted"

# 2. secrets.yml exists locally and is vault-encrypted, not plaintext.
#    It is gitignored (#130); a fresh clone will not have it.
head -c 15 playbooks/group_vars/all/secrets.yml 2>/dev/null | grep -q '^\$ANSIBLE_VAULT' \
  && echo "✅ secrets.yml is vault-encrypted" \
  || echo "❌ secrets.yml missing or NOT encrypted — see /sales-demos-first-time"

# 3. This environment's credentials are real, not placeholders.
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

# 4. kubernetes.core is installed
ansible-galaxy collection list kubernetes.core 2>/dev/null | grep -q kubernetes.core \
  && echo "✅ kubernetes.core" \
  || echo "❌ kubernetes.core — ansible-galaxy collection install -r collections/requirements.yml"

# 5. helm binary is available
command -v helm >/dev/null \
  && echo "✅ helm $(helm version --short 2>/dev/null)" \
  || echo "❌ helm not found — https://helm.sh/docs/intro/install/"

# 6. No project-local ansible.cfg shadowing ~/.ansible.cfg
test -f ansible.cfg \
  && echo "❌ project-local ansible.cfg present — it shadows ~/.ansible.cfg and breaks certified installs" \
  || echo "✅ no project-local ansible.cfg"
```

If any check fails, stop and tell the user exactly which one and the fix shown
beside it. Do not attempt the run with a failing prerequisite.

## Ensure the kubeconfig exists

The Helm module needs a kubeconfig file. Generate it if missing:

```bash
ENV=${ENV:-sandbox}

if [ -f ".kube/${ENV}.kubeconfig" ]; then
  echo "✅ kubeconfig exists for $ENV"
else
  echo "Generating kubeconfig for $ENV..."
  bash utilities/make-kubeconfig.sh "$ENV"
fi
```

## Confirm the cluster is reachable

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

export OCP_URL OCP_TOKEN

case "$OCP_URL" in https://*) ;; *) echo "❌ could not resolve $ENV API URL — check --limit"; esac
case "$OCP_TOKEN" in
  sha256~*) echo "✅ resolved $ENV credentials (OAuth token)" ;;
  eyJ*.*.*)  echo "✅ resolved $ENV credentials (ServiceAccount token)" ;;
  *) echo "❌ could not resolve $ENV token — check the vault password and that env_secrets.$ENV exists" ;;
esac
```

```bash
python3 - <<'PY'
import os, ssl, json, urllib.request
ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
req = urllib.request.Request(os.environ["OCP_URL"].rstrip("/") + "/apis",
                             headers={"Authorization": "Bearer " + os.environ["OCP_TOKEN"]})
groups = json.load(urllib.request.urlopen(req, context=ctx, timeout=20))["groups"]
print("✅ cluster reachable — %d API groups" % len(groups))
PY
```

## Collect inputs

Only one input, and it has a default. Ask the user only if it is ambiguous:

| Variable | Default | Meaning |
|---|---|---|
| `ENV` (inventory limit) | `sandbox` | Which environment to target — `sandbox` or `demo` |

## Run

```bash
mkdir -p ~/ansible-logs
export ANSIBLE_LOG_PATH=~/ansible-logs/portal-sandbox-$(date +%F-%H%M).log

ansible-playbook playbooks/portal.yml -i inventory --limit sandbox -e target_env=sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

**Always set `ANSIBLE_LOG_PATH`** — this run takes about 11 minutes and the log
is the only evidence left if it fails. Logs live outside the repo, in
`~/ansible-logs/`. Tell the user the path so they can find it later.

**Never pipe the run through `tee`.** In a pipeline the exit status comes from
`tee`, not `ansible-playbook`, so a failed run reports success.

Tell the user this takes about 11 minutes and stream the output.

## Verify on the cluster

**A green playbook run is not proof.** Ask the cluster using the
`openshift-sandbox` (or `openshift-demo`) MCP tools:

1. Check namespace exists: `pods_list_in_namespace` for `aap-portal`
2. Check deployment is ready: `resources_get` for Deployment
   `rhaap-portal-redhat-developer-hub` in `aap-portal`
3. Check Route exists: `resources_list` for Routes in `aap-portal`

Then open the portal URL in a browser. It should show the Red Hat Developer Hub
login page. Log in with the AAP credentials — templates from the configured
organizations should be visible.

## When it finishes

Report the playbook summary **and** the verification result above, then tell the
user the portal is live and accessible at the URL shown.

## If it fails

| Symptom | Cause | Fix |
|---|---|---|
| `401` / `Unauthorized` on the first task | RHDP bearer token expired | Refresh `openshift_api_token` in the vault, re-run `make-kubeconfig.sh` |
| `invalid_client` at `/o/token/` | OAuth client_secret was PATCHed instead of recreated | The playbook deletes and recreates; if this still happens, manually delete the `aap-selfservice-portal` application in the gateway |
| Helm deploy hangs or times out | Chart repo unreachable or cluster resources exhausted | Check `helm repo add openshift-charts https://charts.openshift.io/ && helm search repo redhat-rhaap-portal` |
| `rhaap-portal-app-config not found` | Helm deployment failed silently | Check the Helm release: `helm list -n aap-portal --kubeconfig .kube/<env>.kubeconfig` |
| Portal shows `UNRECOGNIZED` or no templates | Org sync not applied or still syncing | Wait 1 minute for the sync interval, or re-run the playbook |
| `Attempting to decrypt but no vault secrets found` | `--vault-id` missing from the command | Add `--vault-id sales.demos@~/secrets/.vault_pass_sales_demos` |

Never paste a live cluster hostname or token into a commit message, issue, or
PR. This repo is public — see `CLAUDE.md`.
