#!/usr/bin/env bash
# =============================================================================
# utilities/run-playbook.sh — run a playbook and put the log where it belongs.
# =============================================================================
#   ./utilities/run-playbook.sh playbooks/config.yml --limit sandbox \
#       -e target_env=sandbox
#
# WHY THIS EXISTS. The rule "run logs live in ~/ansible-logs, outside this repo"
# is real and old -- .gitignore says it, and every skill sets ANSIBLE_LOG_PATH.
# But it was only ever enforced INSIDE skills, so an ad-hoc `ansible-playbook`
# had nothing telling it where to write, and the answer people reached for was a
# directory in the repo. Three of those accumulated before anyone noticed, and
# they were invisible because the same .gitignore that states the rule also
# hides every breach of it.
#
# A CI JOB CANNOT CATCH THIS, which is why there is a wrapper instead of a
# check. CI checks out a clean tree; a stray logs/ directory only ever exists on
# somebody's laptop. A job asserting "no logs/ here" would pass on every run and
# mean nothing -- the green tick that asserts something it does not, which
# check-renderer-fixture.py's docstring already warns about.
#
# So the enforcement is to make the right thing the easy thing: this wrapper
# names the log, creates the directory, passes the vault id, and prints the path.
#
# NEVER PIPE THROUGH tee. In a pipeline the exit status comes from tee, so a
# failed run reports success. This redirects, then reports the real status.
# =============================================================================
set -euo pipefail

LOG_DIR="${ANSIBLE_LOG_DIR:-$HOME/ansible-logs}"
VAULT_PASS="${SALES_DEMOS_VAULT_PASS:-$HOME/secrets/.vault_pass_sales_demos}"

[ $# -ge 1 ] || { echo "usage: $0 <playbook> [ansible-playbook args...]" >&2; exit 2; }

PLAYBOOK="$1"; shift
[ -f "$PLAYBOOK" ] || { echo "ERROR: no such playbook: $PLAYBOOK" >&2; exit 2; }

# Name the log after the playbook plus whatever --limit was asked for, so a
# directory listing tells you what ran against what without opening anything.
NAME="$(basename "$PLAYBOOK" .yml)"
LIMIT=""
prev=""
for arg in "$@"; do
  [ "$prev" = "--limit" ] && LIMIT="-$arg"
  prev="$arg"
done
LOG="$LOG_DIR/${NAME}${LIMIT}-$(date +%F-%H%M%S).log"

mkdir -p "$LOG_DIR"

VAULT_ARGS=()
[ -f "$VAULT_PASS" ] && VAULT_ARGS=(--vault-id "sales.demos@$VAULT_PASS")

echo "playbook : $PLAYBOOK"
echo "log      : $LOG"
echo

set +e
ansible-playbook "$PLAYBOOK" "${VAULT_ARGS[@]}" "$@" > "$LOG" 2>&1
rc=$?
set -e

tail -n 12 "$LOG"
echo
if [ $rc -eq 0 ]; then
  echo "PASSED — full log: $LOG"
else
  echo "FAILED (rc=$rc) — full log: $LOG"
  echo "First failure:"
  grep -m1 -B2 -A8 -E '^fatal:|^ERROR!' "$LOG" || true
fi
exit $rc
