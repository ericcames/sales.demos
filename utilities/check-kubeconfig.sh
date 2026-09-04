#!/usr/bin/env bash
# ===========================================================================
# check-kubeconfig.sh — verify .kube/<env>.kubeconfig still points at <env>.
#
# Issue #161. VERIFY, DO NOT TRUST — the same shape as check-no-secrets.sh's
# second check (#130), which tests that the .gitignore rule actually matches
# rather than assuming a rule that is present is a rule that works.
#
# WHAT GOES WRONG WITHOUT IT. utilities/make-kubeconfig.sh writes the file once.
# Repointing an environment edits connection.yml and the vault; it does NOT
# regenerate this file. The two then disagree silently, and the failure surfaces
# as a DNS error against a cluster that no longer exists, at the moment someone
# tries to reach a VM.
#
# This checks the repo's own per-environment kubeconfig. It deliberately does
# NOT look at ~/.kube/config: that file holds clusters belonging to other demo
# repos and is not this repo's to own or judge.
#
#   ./utilities/check-kubeconfig.sh demo
# ===========================================================================
set -euo pipefail

ENV="${1:-}"
[ -n "$ENV" ] || { echo "usage: $0 <sandbox|demo>" >&2; exit 2; }

CONN="inventory/group_vars/${ENV}/connection.yml"
KUBE=".kube/${ENV}.kubeconfig"

[ -f "$CONN" ] || { echo "❌ no such environment '$ENV' ($CONN missing)" >&2; exit 2; }

if [ ! -f "$KUBE" ]; then
  echo "❌ $KUBE missing — generate it: bash utilities/make-kubeconfig.sh $ENV" >&2
  exit 1
fi

want="$(python3 -c "import yaml,sys;print(yaml.safe_load(open('$CONN'))['openshift_api_url'])")"
have="$(python3 -c "
import yaml,sys
d=yaml.safe_load(open('$KUBE')) or {}
c=(d.get('clusters') or [{}])[0].get('cluster',{})
print(c.get('server',''))
")"

if [ "$want" != "$have" ]; then
  cat >&2 <<EOF
❌ $KUBE is stale for '$ENV'.
     connection.yml: $want
     kubeconfig:     $have
   The environment was repointed without regenerating the kubeconfig.
   Fix: bash utilities/make-kubeconfig.sh $ENV
EOF
  exit 1
fi

echo "✅ $KUBE matches $ENV ($want)"
