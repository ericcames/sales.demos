#!/usr/bin/env bash
# ===========================================================================
# preflight.sh — shared preflight checks for sales.demos skills.
#
# Issue #456. Skills repeat the same vault-password / secrets-file /
# CHANGEME-scan checks, and drift already shows: the stated reason for
# "never tee" differs between skills, and the CHANGEME logic differs
# between pah-sync and sales-demos-dashboard. This script is the single
# implementation; skills call it and add any skill-specific checks after.
#
#   ./utilities/preflight.sh sandbox
#   ./utilities/preflight.sh demo --k8s
#   ./utilities/preflight.sh sandbox --k8s --hub-token
#   ./utilities/preflight.sh sandbox --grafana --grafana-editor
# ===========================================================================
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

ENVS=$(ls -1 inventory/group_vars/ | grep -v '^aap$' | sort)

usage() {
  echo "Usage: $0 <env> [--k8s] [--hub-token] [--grafana] [--grafana-editor] [--terraform]"
  echo ""
  echo "Environments: $(echo $ENVS | tr '\n' ' ')"
  echo ""
  echo "Flags:"
  echo "  --k8s            Check kubernetes.core collection and python client"
  echo "  --hub-token      Check Red Hat offline token in ~/.ansible.cfg"
  echo "  --grafana        Check Grafana Cloud push credentials in vault"
  echo "  --grafana-editor Check Grafana Cloud editor SA token in vault"
  echo "  --terraform      Check terraform binary on PATH"
  exit 1
}

[ $# -ge 1 ] || usage
ENV="$1"; shift

if ! echo "$ENVS" | grep -qx "$ENV"; then
  echo "❌ Unknown environment: $ENV"
  echo "   Available: $(echo $ENVS | tr '\n' ' ')"
  exit 1
fi

want_k8s=false
want_hub_token=false
want_grafana=false
want_grafana_editor=false
want_terraform=false

while [ $# -gt 0 ]; do
  case "$1" in
    --k8s)             want_k8s=true ;;
    --hub-token)       want_hub_token=true ;;
    --grafana)         want_grafana=true ;;
    --grafana-editor)  want_grafana_editor=true ;;
    --terraform)       want_terraform=true ;;
    *) echo "Unknown flag: $1"; usage ;;
  esac
  shift
done

VAULT_ID="sales.demos@$HOME/secrets/.vault_pass_sales_demos"
fail=0

# ── Core checks (every skill) ──────────────────────────────────────────

# 1. Vault password file
if test -s "$HOME/secrets/.vault_pass_sales_demos"; then
  echo "✅ vault password file"
else
  echo "❌ ~/secrets/.vault_pass_sales_demos missing — without it secrets.yml cannot be decrypted"
  fail=1
fi

# 2. secrets.yml exists and is vault-encrypted
if head -c 15 playbooks/group_vars/all/secrets.yml 2>/dev/null | grep -q '^\$ANSIBLE_VAULT'; then
  echo "✅ secrets.yml is vault-encrypted"
else
  echo "❌ secrets.yml missing or NOT encrypted — see /sales-demos-first-time"
  fail=1
fi

# 3. No CHANGEME placeholders in this environment's credentials
if ansible-vault view playbooks/group_vars/all/secrets.yml --vault-id "$VAULT_ID" 2>/dev/null \
  | ENV="$ENV" python3 -c "
import sys, yaml, os
env = os.environ['ENV']
d = yaml.safe_load(sys.stdin) or {}
e = (d.get('env_secrets') or {}).get(env, {})
bad = [k for k, v in e.items() if 'CHANGEME' in str(v)]
if bad:
    print('❌ ' + env + ' still has placeholders: ' + ', '.join(bad))
    sys.exit(1)
print('✅ ' + env + ' credentials filled in')
"; then
  :
else
  fail=1
fi

# 4. No project-local ansible.cfg
if test -f ansible.cfg; then
  echo "❌ project-local ansible.cfg present — it shadows ~/.ansible.cfg and breaks certified installs"
  fail=1
else
  echo "✅ no project-local ansible.cfg"
fi

# ── Optional checks ────────────────────────────────────────────────────

if $want_k8s; then
  if ansible-galaxy collection list kubernetes.core 2>/dev/null | grep -q kubernetes.core; then
    echo "✅ kubernetes.core"
  else
    echo "❌ kubernetes.core — ansible-galaxy collection install -r collections/requirements.yml"
    fail=1
  fi
  if python3 -c "import kubernetes" 2>/dev/null; then
    echo "✅ python kubernetes client"
  else
    echo "❌ python kubernetes client — pip install kubernetes"
    fail=1
  fi
fi

if $want_hub_token; then
  if python3 - <<'PY'
import configparser, os
c = configparser.ConfigParser(); c.read(os.path.expanduser("~/.ansible.cfg"))
t = c.get("galaxy_server.rh_certified", "token", fallback="")
if len(t) > 100:
    print("✅ offline token present ({} chars)".format(len(t)))
else:
    print("❌ no offline token in ~/.ansible.cfg [galaxy_server.rh_certified] —"
          " get one at https://console.redhat.com/ansible/automation-hub/token")
    raise SystemExit(1)
PY
  then :; else fail=1; fi
fi

if $want_grafana; then
  if ansible-vault view playbooks/group_vars/all/secrets.yml --vault-id "$VAULT_ID" 2>/dev/null \
    | python3 -c "
import sys, yaml
d = yaml.safe_load(sys.stdin) or {}
keys = ['grafana_cloud_prom_push_url', 'grafana_cloud_prom_username',
        'grafana_cloud_loki_push_url', 'grafana_cloud_loki_username',
        'grafana_cloud_push_api_key']
bad = [k for k in keys if d.get(k, 'CHANGEME') == 'CHANGEME' or k not in d]
if bad:
    print('❌ Grafana push credentials missing or CHANGEME: ' + ', '.join(bad))
    raise SystemExit(1)
print('✅ Grafana Cloud push credentials filled in')
"; then :; else fail=1; fi
fi

if $want_grafana_editor; then
  if ansible-vault view playbooks/group_vars/all/secrets.yml --vault-id "$VAULT_ID" 2>/dev/null \
    | python3 -c "
import sys, yaml
d = yaml.safe_load(sys.stdin) or {}
keys = ['grafana_cloud_url', 'grafana_cloud_editor_sa_token']
bad = [k for k in keys if d.get(k, 'CHANGEME') == 'CHANGEME' or k not in d]
if bad:
    print('❌ Grafana editor credentials missing or CHANGEME: ' + ', '.join(bad))
    raise SystemExit(1)
print('✅ Grafana Cloud editor credentials filled in')
"; then :; else fail=1; fi
fi

if $want_terraform; then
  if command -v terraform >/dev/null; then
    echo "✅ $(terraform version | head -1)"
  else
    echo "❌ terraform not installed"
    fail=1
  fi
fi

# ── Verdict ─────────────────────────────────────────────────────────────

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "Preflight FAILED — fix the items above before running."
  exit 1
fi

echo ""
echo "Preflight passed for $ENV."
