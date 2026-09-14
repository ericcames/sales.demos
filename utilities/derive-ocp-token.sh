#!/usr/bin/env bash
# ===========================================================================
# derive-ocp-token.sh — derive openshift_api_token from kubeadmin_password.
# Issue #559.
#
#   bash utilities/derive-ocp-token.sh sandbox
#   bash utilities/derive-ocp-token.sh demo --update-vault
#
# The RHDP portal renders bearer tokens with em dashes instead of hyphens,
# corrupting the JWT signature on copy-paste. kubeadmin_password is
# alphanumeric and safe. This script replaces the manual copy-paste with a
# two-step derivation:
#
#   1. OAuth with kubeadmin → short-lived sha256~ token
#   2. Read the long-lived ServiceAccount JWT from the cluster
#
# If the cluster-admin ServiceAccount or its token Secret do not exist, the
# script creates them — so it works on any cluster where kubeadmin works,
# including edge and new RHDP catalog items.
#
# The structure follows make-kubeconfig.sh: same env validation from the
# inventory tree, same vault password handling via SALES_DEMOS_VAULT_PASS,
# same shape checks.
# ===========================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

SA_NAME="cluster-admin"
SA_NAMESPACE="openshift-config"
SECRET_NAME="cluster-admin-token"
CRB_NAME="cluster-admin-sa-binding"

# ── Environment validation ─────────────────────────────────────────────
environments() { ls -1 inventory/group_vars | grep -v '^aap$'; }

ENV_NAME="${1:-}"
if [[ -z "$ENV_NAME" ]]; then
  echo "usage: bash utilities/derive-ocp-token.sh <$(environments | paste -sd'|')> [--update-vault]" >&2
  exit 2
fi

if [[ ! -d "inventory/group_vars/$ENV_NAME" ]]; then
  echo "❌ unknown environment '$ENV_NAME' — expected one of:" >&2
  environments | sed 's/^/     /' >&2
  exit 2
fi
shift

UPDATE_VAULT=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --update-vault) UPDATE_VAULT=true ;;
    *) echo "Unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

# ── Vault password ─────────────────────────────────────────────────────
VAULT_PASS="${SALES_DEMOS_VAULT_PASS:-$HOME/secrets/.vault_pass_sales_demos}"
VAULT_ID="sales.demos@$VAULT_PASS"
if [[ ! -s "$VAULT_PASS" ]]; then
  echo "❌ $VAULT_PASS missing — without it the secrets file cannot be decrypted." >&2
  echo "   Build it with /sales-demos-first-time, step 2, or set" >&2
  echo "   SALES_DEMOS_VAULT_PASS if yours lives somewhere else." >&2
  exit 1
fi

# ── Resolve inventory values (respects local.yml overrides) ────────────
APPS_DOMAIN="$(ansible -i inventory --limit "$ENV_NAME" aap -m debug --vault-id "$VAULT_ID" \
  -a 'msg={{ openshift_apps_domain }}' 2>/dev/null | sed -n 's/.*"msg": "\(.*\)"/\1/p')"

API_URL="$(ansible -i inventory --limit "$ENV_NAME" aap -m debug --vault-id "$VAULT_ID" \
  -a 'msg={{ openshift_api_url }}' 2>/dev/null | sed -n 's/.*"msg": "\(.*\)"/\1/p')"

case "$APPS_DOMAIN" in
  *.*)  ;;
  *) echo "❌ could not resolve $ENV_NAME apps domain — got: ${APPS_DOMAIN:0:60}" >&2; exit 1 ;;
esac
case "$API_URL" in
  https://*) ;;
  *) echo "❌ could not resolve $ENV_NAME API URL — got: ${API_URL:0:60}" >&2; exit 1 ;;
esac

# ── Read kubeadmin_password from vault ─────────────────────────────────
KUBEADMIN_PASS="$(ansible-vault view playbooks/group_vars/all/secrets.yml --vault-id "$VAULT_ID" 2>/dev/null \
  | ENV_NAME="$ENV_NAME" python3 -c \
    'import sys,yaml,os; print(yaml.safe_load(sys.stdin)["env_secrets"][os.environ["ENV_NAME"]]["kubeadmin_password"])')"

