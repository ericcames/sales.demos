#!/usr/bin/env bash
# ===========================================================================
# make-ao-mcp.sh — register the Automation Orchestrator MCP server for one
# environment in the local Claude Code config. Issue #464.
#
#   bash utilities/make-ao-mcp.sh sandbox
#   bash utilities/make-ao-mcp.sh demo
#
# WHY THIS IS LOCAL, NOT COMMITTED. The AO admin password is a credential —
# it cannot go in .mcp.json. The server is registered with
# `claude mcp add --scope local` instead.
#
# The server reads credentials from environment variables set on the
# `claude mcp add` entry:
#   AO_URL       — derived from the AO Route in the cluster
#   AO_USERNAME  — defaults to "admin"
#   AO_PASSWORD  — the AO admin password (= AAP admin password, #143)
#
# PREREQUISITES:
#   - python3 with the `mcp` package installed (pip install mcp)
#   - the vault password file at ~/secrets/.vault_pass_sales_demos
#   - a valid kubeconfig at .kube/<env>.kubeconfig (run make-kubeconfig.sh)
# ===========================================================================
set -euo pipefail

ENV="${1:-}"
if [[ -z "$ENV" ]]; then
  echo "Usage: $0 <environment>" >&2
  echo "  e.g. $0 sandbox" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VAULT_ID="sales.demos@${HOME}/secrets/.vault_pass_sales_demos"
KUBECONFIG_PATH="${REPO_ROOT}/.kube/${ENV}.kubeconfig"

# --- Validate prerequisites -----------------------------------------------

if [[ ! -f "$HOME/secrets/.vault_pass_sales_demos" ]]; then
  echo "❌ Vault password file missing: ~/secrets/.vault_pass_sales_demos" >&2
  exit 1
fi

if [[ ! -f "${REPO_ROOT}/playbooks/group_vars/all/secrets.yml" ]]; then
  echo "❌ secrets.yml missing — see /sales-demos-first-time" >&2
  exit 1
fi

if [[ ! -f "$KUBECONFIG_PATH" ]]; then
  echo "❌ Kubeconfig missing: ${KUBECONFIG_PATH}" >&2
  echo "   Run: bash utilities/make-kubeconfig.sh ${ENV}" >&2
  exit 1
fi

if ! python3 -c "import mcp" 2>/dev/null; then
  echo "❌ Python mcp package not installed" >&2
  echo "   Run: pip install mcp" >&2
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "❌ claude CLI not found" >&2
  exit 1
fi

# --- Resolve credentials from the vault ------------------------------------

echo "Reading credentials from the vault for '${ENV}'..."
AO_PASSWORD="$(ansible-vault view "${REPO_ROOT}/playbooks/group_vars/all/secrets.yml" \
  --vault-id "$VAULT_ID" 2>/dev/null \
  | python3 -c "import sys,yaml; d=yaml.safe_load(sys.stdin); print(d['env_secrets']['${ENV}']['aap_password'])")"

if [[ -z "$AO_PASSWORD" ]]; then
  echo "❌ Could not read aap_password for '${ENV}' from the vault" >&2
  exit 1
fi

# --- Find the AO Route -----------------------------------------------------

echo "Finding AO Route in the cluster..."
AO_HOST="$(KUBECONFIG="$KUBECONFIG_PATH" oc get route ao \
  -n automation-orchestrator \
  -o jsonpath='{.spec.host}' 2>/dev/null || true)"

if [[ -z "$AO_HOST" ]]; then
  echo "❌ No AO Route found in automation-orchestrator namespace" >&2
  echo "   Is Automation Orchestrator installed? Run /sales-demos-orchestrator" >&2
  exit 1
fi

AO_URL="https://${AO_HOST}"
echo "  AO URL: ${AO_URL}"

# --- Verify AO is reachable ------------------------------------------------

HTTP_CODE="$(curl -sk -o /dev/null -w '%{http_code}' "${AO_URL}" 2>/dev/null || echo "000")"
if [[ "$HTTP_CODE" != "200" ]]; then
  echo "❌ AO Route returned HTTP ${HTTP_CODE} — is AO running?" >&2
  exit 1
fi
echo "  AO is reachable (HTTP 200)"

# --- Verify login works ----------------------------------------------------

echo "Testing AO login..."
LOGIN_CODE="$(curl -sk -o /dev/null -w '%{http_code}' -X POST "${AO_URL}/api/v1/auth/login" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"admin\",\"password\":\"${AO_PASSWORD}\"}" 2>/dev/null || echo "000")"
if [[ "$LOGIN_CODE" != "200" ]]; then
  echo "❌ AO login failed (HTTP ${LOGIN_CODE})" >&2
  echo "   The AO admin password may not match the AAP admin password." >&2
  echo "   If this environment was built before #143, retrieve the password with:" >&2
  echo "     oc get secret ao-initial-admin-password -n automation-orchestrator -o jsonpath='{.data.password}' | base64 -d" >&2
  exit 1
fi
echo "  Login successful"

# --- Register the MCP server -----------------------------------------------

SERVER_NAME="ao-${ENV}"
SERVER_SCRIPT="${REPO_ROOT}/utilities/ao-mcp-server.py"

echo "Registering MCP server '${SERVER_NAME}'..."

# Remove existing registration if present
claude mcp remove "${SERVER_NAME}" 2>/dev/null || true

claude mcp add "${SERVER_NAME}" --scope local \
  -e "AO_URL=${AO_URL}" \
  -e "AO_USERNAME=admin" \
  -e "AO_PASSWORD=${AO_PASSWORD}" \
  -- python3 "${SERVER_SCRIPT}"

echo ""
echo "✅ MCP server '${SERVER_NAME}' registered"
echo ""
echo "Restart Claude Code for the new server to take effect."
echo "After restart, verify with: mcp__${SERVER_NAME}__version"
echo ""
echo "To remove:"
echo "  claude mcp remove ${SERVER_NAME}"
