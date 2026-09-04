#!/usr/bin/env bash
# ===========================================================================
# make-aap-mcp.sh — register the AAP MCP server for one environment in the
# local Claude Code config. Issue #150.
#
#   bash utilities/make-aap-mcp.sh sandbox
#   bash utilities/make-aap-mcp.sh demo
#
# WHY THIS EXISTS. The AAP MCP server runs in the cluster (deployed by
# playbooks/mcp_server.yml, which setup.yml calls). The client side needs a
# bearer token, and tokens must not go in a tracked file, so the server is
# registered with `claude mcp add --scope local` instead of .mcp.json.
#
# This script automates what used to be a manual block in SKILL.md: resolve
# the AAP hostname and password from the vault, create a personal access
# token via the gateway API, find the MCP route, and register the server.
#
# THE TOKEN DOES NOT CLEAN ITSELF UP. An MCP client needs a durable
# credential, so it deliberately survives — the documented exception in
# CLAUDE.md. List and delete stale tokens with:
#
#   curl -sk -u "admin:<pass>" "https://<host>/api/gateway/v1/tokens/"
#   curl -sk -u "admin:<pass>" -X DELETE "https://<host>/api/gateway/v1/tokens/<id>/"
# ===========================================================================
set -euo pipefail

ENV_NAME="${1:-}"
if [[ -z "$ENV_NAME" ]]; then
  echo "usage: bash utilities/make-aap-mcp.sh <sandbox|demo>" >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [[ ! -d "inventory/group_vars/$ENV_NAME" ]]; then
  echo "❌ unknown environment '$ENV_NAME' — expected one of:" >&2
  ls -1 inventory/group_vars | grep -v '^aap$' | sed 's/^/     /' >&2
  exit 2
fi

VAULT_PASS="$HOME/secrets/.vault_pass_sales_demos"
VAULT_ID="sales.demos@$VAULT_PASS"
if [[ ! -s "$VAULT_PASS" ]]; then
  echo "❌ $VAULT_PASS missing — without it the committed secrets cannot be decrypted." >&2
  echo "   See /sales-demos-first-time, step 2." >&2
  exit 1
fi

KUBECONFIG_FILE="$REPO_ROOT/.kube/${ENV_NAME}.kubeconfig"
if [[ ! -s "$KUBECONFIG_FILE" ]]; then
  echo "❌ $KUBECONFIG_FILE missing — run 'bash utilities/make-kubeconfig.sh $ENV_NAME' first." >&2
  exit 1
fi

# --- Resolve AAP hostname and password from the vault ---------------------

AAP_HOST="$(ansible -i inventory --limit "$ENV_NAME" aap -m debug --vault-id "$VAULT_ID" \
  -a 'msg={{ aap_hostname }}' 2>/dev/null | sed -n 's/.*"msg": "\(.*\)"/\1/p')"

case "$AAP_HOST" in
  *.*) ;;
  *) echo "❌ could not resolve $ENV_NAME AAP hostname — got: ${AAP_HOST:0:60}" >&2; exit 1 ;;
esac

AAP_PASS="$(ansible-vault view playbooks/group_vars/all/secrets.yml --vault-id "$VAULT_ID" 2>/dev/null \
  | ENV_NAME="$ENV_NAME" python3 -c \
      'import sys,yaml,os; print(yaml.safe_load(sys.stdin)["env_secrets"][os.environ["ENV_NAME"]]["aap_password"])')"

if [[ -z "$AAP_PASS" ]]; then
  echo "❌ could not resolve $ENV_NAME AAP password from the vault" >&2
  exit 1
fi

# --- Find the MCP server route -------------------------------------------

MCP_HOST="$(KUBECONFIG="$KUBECONFIG_FILE" oc get route aap-mcp -n aap -o jsonpath='{.spec.host}' 2>/dev/null)" || true

if [[ -z "$MCP_HOST" ]]; then
  echo "❌ no aap-mcp route in namespace 'aap' on $ENV_NAME — has playbooks/mcp_server.yml run?" >&2
  exit 1
fi

# --- Create a personal access token --------------------------------------
# demo gets read scope; sandbox gets write scope.

if [[ "$ENV_NAME" == "demo" ]]; then
  TOKEN_SCOPE="read"
else
  TOKEN_SCOPE="write"
fi

TOKEN_DESC="sales.demos MCP ($ENV_NAME)"

TOKEN_RESPONSE="$(curl -sk -u "admin:$AAP_PASS" -X POST "https://$AAP_HOST/api/gateway/v1/tokens/" \
  -H 'Content-Type: application/json' \
  -d "{\"description\":\"$TOKEN_DESC\",\"scope\":\"$TOKEN_SCOPE\"}" 2>/dev/null)"

TOKEN="$(echo "$TOKEN_RESPONSE" | python3 -c 'import sys,json; print(json.load(sys.stdin)["token"])' 2>/dev/null)" || true

if [[ -z "$TOKEN" ]]; then
  echo "❌ failed to create token on $AAP_HOST" >&2
  echo "   response: ${TOKEN_RESPONSE:0:200}" >&2
  exit 1
fi

TOKEN_ID="$(echo "$TOKEN_RESPONSE" | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])' 2>/dev/null)"

# --- Register with Claude Code -------------------------------------------

claude mcp remove "aap-$ENV_NAME" 2>/dev/null || true

claude mcp add --transport http --scope local "aap-$ENV_NAME" "https://$MCP_HOST/mcp" \
  --header "Authorization: Bearer $TOKEN"

echo ""
echo "✅ registered aap-$ENV_NAME (scope: $TOKEN_SCOPE)"
echo "   environment : $ENV_NAME"
echo "   AAP host    : $AAP_HOST"
echo "   MCP route   : $MCP_HOST"
echo "   token id    : $TOKEN_ID"
echo "   token scope : $TOKEN_SCOPE"
echo ""
echo "⚠️  This token does not clean itself up — it is the documented exception."
echo "   To retire it later:"
echo "     curl -sk -u \"admin:<pass>\" -X DELETE \"https://$AAP_HOST/api/gateway/v1/tokens/$TOKEN_ID/\""
echo "   To list all tokens:"
echo "     curl -sk -u \"admin:<pass>\" \"https://$AAP_HOST/api/gateway/v1/tokens/\""