if [[ -z "$KUBEADMIN_PASS" || "$KUBEADMIN_PASS" == *CHANGEME* ]]; then
  echo "❌ kubeadmin_password for $ENV_NAME is missing or still CHANGEME in the vault" >&2
  exit 1
fi

# ── Step 1: OAuth with kubeadmin to get a short-lived token ────────────
OAUTH_URL="https://oauth-openshift.${APPS_DOMAIN}/oauth/authorize?response_type=token&client_id=openshift-challenging-client"

REDIRECT_HEADERS="$(curl -skI -u "kubeadmin:${KUBEADMIN_PASS}" \
  --max-time 15 "$OAUTH_URL" 2>/dev/null || true)"

OAUTH_TOKEN="$(echo "$REDIRECT_HEADERS" \
  | grep -i '^location:' | tr -d '\r' \
  | sed -n 's/.*access_token=\([^&]*\).*/\1/p')"

if [[ -z "$OAUTH_TOKEN" ]]; then
  echo "❌ OAuth failed for $ENV_NAME" >&2
  echo "   URL:  $OAUTH_URL" >&2
  echo "   Check kubeadmin_password in the vault and cluster reachability." >&2
  if echo "$REDIRECT_HEADERS" | grep -qi '401\|unauthorized'; then
    echo "   The server returned 401 — kubeadmin_password is likely wrong." >&2
  fi
  exit 1
fi
echo "✅ OAuth succeeded — got short-lived token"

# ── Step 2: Ensure SA + Secret exist ───────────────────────────────────
api_call() {
  local method="$1" path="$2" data="${3:-}"
  local args=(-sk -X "$method" -H "Authorization: Bearer ${OAUTH_TOKEN}"
              -H "Content-Type: application/json"
              --max-time 15)
  [[ -n "$data" ]] && args+=(-d "$data")
  curl "${args[@]}" "${API_URL}${path}" 2>/dev/null
}

SECRET_RESP="$(api_call GET "/api/v1/namespaces/${SA_NAMESPACE}/secrets/${SECRET_NAME}")"
SECRET_CODE="$(echo "$SECRET_RESP" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("code","200"))' 2>/dev/null || echo "error")"

if [[ "$SECRET_CODE" == "404" ]]; then
  echo "   cluster-admin-token Secret not found — creating SA, ClusterRoleBinding, and Secret..."

  # Create ServiceAccount (ignore 409 = already exists)
  SA_RESP="$(api_call POST "/api/v1/namespaces/${SA_NAMESPACE}/serviceaccounts" \
    "{\"apiVersion\":\"v1\",\"kind\":\"ServiceAccount\",\"metadata\":{\"name\":\"${SA_NAME}\",\"namespace\":\"${SA_NAMESPACE}\"}}")"
  SA_CODE="$(echo "$SA_RESP" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("code","200"))' 2>/dev/null || echo "error")"
  if [[ "$SA_CODE" != "200" && "$SA_CODE" != "409" ]]; then
    echo "❌ Failed to create ServiceAccount $SA_NAME in $SA_NAMESPACE" >&2
    echo "   Response: $(echo "$SA_RESP" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("message","unknown"))' 2>/dev/null)" >&2
    exit 1
  fi

  # Create ClusterRoleBinding (ignore 409)
  CRB_RESP="$(api_call POST "/apis/rbac.authorization.k8s.io/v1/clusterrolebindings" \
    "{\"apiVersion\":\"rbac.authorization.k8s.io/v1\",\"kind\":\"ClusterRoleBinding\",\"metadata\":{\"name\":\"${CRB_NAME}\"},\"subjects\":[{\"kind\":\"ServiceAccount\",\"name\":\"${SA_NAME}\",\"namespace\":\"${SA_NAMESPACE}\"}],\"roleRef\":{\"apiGroup\":\"rbac.authorization.k8s.io\",\"kind\":\"ClusterRole\",\"name\":\"cluster-admin\"}}")"
  CRB_CODE="$(echo "$CRB_RESP" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("code","200"))' 2>/dev/null || echo "error")"
  if [[ "$CRB_CODE" != "200" && "$CRB_CODE" != "409" ]]; then
    echo "❌ Failed to create ClusterRoleBinding $CRB_NAME" >&2
    echo "   Response: $(echo "$CRB_RESP" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("message","unknown"))' 2>/dev/null)" >&2
    exit 1
  fi

  # Create the long-lived token Secret
  SEC_RESP="$(api_call POST "/api/v1/namespaces/${SA_NAMESPACE}/secrets" \
    "{\"apiVersion\":\"v1\",\"kind\":\"Secret\",\"metadata\":{\"name\":\"${SECRET_NAME}\",\"namespace\":\"${SA_NAMESPACE}\",\"annotations\":{\"kubernetes.io/service-account.name\":\"${SA_NAME}\"}},\"type\":\"kubernetes.io/service-account-token\"}")"
  SEC_CODE="$(echo "$SEC_RESP" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("code","200"))' 2>/dev/null || echo "error")"
  if [[ "$SEC_CODE" != "200" && "$SEC_CODE" != "201" ]]; then
    echo "❌ Failed to create Secret $SECRET_NAME in $SA_NAMESPACE" >&2
    echo "   Response: $(echo "$SEC_RESP" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("message","unknown"))' 2>/dev/null)" >&2
    exit 1
  fi

  echo "   ✅ Created SA, ClusterRoleBinding, and Secret"

  # Wait for the token controller to populate the Secret
  for i in $(seq 1 10); do
    SECRET_RESP="$(api_call GET "/api/v1/namespaces/${SA_NAMESPACE}/secrets/${SECRET_NAME}")"
    HAS_TOKEN="$(echo "$SECRET_RESP" | python3 -c 'import sys,json; print("yes" if json.load(sys.stdin).get("data",{}).get("token") else "no")' 2>/dev/null || echo "no")"
    [[ "$HAS_TOKEN" == "yes" ]] && break
    sleep 1
  done
  if [[ "$HAS_TOKEN" != "yes" ]]; then
    echo "❌ Token controller did not populate the Secret within 10 seconds" >&2
    exit 1
  fi
