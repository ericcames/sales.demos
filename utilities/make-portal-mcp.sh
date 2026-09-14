#!/usr/bin/env bash
# ===========================================================================
# make-portal-mcp.sh — read the portal MCP credentials from the cluster and
# write the files that .mcp.json needs to connect. Issue #555.
#
#   bash utilities/make-portal-mcp.sh sandbox
#   bash utilities/make-portal-mcp.sh demo
#
# WHY THIS IS SIMPLER THAN make-aap-mcp.sh. The AAP script creates a
# personal access token via the gateway API. This script reads an existing
# Secret — the static MCP token was already generated and stored by
# portal.yml during deployment. No token creation, no cleanup instructions.
#
# THE TOKEN DIES WITH THE PORTAL. It is generated at deploy time by
# portal.yml and stored in a K8s Secret. When the RHDP environment expires,
# the Secret goes with it. On a fresh bootstrap, portal.yml generates a new
# token and this script picks it up.
# ===========================================================================
set -euo pipefail

ENV_NAME="${1:-}"
if [[ -z "$ENV_NAME" ]]; then
  echo "usage: bash utilities/make-portal-mcp.sh <sandbox|demo>" >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [[ ! -d "inventory/group_vars/$ENV_NAME" ]]; then
  echo "❌ unknown environment '$ENV_NAME' — expected one of:" >&2
  ls -1 inventory/group_vars | grep -v '^aap$' | sed 's/^/     /' >&2
  exit 2
fi

KUBECONFIG_FILE="$REPO_ROOT/.kube/${ENV_NAME}.kubeconfig"
if [[ ! -s "$KUBECONFIG_FILE" ]]; then
  echo "❌ $KUBECONFIG_FILE missing — run 'bash utilities/make-kubeconfig.sh $ENV_NAME' first." >&2
  exit 1
fi

PORTAL_NS="aap-portal"

# --- Find the portal route -------------------------------------------------

PORTAL_HOST="$(KUBECONFIG="$KUBECONFIG_FILE" oc get route -n "$PORTAL_NS" \
  -l app.kubernetes.io/name=rhaap-portal \
  -o jsonpath='{.items[0].spec.host}' 2>/dev/null)" || true

if [[ -z "$PORTAL_HOST" ]]; then
  echo "❌ no portal route in namespace '$PORTAL_NS' on $ENV_NAME — has portal.yml run?" >&2
  exit 1
fi

# --- Read the MCP static token from the cluster Secret ----------------------

TOKEN="$(KUBECONFIG="$KUBECONFIG_FILE" oc get secret portal-mcp-token -n "$PORTAL_NS" \
  -o jsonpath='{.data.token}' 2>/dev/null | base64 -d)" || true

if [[ -z "$TOKEN" ]]; then
  echo "❌ secret 'portal-mcp-token' not found in namespace '$PORTAL_NS' on $ENV_NAME." >&2
  echo "   The portal may have been deployed without MCP plugins enabled." >&2
  echo "   Re-run portal.yml to enable MCP and create the token Secret." >&2
  exit 1
fi

# --- Write credential files for the stdio bridge ---------------------------

MCP_URL="https://$PORTAL_HOST/api/mcp-actions/v1"

mkdir -p "$REPO_ROOT/.portal" && chmod 700 "$REPO_ROOT/.portal"

printf '%s\n' "$TOKEN" > "$REPO_ROOT/.portal/${ENV_NAME}.token"
chmod 600 "$REPO_ROOT/.portal/${ENV_NAME}.token"

printf '%s\n' "$MCP_URL" > "$REPO_ROOT/.portal/${ENV_NAME}.url"
chmod 600 "$REPO_ROOT/.portal/${ENV_NAME}.url"

echo ""
echo "✅ portal-$ENV_NAME credentials written"
echo "   environment : $ENV_NAME"
echo "   portal host : $PORTAL_HOST"
echo "   MCP endpoint: $MCP_URL"
echo "   token file  : .portal/${ENV_NAME}.token"
echo "   url file    : .portal/${ENV_NAME}.url"
echo ""
echo "   Restart Claude Code to bring portal-$ENV_NAME online."
