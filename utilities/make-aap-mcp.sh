#!/usr/bin/env bash
# ===========================================================================
# make-aap-mcp.sh — create an AAP MCP bearer token and write the credential
# files that .mcp.json needs to connect. Issue #515 (replaces #150).
#
#   bash utilities/make-aap-mcp.sh sandbox
#   bash utilities/make-aap-mcp.sh demo
#
# WHY THIS EXISTS. The AAP MCP server runs in the cluster (deployed by
# playbooks/mcp_server.yml). The client side needs a bearer token, and tokens
# must not go in a tracked file, so .mcp.json calls a wrapper script
# (utilities/aap-mcp-stdio.sh) that reads the token from a gitignored file.
#
# This script resolves the AAP hostname and password from the vault, finds
# the MCP route, creates a personal access token via the gateway API, and
# writes the token and URL to .aap/<env>.token and .aap/<env>.url.
#
# TOKEN SCOPE IS ALWAYS WRITE. Server-side enforcement
# (aap_mcp_allow_write_operations) is the real guard, not the token scope.
# During setup the server runs write-enabled; after setup it can be toggled
# to read-only without changing the token or restarting Claude Code.
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

VAULT_PASS="${SALES_DEMOS_VAULT_PASS:-$HOME/secrets/.vault_pass_sales_demos}"
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

# --- Migration: remove the pre-#515 registration, then prove it is gone -----
# Before #515, the server was registered with `claude mcp add --scope local`
# as an HTTP entry with the URL inline. Local scope outranks .mcp.json, so
# while that entry exists the stdio wrapper never runs and the .aap/ files
# written below are never read.
#
# THIS USED TO BE `claude mcp remove "aap-$ENV" 2>/dev/null || true` (#603).
# With the name in two scopes and no -s, it removed nothing, and the discarded
# error hid that: the previous cluster survived every regeneration and
# restart. So remove from local scope explicitly, treat only "not in local
# scope" as success, and then ask which scope actually wins.
#
# Local scope is keyed on the absolute project path, so run from the main
# checkout: a worktree is a different project to Claude Code.
MAIN_ROOT="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"

if command -v claude >/dev/null 2>&1; then
  if out="$(cd "$MAIN_ROOT" && claude mcp remove "aap-$ENV_NAME" -s local 2>&1)"; then
    echo "🧹 removed a pre-#515 local-scope aap-$ENV_NAME registration"
  elif [[ "$out" != *"in local scope"* ]]; then
    echo "❌ could not remove the local-scope aap-$ENV_NAME registration:" >&2
    echo "   $out" >&2
    exit 1
  fi

  winner="$(cd "$MAIN_ROOT" && claude mcp get "aap-$ENV_NAME" 2>/dev/null \
    | sed -n 's/^ *Scope: //p')" || true
  case "$winner" in
    "Project config"*) ;;
    "")
      echo "❌ Claude Code has no aap-$ENV_NAME server in $MAIN_ROOT — is .mcp.json intact?" >&2
      exit 1
      ;;
    *)
      echo "❌ aap-$ENV_NAME resolves from '$winner', not .mcp.json — it would ignore .aap/." >&2
      echo "   inspect: (cd $MAIN_ROOT && claude mcp get aap-$ENV_NAME)" >&2
      exit 1
      ;;
  esac
else
  echo "⚠️  claude CLI not on PATH — cannot check for a registration shadowing .mcp.json." >&2
  echo "   Run 'bash utilities/check-mcp-staleness.sh $ENV_NAME' where it is." >&2
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

TOKEN_SCOPE="write"
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

# --- Write credential files for the stdio bridge -------------------------

mkdir -p "$REPO_ROOT/.aap" && chmod 700 "$REPO_ROOT/.aap"

printf '%s\n' "$TOKEN" > "$REPO_ROOT/.aap/${ENV_NAME}.token"
chmod 600 "$REPO_ROOT/.aap/${ENV_NAME}.token"

printf '%s\n' "https://$MCP_HOST" > "$REPO_ROOT/.aap/${ENV_NAME}.url"
chmod 600 "$REPO_ROOT/.aap/${ENV_NAME}.url"

echo ""
echo "✅ aap-$ENV_NAME credentials written"
echo "   environment : $ENV_NAME"
echo "   AAP host    : $AAP_HOST"
echo "   MCP route   : $MCP_HOST"
echo "   token id    : $TOKEN_ID"
echo "   token scope : $TOKEN_SCOPE"
echo "   token file  : .aap/${ENV_NAME}.token"
echo "   url file    : .aap/${ENV_NAME}.url"
echo ""
echo "   Restart Claude Code to bring aap-$ENV_NAME online."
echo ""
echo "⚠️  This token does not clean itself up — it is the documented exception."
echo "   To retire it later:"
echo "     curl -sk -u \"admin:<pass>\" -X DELETE \"https://$AAP_HOST/api/gateway/v1/tokens/$TOKEN_ID/\""
echo "   To list all tokens:"
echo "     curl -sk -u \"admin:<pass>\" \"https://$AAP_HOST/api/gateway/v1/tokens/\""
