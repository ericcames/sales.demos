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
  # Only tracked files. secrets.yml is untracked (#130), so these patterns do
  # not see it at all — the separate block below is what keeps it that way, and
  # is the reason this scan being blind to it is safe rather than a hole.
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
# secrets.yml MUST NOT BE TRACKED, and the ignore rule must actually work.
#
# The history of this block matters, because it has now been through both
# designs and the second one nearly shipped a hole.
#
# Originally: "secrets.yml must never be tracked." Then #18 moved the repo to a
# vault-encrypted COMMITTED file, and this became "a tracked secrets.yml must
# start with $ANSIBLE_VAULT" -- the only thing standing between a plaintext
# credential file and a public push. The comment here said, correctly, that an
# ignore rule would hide the real file rather than verify it.
#
# #130 untracks the file again, because a public repo that ships one person's
# encrypted credentials cannot be reused by anyone else. That objection above is
# still right, so the ignore rule is NOT a replacement for verification -- the
# rule itself is now verified.
#
# THE TRAP THIS AVOIDS. Simply gitignoring the file and keeping the old loop
# would have been silent: `git ls-files` returns nothing, the `while` never
# iterates, `fail` stays 0, and the script prints "passed". Every check() above
# also pipes from `git ls-files`, so a PLAINTEXT untracked secrets.yml full of
# live tokens would be invisible to all of them. CI would go green while the one
# thing this script exists to guard stopped being guarded.
#
# So there are three checks, and none of them can no-op:
#   1. the ignore rule exists and actually matches the file
#   2. nothing named secrets.yml is tracked (catches `git add -f`)
#   3. if one IS tracked despite (2), it must still be vault-encrypted
# ---------------------------------------------------------------------------
SECRETS_FILE="playbooks/group_vars/all/secrets.yml"

# 1. Nothing named secrets.yml may be tracked. An ignore rule does not apply to
#    a file already in the index, so `git add -f` -- or a stale entry left over
#    from before #130 -- is invisible to check-ignore and has to be caught here.
tracked_secrets=$(git ls-files '*/secrets.yml' 'secrets.yml')
if [ -n "$tracked_secrets" ]; then
  echo "::error::a secrets.yml is TRACKED — credentials must never be committed here"
  printf '%s\n' "$tracked_secrets" | sed 's/^/    /'
  echo "    Untrack it, keeping your local copy on disk:"
  echo "      git rm --cached <path>"
  fail=1
fi

# 2. The ignore rule must exist AND match. `git check-ignore` runs the real
#    matching engine, so a typo'd path or a rule dropped in a merge is caught
#    here rather than discovered by a credential reaching GitHub.
#
#    ONLY MEANINGFUL WHEN THE FILE IS NOT TRACKED. git reports a tracked file as
#    "not ignored" whatever .gitignore says -- tracking wins -- so running this
#    unconditionally blames .gitignore for a rule that is present and correct.
#    Check 1 has already reported the real cause in that case.
if [ -z "$tracked_secrets" ] && ! git check-ignore -q "$SECRETS_FILE"; then
  echo "::error::$SECRETS_FILE is NOT covered by .gitignore"
  echo "    That rule is what keeps live credentials out of this public repo."
  echo "    Restore it in .gitignore before pushing."
  fail=1
fi

# 3. Belt and braces. If one is tracked anyway, it had better be encrypted.
#    Checks the committed blob, not the working tree, so staging a plaintext
#    file over an encrypted one is caught.
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
      echo "::error::$f is tracked and NOT vault-encrypted"
      fail=1
      ;;
  esac
done < <(printf '%s\n' "$tracked_secrets")

if [ "$fail" -ne 0 ]; then
  echo
  echo "Secret-hygiene check failed. See CONTRIBUTING.md -> 'Audit before every push'."
  echo "Credentials belong in playbooks/group_vars/all/secrets.yml, which is"
  echo "vault-encrypted and LOCAL ONLY -- never tracked. Hostnames and API URLs"
  echo "are not credentials and are fine in connection.yml."
  exit 1
fi

echo "Secret-hygiene check passed: no credentials tracked, and secrets.yml is ignored."
