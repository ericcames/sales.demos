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
  # Only tracked files — the committed secrets.yml is vault-encrypted, and the
  # separate check below is what enforces that.
  #
  # `-e` IS LOAD-BEARING. Without it, a pattern starting with a dash — like the
  # private-key block, `-----BEGIN ...` — is parsed by grep as an option bundle.
  # grep then errors out, `2>/dev/null || true` swallows the error, `hits` is
  # empty, and the check reports PASS on a file that plainly matches. That is
  # how the private-key check silently did nothing at all until it was caught
  # while adding an SSH key to the vault. Do not remove `-e`.
  hits=$(git ls-files -z | xargs -0 grep -nEI -e "$pattern" 2>/dev/null || true)
  if [ -n "$hits" ]; then
    echo "::error::$label"
    printf '%s\n' "$hits" | sed 's/^/    /'
    fail=1
  fi
}

check "OpenShift bearer token" \
      'sha256~[A-Za-z0-9_-]{20,}'

# RHDP hostnames are NOT checked. They are ephemeral demo-platform addresses,
# not customer-identifying, and group_vars/<env>/connection.yml now carries them
# in the clear on purpose — that is what lets the vaulted secrets file hold
# credentials only. The hard rule about customer names, passwords, tokens, and
# API keys is unchanged; only the RHDP URL concern is relaxed. (#18)

check "Private key block" \
      '-----BEGIN [A-Z ]*PRIVATE KEY-----'

check "AWS access key id" \
      'AKIA[0-9A-Z]{16}'

check "GitHub token" \
      'gh[pousr]_[A-Za-z0-9]{36}'

check "Quay/registry credential in a tracked file" \
      '(quay|registry)[._-]?(password|token)[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9_/+=-]{12,}'

# ---------------------------------------------------------------------------
# A tracked secrets.yml MUST be vault-encrypted.
#
# This replaced the old "secrets.yml must never be tracked" rule when the repo
# moved to vault-encrypted committed secrets (#18). It is the load-bearing check
# of that change: secrets.yml is no longer gitignored, so this is the only thing
# standing between a plaintext credential file and a public push. Do not weaken
# it, and do not re-add an ignore rule instead — an ignore rule would hide the
# real file rather than verify it.
#
# Checks the committed blob, not the working tree, so staging a plaintext file
# over an encrypted one is caught.
# ---------------------------------------------------------------------------
while IFS= read -r f; do
  [ -n "$f" ] || continue
  # Read the header into a variable FIRST, then test it. Testing the pipeline
  # directly is what this used to do, and it was wrong: `head -c 15` exits as
  # soon as it has its 15 bytes, `git show` then dies of SIGPIPE with status
  # 141, and `set -o pipefail` propagates that as the pipeline's status. The
  # condition therefore reported "not encrypted" for a file that was.
  #
  # It looked fine for a long time because it is a RACE: for a small blob git
  # finishes writing into the pipe buffer and exits 0 before head closes it.
  # Adding the SSH private key grew secrets.yml past that point and the check
  # started failing on a correctly encrypted file. A command substitution has
  # its own exit status, so pipefail cannot poison the comparison.
  header=$(git show ":$f" 2>/dev/null | head -c 15 || true)
  case "$header" in
    '$ANSIBLE_VAULT'*) ;;
    *)
      echo "::error::$f is tracked but NOT vault-encrypted"
      echo "    Encrypt it before committing:"
      echo "      ansible-vault encrypt $f --vault-id sales.demos@~/secrets/.vault_pass_sales_demos"
      fail=1
      ;;
  esac
done < <(git ls-files '*/secrets.yml' 'secrets.yml')

if [ "$fail" -ne 0 ]; then
  echo
  echo "Secret-hygiene check failed. See CONTRIBUTING.md -> 'Audit before every push'."
  echo "Credentials belong in the vault-encrypted playbooks/group_vars/all/secrets.yml,"
  echo "never in plaintext. Hostnames and API URLs are fine in connection.yml."
  exit 1
fi

echo "Secret-hygiene check passed: no live credentials or RHDP identifiers tracked."
