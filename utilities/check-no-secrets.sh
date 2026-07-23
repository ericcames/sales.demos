#!/usr/bin/env bash
# ===========================================================================
# check-no-secrets.sh — CI enforcement of the pre-push audit.
#
# This repo is public. CONTRIBUTING.md tells you to grep before pushing; this
# script is that check, run automatically so it cannot be forgotten at the end
# of a long demo build.
#
# The patterns deliberately match REAL values, not the words. Documentation
# that discusses `sha256~` tokens or `redhatworkshops` hostnames must not fail
# the build, and `secrets.yml.example` placeholders must not either. So every
# pattern requires the shape of a genuine value:
#
#   sha256~CHANGEME              -> ignored (no 20+ char body)
#   cluster-<id>.dyn.redhat...   -> ignored (angle-bracket placeholder)
#   sha256~A7oD7vrp...           -> FAILS
#   cluster-c22j8-2.dyn.redhat.. -> FAILS
#
# Generic IPv4 is intentionally NOT checked here: RFC1918 addresses appear
# legitimately in docs and examples, and the false-positive rate would train
# people to ignore this script. Keep IPv4 in the manual pre-push grep.
# ===========================================================================
set -uo pipefail

fail=0

check() {
  local label="$1" pattern="$2"
  local hits
  # Only tracked files — gitignored secrets.yml is expected to hold real values.
  hits=$(git ls-files -z | xargs -0 grep -nEI "$pattern" 2>/dev/null || true)
  if [ -n "$hits" ]; then
    echo "::error::$label"
    printf '%s\n' "$hits" | sed 's/^/    /'
    fail=1
  fi
}

check "OpenShift bearer token" \
      'sha256~[A-Za-z0-9_-]{20,}'

check "Live RHDP cluster hostname (use cluster-<id> placeholder)" \
      '[Cc]luster-[a-z0-9]{4,}[-.][a-z0-9.-]*redhatworkshops'

check "Private key block" \
      '-----BEGIN [A-Z ]*PRIVATE KEY-----'

check "AWS access key id" \
      'AKIA[0-9A-Z]{16}'

check "GitHub token" \
      'gh[pousr]_[A-Za-z0-9]{36}'

check "Quay/registry credential in a tracked file" \
      '(quay|registry)[._-]?(password|token)[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9_/+=-]{12,}'

# A real secrets.yml must never be tracked, whatever it contains.
if git ls-files --error-unmatch 'inventory/group_vars/*/secrets.yml' >/dev/null 2>&1; then
  echo "::error::inventory/group_vars/*/secrets.yml is tracked — it must stay gitignored"
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo
  echo "Secret-hygiene check failed. See CONTRIBUTING.md -> 'Audit before every push'."
  echo "Environment-specific values belong in the gitignored"
  echo "inventory/group_vars/<env>/secrets.yml, never in a tracked file."
  exit 1
fi

echo "Secret-hygiene check passed: no live credentials or RHDP identifiers tracked."
