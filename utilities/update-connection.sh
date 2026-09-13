#!/usr/bin/env bash
# ===========================================================================
# update-connection.sh — propagate local.yml overrides into connection.yml
#
# local.yml is a gitignored per-environment override that lets an SE point
# their laptop at a different cluster without editing a committed file.
# AAP reads the committed connection.yml from its SCM checkout, so local.yml
# is invisible to it. This script bridges that gap: it reads local.yml and
# updates the matching keys in connection.yml, preserving comments and
# formatting.
#
# Usage:
#     bash utilities/update-connection.sh <env>
#
# <env> is sandbox, demo, or edge.
#
# Ref: #513
# ===========================================================================
set -euo pipefail

# ---- argument validation ---------------------------------------------------
if [ $# -ne 1 ]; then
  echo "Usage: $0 <env>"
  echo "  <env> is sandbox, demo, or edge"
  exit 1
fi

env_name="$1"

# Resolve paths relative to the repo root, not the cwd.
repo_root="$(git rev-parse --show-toplevel)"
env_dir="${repo_root}/inventory/group_vars/${env_name}"
local_file="${env_dir}/local.yml"
connection_file="${env_dir}/connection.yml"

if [ ! -f "$connection_file" ]; then
  echo "ERROR: ${connection_file} does not exist."
  echo "  '${env_name}' does not look like a valid environment."
  echo "  Valid environments have a directory under inventory/group_vars/."
  exit 1
fi

if [ ! -f "$local_file" ]; then
  echo "ERROR: ${local_file} does not exist."
  echo
  echo "  Copy the example and fill in your cluster's values:"
  echo "    cp ${env_dir}/local.yml.example ${local_file}"
  echo
  echo "  See the comment header in local.yml.example for details."
  exit 1
fi

# ---- update connection.yml using python3 -----------------------------------
python3 - "$local_file" "$connection_file" <<'PYEOF'
import sys
import yaml
import re

local_path = sys.argv[1]
connection_path = sys.argv[2]

# Parse local.yml to get override key-value pairs.
with open(local_path) as f:
    local_data = yaml.safe_load(f)

if not local_data or not isinstance(local_data, dict):
    print("local.yml is empty or not a YAML mapping — nothing to update.")
    sys.exit(0)

# Read connection.yml as text to preserve comments and formatting.
with open(connection_path) as f:
    lines = f.readlines()

changes = []
updated_lines = []

for line in lines:
    matched = False
    for key, new_value in local_data.items():
        # Match lines like:  key: value  or  key: "value"
        # Anchored to start-of-line (possibly with leading whitespace).
        pattern = r'^(\s*' + re.escape(key) + r'\s*:\s*)(.*)$'
        m = re.match(pattern, line)
        if m:
            prefix = m.group(1)     # e.g. 'aap_hostname: '
            old_raw = m.group(2)    # e.g. '"old-value"'

            # Strip surrounding quotes and trailing whitespace from old value
            # for comparison.
            old_stripped = old_raw.strip().strip('"').strip("'")
            new_str = str(new_value)

            if old_stripped != new_str:
                # Preserve the quoting style of the original.
                if old_raw.strip().startswith('"'):
                    replacement = prefix + '"' + new_str + '"\n'
                elif old_raw.strip().startswith("'"):
                    replacement = prefix + "'" + new_str + "'\n"
                else:
                    replacement = prefix + '"' + new_str + '"\n'
                updated_lines.append(replacement)
                changes.append((key, old_stripped, new_str))
            else:
                updated_lines.append(line)
            matched = True
            break
    if not matched:
        updated_lines.append(line)

# Write back.
with open(connection_path, 'w') as f:
    f.writelines(updated_lines)

# Report.
if changes:
    print(f"Updated {len(changes)} key(s) in {connection_path}:")
    for key, old_val, new_val in changes:
        # Truncate long values for readability.
        old_display = old_val if len(old_val) <= 60 else old_val[:57] + "..."
        new_display = new_val if len(new_val) <= 60 else new_val[:57] + "..."
        print(f"  {key}:")
        print(f"    old: {old_display}")
        print(f"    new: {new_display}")
else:
    print("All keys in local.yml already match connection.yml — no changes.")
PYEOF
