#!/usr/bin/env bash
# ===========================================================================
# install-hub-token-keepalive.sh — schedule hub-token-keepalive.sh daily.
# Issue #915.
#
#   bash utilities/install-hub-token-keepalive.sh              # install
#   bash utilities/install-hub-token-keepalive.sh --status
#   bash utilities/install-hub-token-keepalive.sh --uninstall
#
# Linux:  a systemd USER timer, OnCalendar=daily, Persistent=true
# macOS:  a launchd agent in ~/Library/LaunchAgents, daily at 10:00
#
# Not cron, because cron skips a run that falls while the laptop is asleep.
# A systemd timer with Persistent=true runs it at the next boot or wake;
# launchd runs a missed StartCalendarInterval when the Mac wakes.
#
# THE SCHEDULE EMBEDS THIS CHECKOUT'S ABSOLUTE PATH. Install from the main
# checkout, not a git worktree: worktrees here are removed after merge, and a
# timer pointing at a deleted directory fails every day without a notification
# (the notification lives in the script it can no longer find).
# --allow-worktree exists for testing a branch, and nothing else.
#
# Re-running install is idempotent: it rewrites the unit/plist and reloads.
# Portable to macOS's bash 3.2.
# ===========================================================================
set -euo pipefail

name="sales-demos-hub-token-keepalive"
label="com.github.ericcames.sales-demos.hub-token-keepalive"
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
script="$here/hub-token-keepalive.sh"
log_dir="${ANSIBLE_LOG_DIR:-$HOME/ansible-logs}"

action="install"
allow_worktree=0
for arg in "$@"; do
  case "$arg" in
    --status) action="status" ;;
    --uninstall) action="uninstall" ;;
    --allow-worktree) allow_worktree=1 ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

os="$(uname -s)"
case "$os" in
  Linux)
    unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
    service="$unit_dir/$name.service"
    timer="$unit_dir/$name.timer"
    ;;
  Darwin)
    plist="$HOME/Library/LaunchAgents/$label.plist"
    domain="gui/$(id -u)"
    ;;
  *) echo "unsupported OS: $os (Linux and macOS only)" >&2; exit 2 ;;
esac

warn_old_cron() {
  # The keepalive this replaces was a crontab line. It never worked (#915),
  # but say so rather than edit someone's crontab behind their back.
  local old
  old="$(crontab -l 2>/dev/null | grep -E 'token_keepalive|token-keepalive' || true)"
  if [[ -n "$old" ]]; then
    echo
    echo "⚠️  crontab still has keepalive line(s) — check whether they are superseded:"
    printf '%s\n' "$old" | sed 's/^/     /'
    echo "   Remove one with:  crontab -l | grep -v '<pattern>' | crontab -"
  fi
}

install_linux() {
  mkdir -p "$unit_dir"
  cat >"$service" <<EOF
# Installed by $repo/utilities/install-hub-token-keepalive.sh (#915)
[Unit]
Description=Keep the Red Hat Automation Hub offline token alive
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
# notify-send needs the session bus; set it explicitly rather than trust the
# user manager's imported environment.
Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=%t/bus
Environment=ANSIBLE_LOG_DIR=$log_dir
ExecStart=/usr/bin/env bash $script
EOF
  cat >"$timer" <<EOF
# Installed by $repo/utilities/install-hub-token-keepalive.sh (#915)
[Unit]
Description=Daily Red Hat Automation Hub offline token keepalive

[Timer]
OnCalendar=daily
# Run at the next boot or wake if the scheduled time was missed.
Persistent=true
RandomizedDelaySec=1h

[Install]
WantedBy=timers.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable --now "$name.timer"
  echo "✅ installed $timer"
  systemctl --user list-timers "$name.timer" --no-pager
}

install_darwin() {
  mkdir -p "$(dirname "$plist")" "$log_dir"
  cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!-- Installed by $repo/utilities/install-hub-token-keepalive.sh (#915) -->
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$script</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>ANSIBLE_LOG_DIR</key><string>$log_dir</string>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key><integer>10</integer>
    <key>Minute</key><integer>0</integer>
  </dict>
  <key>StandardOutPath</key><string>$log_dir/hub-token-keepalive.launchd.log</string>
  <key>StandardErrorPath</key><string>$log_dir/hub-token-keepalive.launchd.log</string>
</dict>
</plist>
EOF
  plutil -lint "$plist" >/dev/null
  launchctl bootout "$domain/$label" 2>/dev/null || true
  launchctl bootstrap "$domain" "$plist"
  echo "✅ installed $plist (daily at 10:00; a missed run fires on wake)"
}

case "$action" in
  install)
    if [[ -f "$repo/.git" && $allow_worktree -eq 0 ]]; then
      echo "❌ $repo is a git worktree. The schedule embeds this path, and worktrees" >&2
      echo "   are removed after merge. Install from the main checkout instead." >&2
      exit 1
    fi
    [[ -f "$script" ]] || { echo "❌ missing $script" >&2; exit 1; }
    echo "Checking the token once before scheduling it:"
    bash "$script" || echo "   (scheduling anyway — the daily run will keep reporting until it is fixed)"
    echo
    if [[ "$os" == Linux ]]; then install_linux; else install_darwin; fi
    echo "   runs: $script"
    echo "   log:  $log_dir/hub-token-keepalive.log"
    warn_old_cron
    ;;
  status)
    if [[ "$os" == Linux ]]; then
      systemctl --user list-timers "$name.timer" --no-pager || true
      systemctl --user status "$name.service" --no-pager 2>/dev/null | sed -n '1,6p' || true
      [[ -f "$service" ]] && grep '^ExecStart=' "$service"
    else
      launchctl print "$domain/$label" 2>/dev/null \
        | grep -E 'state =|last exit code|program =|arguments' || echo "not loaded"
    fi
    echo "--- last log lines"
    tail -n 5 "$log_dir/hub-token-keepalive.log" 2>/dev/null || echo "(no log yet)"
    ;;
  uninstall)
    if [[ "$os" == Linux ]]; then
      systemctl --user disable --now "$name.timer" 2>/dev/null || true
      rm -f "$service" "$timer"
      systemctl --user daemon-reload
    else
      launchctl bootout "$domain/$label" 2>/dev/null || true
      rm -f "$plist"
    fi
    echo "✅ uninstalled $name"
    ;;
esac
