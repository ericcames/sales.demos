#!/usr/bin/env bash
# ===========================================================================
# check-mcp-staleness.sh — detect stale MCP client-side credentials.
#
# Issue #533. When an RHDP environment expires or gets repointed, MCP
# client credentials go stale silently. This script checks ALL credential
# types for one environment against the effective inventory values (which
# respect local.yml overrides via Ansible variable precedence).
#
# Checks:
#   1. Kubeconfig server URL  vs.  effective openshift_api_url
#   2. AAP MCP URL            vs.  effective openshift_apps_domain
#   3. AO MCP registration    vs.  effective openshift_apps_domain
#   4. Portal MCP URL         vs.  effective openshift_apps_domain (#555)
#
# Grafana is NOT checked — it is an external SaaS instance unrelated to
# RHDP environment lifecycle.
#
# REPORTS ONLY. Does not fix anything. Each stale item prints the exact
# command to regenerate it.
#
#   bash utilities/check-mcp-staleness.sh sandbox
#   bash utilities/check-mcp-staleness.sh demo
#   bash utilities/check-mcp-staleness.sh edge
# ===========================================================================
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

REPO_ROOT="$PWD"

environments() { ls -1 inventory/group_vars | grep -v '^aap$'; }

ENV="${1:-}"
[ -n "$ENV" ] || { echo "usage: $0 <$(environments | paste -sd'|')>" >&2; exit 2; }

[ -d "inventory/group_vars/$ENV" ] || {
  echo "❌ no such environment '$ENV'" >&2
  exit 2
}

# ---------------------------------------------------------------------------
# Resolve effective values from Ansible inventory (respects local.yml)
# ---------------------------------------------------------------------------

VAULT_PASS="${SALES_DEMOS_VAULT_PASS:-$HOME/secrets/.vault_pass_sales_demos}"
VAULT_ID="sales.demos@$VAULT_PASS"

if [[ ! -s "$VAULT_PASS" ]]; then
  echo "❌ vault password file missing ($VAULT_PASS)" >&2
  echo "   Run /sales-demos-first-time to set up prerequisites." >&2
  exit 2
fi

resolve_var() {
  ansible -i inventory --limit "$ENV" aap -m debug --vault-id "$VAULT_ID" \
    -a "msg={{ $1 }}" 2>/dev/null | sed -n 's/.*"msg": "\(.*\)"/\1/p'
}

EFFECTIVE_API_URL="$(resolve_var openshift_api_url)"
EFFECTIVE_APPS_DOMAIN="$(resolve_var openshift_apps_domain)"

case "$EFFECTIVE_API_URL" in
  https://*) ;;
  *)
    echo "❌ could not resolve openshift_api_url for '$ENV' — got: ${EFFECTIVE_API_URL:-(empty)}" >&2
    echo "   Check connection.yml / local.yml and the vault password." >&2
    exit 2
    ;;
esac

if [[ -z "$EFFECTIVE_APPS_DOMAIN" ]]; then
  echo "❌ could not resolve openshift_apps_domain for '$ENV'" >&2
  exit 2
fi

stale=0

echo "Checking MCP credentials for '$ENV'..."
echo "  effective openshift_api_url   : $EFFECTIVE_API_URL"
echo "  effective openshift_apps_domain: $EFFECTIVE_APPS_DOMAIN"
echo ""

# ---------------------------------------------------------------------------
# Check 1: Kubeconfig
# ---------------------------------------------------------------------------

KUBE="$REPO_ROOT/.kube/${ENV}.kubeconfig"

if [[ ! -f "$KUBE" ]]; then
  echo "❌ openshift-$ENV: kubeconfig missing ($KUBE)"
  echo "   fix: bash utilities/make-kubeconfig.sh $ENV"
  stale=$((stale + 1))
else
  have="$(python3 -c "
import yaml
d = yaml.safe_load(open('$KUBE')) or {}
c = (d.get('clusters') or [{}])[0].get('cluster', {})
print(c.get('server', ''))
")"
  if [[ "$EFFECTIVE_API_URL" != "$have" ]]; then
    echo "❌ openshift-$ENV: kubeconfig is stale"
    echo "     expected: $EFFECTIVE_API_URL"
    echo "     have:     $have"
    echo "   fix: bash utilities/make-kubeconfig.sh $ENV"
    stale=$((stale + 1))
  else
    echo "✅ openshift-$ENV kubeconfig ($EFFECTIVE_API_URL)"
  fi
fi

# ---------------------------------------------------------------------------
# Check 2: AAP MCP URL
# ---------------------------------------------------------------------------

AAP_URL_FILE="$REPO_ROOT/.aap/${ENV}.url"
AAP_TOKEN_FILE="$REPO_ROOT/.aap/${ENV}.token"

