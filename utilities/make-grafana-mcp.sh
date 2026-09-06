#!/usr/bin/env bash
# ===========================================================================
# make-grafana-mcp.sh — register the Grafana Cloud MCP server in the local
# Claude Code config. Issue #260.
#
#   bash utilities/make-grafana-mcp.sh
#
# WHY THIS EXISTS. Grafana Cloud is an external SaaS instance, not tied to
# any RHDP environment. The service account token must not go in a tracked
# file, so the server is registered with `claude mcp add --scope local`
# instead of .mcp.json — the same pattern as the AAP MCP servers (#150).
#
# Unlike make-aap-mcp.sh, this takes NO arguments — there is one Grafana
# Cloud instance, not one per environment.
#
# THE TOKEN DOES NOT CLEAN ITSELF UP. It is created in the Grafana Cloud UI
# and must be revoked there:
#   Administration > Service Accounts > <account> > Tokens > Delete
# ===========================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

VAULT_PASS="$HOME/secrets/.vault_pass_sales_demos"
VAULT_ID="sales.demos@$VAULT_PASS"
if [[ ! -s "$VAULT_PASS" ]]; then
  echo "❌ $VAULT_PASS missing — without it the committed secrets cannot be decrypted." >&2
  echo "   See /sales-demos-first-time, step 2." >&2
  exit 1
fi

if ! command -v uvx >/dev/null 2>&1; then
  echo "❌ uvx not found — install uv (https://docs.astral.sh/uv/getting-started/installation/)" >&2
  exit 1
fi

# --- Resolve Grafana Cloud credentials from the vault --------------------

VAULT_CONTENT="$(ansible-vault view playbooks/group_vars/all/secrets.yml --vault-id "$VAULT_ID" 2>/dev/null)"

GRAFANA_URL="$(echo "$VAULT_CONTENT" \
  | python3 -c 'import sys,yaml; print(yaml.safe_load(sys.stdin)["grafana_cloud_url"])')" || true

GRAFANA_TOKEN="$(echo "$VAULT_CONTENT" \
  | python3 -c 'import sys,yaml; print(yaml.safe_load(sys.stdin)["grafana_cloud_sa_token"])')" || true

if [[ -z "$GRAFANA_URL" || "$GRAFANA_URL" == "CHANGEME" ]]; then
  echo "❌ grafana_cloud_url not set in the vault — add it with ansible-vault edit" >&2
  exit 1
fi

if [[ -z "$GRAFANA_TOKEN" || "$GRAFANA_TOKEN" == "CHANGEME" ]]; then
  echo "❌ grafana_cloud_sa_token not set in the vault — add it with ansible-vault edit" >&2
  exit 1
fi

# --- Register with Claude Code ------------------------------------------

claude mcp remove grafana 2>/dev/null || true

claude mcp add grafana --scope local \
  -e GRAFANA_URL="$GRAFANA_URL" \
  -e GRAFANA_SERVICE_ACCOUNT_TOKEN="$GRAFANA_TOKEN" \
  -- uvx mcp-grafana

echo ""
echo "✅ registered grafana"
echo "   Grafana URL : $GRAFANA_URL"
echo ""
echo "⚠️  This token does not clean itself up — it was created in the Grafana UI."
echo "   To revoke it: Administration > Service Accounts > <account> > Tokens > Delete"
echo ""
echo "   Restart Claude Code for the server to become available."
