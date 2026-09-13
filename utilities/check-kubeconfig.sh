#!/usr/bin/env bash
# ===========================================================================
# check-kubeconfig.sh — verify .kube/<env>.kubeconfig still points at <env>.
#
# Issue #161, updated #533. VERIFY, DO NOT TRUST — the same shape as
# check-no-secrets.sh's second check (#130).
#
# WHAT GOES WRONG WITHOUT IT. utilities/make-kubeconfig.sh writes the file once.
# Repointing an environment edits connection.yml (or local.yml) and the vault;
# it does NOT regenerate this file. The two then disagree silently, and the
# failure surfaces as a DNS error against a cluster that no longer exists.
#
# The expected URL is resolved through Ansible variable precedence, so
# local.yml overrides are respected (#533). Before #533 this script read
# connection.yml with raw yaml.safe_load, which was blind to local.yml.
#
# This checks the repo's own per-environment kubeconfig. It deliberately does
# NOT look at ~/.kube/config: that file holds clusters belonging to other demo
# repos and is not this repo's to own or judge.
#
#   ./utilities/check-kubeconfig.sh demo
#   ./utilities/check-kubeconfig.sh edge
# ===========================================================================
set -euo pipefail

# Anchor to the repo root. Every path below is relative, so this script only
# ever worked when invoked from there; without it the derived usage line below
# prints an empty list from anywhere else, which is worse than the stale one it
# replaced. Same anchor as make-kubeconfig.sh, for the same reason.
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# The environments, read from the tree rather than hardcoded, so the usage line
# cannot go stale the way a literal `<sandbox|demo>` did once `edge` arrived
# (#405). `aap` is the group every environment belongs to, not an environment.
environments() { ls -1 inventory/group_vars | grep -v '^aap$'; }

ENV="${1:-}"
[ -n "$ENV" ] || { echo "usage: $0 <$(environments | paste -sd'|')>" >&2; exit 2; }

KUBE=".kube/${ENV}.kubeconfig"

[ -d "inventory/group_vars/$ENV" ] || { echo "❌ no such environment '$ENV'" >&2; exit 2; }

if [ ! -f "$KUBE" ]; then
  echo "❌ $KUBE missing — generate it: bash utilities/make-kubeconfig.sh $ENV" >&2
  exit 1
fi

VAULT_PASS="${SALES_DEMOS_VAULT_PASS:-$HOME/secrets/.vault_pass_sales_demos}"
VAULT_ID="sales.demos@$VAULT_PASS"

want="$(ansible -i inventory --limit "$ENV" aap -m debug --vault-id "$VAULT_ID" \
  -a 'msg={{ openshift_api_url }}' 2>/dev/null | sed -n 's/.*"msg": "\(.*\)"/\1/p')"

case "$want" in
  https://*) ;;
  *) echo "❌ could not resolve openshift_api_url for '$ENV' — got: ${want:-(empty)}" >&2; exit 2 ;;
esac
have="$(python3 -c "
import yaml,sys
d=yaml.safe_load(open('$KUBE')) or {}
c=(d.get('clusters') or [{}])[0].get('cluster',{})
print(c.get('server',''))
")"

if [ "$want" != "$have" ]; then
  cat >&2 <<EOF
❌ $KUBE is stale for '$ENV'.
     expected:   $want
     kubeconfig: $have
   The environment was repointed without regenerating the kubeconfig.
   Fix: bash utilities/make-kubeconfig.sh $ENV
EOF
  exit 1
fi

echo "✅ $KUBE matches $ENV ($want)"
