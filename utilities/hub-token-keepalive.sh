#!/usr/bin/env bash
# ===========================================================================
# hub-token-keepalive.sh — use the Red Hat offline token so it does not die.
# Issue #915.
#
#   bash utilities/hub-token-keepalive.sh
#
# Run daily by the systemd user timer (Linux) or launchd agent (macOS) that
# utilities/install-hub-token-keepalive.sh installs. Safe to run by hand.
#
# A Red Hat offline token expires after 30 days WITHOUT USE, and the exchange
# check-hub-token.sh makes -- grant_type refresh_token, client_id
# cloud-services -- is a use. So the keepalive is that check on a schedule.
# It stores no token: ~/.ansible.cfg is read at run time, so a rotated token
# is picked up with nothing to update. The keepalive this replaced embedded its
# own copy, which drifted from ~/.ansible.cfg and kept the wrong token alive.
#
# Exit codes follow check-hub-token.sh:
#   0 live          log only
#   1 rejected      log AND desktop notification -- a dead token needs a
#                   browser login, so the point is to find out the same day
#   2 unreachable   log only. Offline is normal on a laptop, and a daily run
#                   gets ~30 more chances before the token lapses
#
# Logs to ~/ansible-logs/hub-token-keepalive.log. Only the token's length is
# ever printed. HUB_TOKEN_CFG passes through to check-hub-token.sh.
#
# Portable to macOS's bash 3.2: no readlink -f, no GNU date flags.
# ===========================================================================
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
log_dir="${ANSIBLE_LOG_DIR:-$HOME/ansible-logs}"
log="$log_dir/hub-token-keepalive.log"
new_url="https://console.redhat.com/ansible/automation-hub/token"

mkdir -p "$log_dir"

out="$(bash "$here/check-hub-token.sh" 2>&1)"
rc=$?

stamp="$(date '+%Y-%m-%dT%H:%M:%S%z')"
printf '%s\n' "$out" | while IFS= read -r line; do
  printf '%s rc=%s %s\n' "$stamp" "$rc" "$line"
done >>"$log"
printf '%s\n' "$out"

notify() {
  local title="$1" body="$2"
  case "$(uname -s)" in
    Darwin)
      # AppleScript string literals: escape backslashes and double quotes.
      body="${body//\\/\\\\}"; body="${body//\"/\\\"}"
      title="${title//\\/\\\\}"; title="${title//\"/\\\"}"
      osascript -e "display notification \"$body\" with title \"$title\" sound name \"Basso\"" \
        >/dev/null 2>&1 || true
      ;;
    *)
      if command -v notify-send >/dev/null 2>&1; then
        notify-send -u critical -a "sales.demos" "$title" "$body" >/dev/null 2>&1 || true
      fi
      ;;
  esac
}

if [[ $rc -eq 1 ]]; then
  notify "Automation Hub token is dead" \
    "Red Hat SSO rejected the offline token in ~/.ansible.cfg. Load a new one at $new_url and replace it in [rh_certified] and [rh_validated]. Log: $log"
fi

exit "$rc"