fi

# ── Step 3: Read the SA token ──────────────────────────────────────────
SA_TOKEN="$(echo "$SECRET_RESP" | python3 -c \
  'import sys,json,base64; print(base64.b64decode(json.load(sys.stdin)["data"]["token"]).decode().strip())')"

if [[ -z "$SA_TOKEN" ]]; then
  echo "❌ Could not extract token from Secret $SECRET_NAME" >&2
  exit 1
fi

# Shape check: must be a ServiceAccount JWT (eyJ prefix, three dot-separated parts)
case "$SA_TOKEN" in
  eyJ*.*.*)  ;;
  *) echo "❌ Derived token has unexpected shape — expected a ServiceAccount JWT (eyJ...)" >&2; exit 1 ;;
esac

# Belt-and-suspenders: reject non-ASCII (should never happen for a JWT)
if echo "$SA_TOKEN" | grep -qP '[^\x00-\x7F]'; then
  echo "❌ Derived token contains non-ASCII characters — this should not happen" >&2
  exit 1
fi

echo "✅ Derived long-lived ServiceAccount token for $ENV_NAME"

# ── Step 4: Output or update vault ─────────────────────────────────────
if $UPDATE_VAULT; then
  SECRETS_FILE="$REPO_ROOT/playbooks/group_vars/all/secrets.yml"
  if [[ ! -f "$SECRETS_FILE" ]]; then
    echo "❌ $SECRETS_FILE does not exist — run /sales-demos-first-time first" >&2
    exit 1
  fi

  TMPFILE="$(mktemp)"
  trap 'rm -f "$TMPFILE"' EXIT

  ansible-vault view "$SECRETS_FILE" --vault-id "$VAULT_ID" 2>/dev/null \
    | ENV_NAME="$ENV_NAME" SA_TOKEN="$SA_TOKEN" python3 -c "
import sys, yaml, os
data = yaml.safe_load(sys.stdin)
data['env_secrets'][os.environ['ENV_NAME']]['openshift_api_token'] = os.environ['SA_TOKEN']
yaml.dump(data, sys.stdout, default_flow_style=False, width=200)
" > "$TMPFILE"

  ansible-vault encrypt "$TMPFILE" --vault-id "$VAULT_ID" 2>/dev/null
  cp "$TMPFILE" "$SECRETS_FILE"
  chmod 600 "$SECRETS_FILE"

  echo "✅ Updated openshift_api_token in the vault for $ENV_NAME"
else
  echo "$SA_TOKEN"
fi
