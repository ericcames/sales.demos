#!/usr/bin/env bash
# clean-ansible-logs.sh — delete stale Ansible log files from ~/ansible-logs.
#
# Called weekly by cron; safe to run manually at any time.
set -euo pipefail

dir="${ANSIBLE_LOG_DIR:-$HOME/ansible-logs}"
days="${ANSIBLE_LOG_RETENTION_DAYS:-14}"

if [[ ! -d "$dir" ]]; then
  exit 0
fi

before=$(du -sb "$dir" 2>/dev/null | cut -f1)

empty=$(find "$dir" -maxdepth 1 -type f -empty -printf '%f\n')
empty_count=$(echo -n "$empty" | grep -c '' || true)
if (( empty_count > 0 )); then
  find "$dir" -maxdepth 1 -type f -empty -delete
fi

stale=$(find "$dir" -maxdepth 1 -type f -mtime +"$days" -printf '%f\n')
stale_count=$(echo -n "$stale" | grep -c '' || true)
if (( stale_count > 0 )); then
  find "$dir" -maxdepth 1 -type f -mtime +"$days" -delete
fi

after=$(du -sb "$dir" 2>/dev/null | cut -f1)
freed=$(( before - after ))

total=$(( empty_count + stale_count ))
if (( total > 0 )); then
  echo "clean-ansible-logs: removed $total files ($stale_count stale, $empty_count empty), freed $(numfmt --to=iec "$freed")"
fi