if [[ ! -f "$AAP_URL_FILE" ]] && [[ ! -f "$AAP_TOKEN_FILE" ]]; then
  echo "⏭️  aap-$ENV: not configured (.aap/${ENV}.url and .token missing)"
else
  if [[ ! -f "$AAP_URL_FILE" ]]; then
    echo "❌ aap-$ENV: .aap/${ENV}.url missing"
    echo "   fix: bash utilities/make-aap-mcp.sh $ENV"
    stale=$((stale + 1))
  else
    aap_mcp_url="$(cat "$AAP_URL_FILE")"
    if echo "$aap_mcp_url" | grep -qF "$EFFECTIVE_APPS_DOMAIN"; then
      echo "✅ aap-$ENV URL ($aap_mcp_url)"
    else
      echo "❌ aap-$ENV: URL is stale"
      echo "     have:     $aap_mcp_url"
      echo "     expected: https://aap-mcp-aap.$EFFECTIVE_APPS_DOMAIN"
      echo "   fix: bash utilities/make-aap-mcp.sh $ENV"
      stale=$((stale + 1))
    fi
  fi

  if [[ ! -f "$AAP_TOKEN_FILE" ]]; then
    echo "❌ aap-$ENV: .aap/${ENV}.token missing"
    echo "   fix: bash utilities/make-aap-mcp.sh $ENV"
    stale=$((stale + 1))
  else
    echo "✅ aap-$ENV token present"
  fi
fi

# ---------------------------------------------------------------------------
# Check 3: Portal MCP URL (#555)
# ---------------------------------------------------------------------------

PORTAL_URL_FILE="$REPO_ROOT/.portal/${ENV}.url"
PORTAL_TOKEN_FILE="$REPO_ROOT/.portal/${ENV}.token"

if [[ ! -f "$PORTAL_URL_FILE" ]] && [[ ! -f "$PORTAL_TOKEN_FILE" ]]; then
  echo "⏭️  portal-$ENV: not configured (.portal/${ENV}.url and .token missing)"
else
  if [[ ! -f "$PORTAL_URL_FILE" ]]; then
    echo "❌ portal-$ENV: .portal/${ENV}.url missing"
    echo "   fix: bash utilities/make-portal-mcp.sh $ENV"
    stale=$((stale + 1))
  else
    portal_mcp_url="$(cat "$PORTAL_URL_FILE")"
    if echo "$portal_mcp_url" | grep -qF "$EFFECTIVE_APPS_DOMAIN"; then
      echo "✅ portal-$ENV URL ($portal_mcp_url)"
    else
      echo "❌ portal-$ENV: URL is stale"
      echo "     have:     $portal_mcp_url"
      echo "     expected domain: $EFFECTIVE_APPS_DOMAIN"
      echo "   fix: bash utilities/make-portal-mcp.sh $ENV"
      stale=$((stale + 1))
    fi
  fi

  if [[ ! -f "$PORTAL_TOKEN_FILE" ]]; then
    echo "❌ portal-$ENV: .portal/${ENV}.token missing"
    echo "   fix: bash utilities/make-portal-mcp.sh $ENV"
    stale=$((stale + 1))
  else
    echo "✅ portal-$ENV token present"
  fi
fi

# ---------------------------------------------------------------------------
# Check 4: AO MCP registration
# ---------------------------------------------------------------------------

ao_url=""
settings_local="$REPO_ROOT/.claude/settings.local.json"

if [[ -f "$settings_local" ]]; then
  ao_url="$(python3 -c "
import json, sys
try:
    d = json.load(open('$settings_local'))
    servers = d.get('mcpServers', {})
    ao = servers.get('ao-$ENV', {})
    env = ao.get('env', {})
    print(env.get('AO_URL', ''))
except Exception:
    pass
" 2>/dev/null)" || true
fi

if [[ -z "$ao_url" ]]; then
  echo "⏭️  ao-$ENV: not registered"
else
  if echo "$ao_url" | grep -qF "$EFFECTIVE_APPS_DOMAIN"; then
    echo "✅ ao-$ENV URL ($ao_url)"
  else
    echo "❌ ao-$ENV: registration is stale"
    echo "     have:     $ao_url"
    echo "     expected domain: $EFFECTIVE_APPS_DOMAIN"
    echo "   fix: bash utilities/make-ao-mcp.sh $ENV"
    stale=$((stale + 1))
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
if [[ "$stale" -gt 0 ]]; then
  echo "Staleness check FAILED for $ENV — $stale credential(s) stale."
  exit 1
else
  echo "Staleness check passed for $ENV."
fi
