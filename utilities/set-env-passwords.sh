#!/usr/bin/env bash
# ===========================================================================
# set-env-passwords.sh — write an environment's two RHDP passwords into the
# vault without echoing them. Issue #579.
#
#   bash utilities/set-env-passwords.sh sandbox
#   bash utilities/set-env-passwords.sh demo --derive-token
#
# A new RHDP environment needs three human inputs. The AAP URL goes in the
# /sales-demos-bootstrap prompt; the other two are credentials and go here:
#
#   aap_password         AAP admin password from the RHDP environment page
#   kubeadmin_password   OpenShift kubeadmin password from the same page
#
# openshift_api_token is NOT asked for — derive-ocp-token.sh derives it from
# kubeadmin_password (#559). --derive-token runs that afterwards, which only
# works once local.yml already points at the new cluster.
#
# Each character typed prints an asterisk so you can see keystrokes are
# registering; the actual values never reach the terminal, the shell history,
# or a Claude Code transcript. They are handed to python through the
# environment, never argv, so they are not visible in the process list.
# Pressing Enter on a prompt keeps the value already in the vault.
#
# The vault write follows derive-ocp-token.sh --update-vault: decrypt, set the
# keys, re-encrypt, replace.
# ===========================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# ── Environment validation ─────────────────────────────────────────────
environments() { ls -1 inventory/group_vars | grep -v '^aap$'; }

ENV_NAME="${1:-}"
if [[ -z "$ENV_NAME" ]]; then
  echo "usage: bash utilities/set-env-passwords.sh <$(environments | paste -sd'|')> [--derive-token]" >&2
  exit 2
fi

if [[ ! -d "inventory/group_vars/$ENV_NAME" ]]; then
  echo "❌ unknown environment '$ENV_NAME' — expected one of:" >&2
  environments | sed 's/^/     /' >&2
  exit 2
fi
shift

DERIVE_TOKEN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --derive-token) DERIVE_TOKEN=true ;;
    *) echo "Unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

# ── Hidden input needs a terminal ──────────────────────────────────────
if [[ ! -t 0 ]]; then
  echo "❌ no terminal on stdin — the password prompts cannot hide what you type." >&2
  echo "   Run this in a terminal window in the repo:" >&2
  echo "     bash utilities/set-env-passwords.sh $ENV_NAME" >&2
  exit 1
fi

# ── Vault password and secrets file ────────────────────────────────────
VAULT_PASS="${SALES_DEMOS_VAULT_PASS:-$HOME/secrets/.vault_pass_sales_demos}"
VAULT_ID="sales.demos@$VAULT_PASS"
if [[ ! -s "$VAULT_PASS" ]]; then
  echo "❌ $VAULT_PASS missing — without it the secrets file cannot be decrypted." >&2
  echo "   Build it with /sales-demos-first-time, step 2, or set" >&2
  echo "   SALES_DEMOS_VAULT_PASS if yours lives somewhere else." >&2
  exit 1
fi

SECRETS_FILE="$REPO_ROOT/playbooks/group_vars/all/secrets.yml"
if [[ ! -f "$SECRETS_FILE" ]]; then
  echo "❌ $SECRETS_FILE does not exist — run /sales-demos-first-time first" >&2
  exit 1
fi

# Fail on a bad vault password now, not after the user has typed two passwords.
if ! ansible-vault view "$SECRETS_FILE" --vault-id "$VAULT_ID" >/dev/null 2>&1; then
  echo "❌ could not decrypt $SECRETS_FILE with $VAULT_PASS" >&2
  exit 1
fi

# ── Read a password with asterisk feedback ────────────────────────────
read_secret() {
  local _var="$1" _prompt="$2" _input="" _char=""
  local _saved_stty
  _saved_stty="$(stty -g)"
  # shellcheck disable=SC2064
  trap "stty '$_saved_stty'" INT TERM
  printf '%s' "$_prompt"
  stty -echo
  while IFS= read -rsn1 _char; do
    if [[ -z "$_char" ]]; then
      break
    elif [[ "$_char" == $'\x7f' || "$_char" == $'\x08' ]]; then
      if [[ -n "$_input" ]]; then
        _input="${_input%?}"
        printf '\b \b'
      fi
    else
      _input+="$_char"
      printf '*'
    fi
  done
  stty "$_saved_stty"
  trap - INT TERM
  echo
  printf -v "$_var" '%s' "$_input"
}

# ── Prompt ─────────────────────────────────────────────────────────────
echo "Setting RHDP passwords for '$ENV_NAME'. Enter keeps the current value."
read_secret NEW_AAP_PASSWORD "  aap_password: "
read_secret NEW_KUBEADMIN_PASSWORD "  kubeadmin_password: "

if [[ -z "$NEW_AAP_PASSWORD" && -z "$NEW_KUBEADMIN_PASSWORD" ]]; then
  echo "Nothing entered — vault unchanged."
else
  umask 077
  TMPFILE="$(mktemp)"
  trap 'rm -f "$TMPFILE"' EXIT

  ansible-vault view "$SECRETS_FILE" --vault-id "$VAULT_ID" 2>/dev/null \
    | ENV_NAME="$ENV_NAME" \
      NEW_AAP_PASSWORD="$NEW_AAP_PASSWORD" \
      NEW_KUBEADMIN_PASSWORD="$NEW_KUBEADMIN_PASSWORD" \
      python3 -c "
import sys, yaml, os
data = yaml.safe_load(sys.stdin)
env = data.setdefault('env_secrets', {}).setdefault(os.environ['ENV_NAME'], {})
for key, var in (('aap_password', 'NEW_AAP_PASSWORD'),
                 ('kubeadmin_password', 'NEW_KUBEADMIN_PASSWORD')):
    if os.environ[var]:
        env[key] = os.environ[var]
yaml.dump(data, sys.stdout, default_flow_style=False, sort_keys=False, width=200)
" > "$TMPFILE"

  ansible-vault encrypt "$TMPFILE" --vault-id "$VAULT_ID" 2>/dev/null
  cp "$TMPFILE" "$SECRETS_FILE"
  chmod 600 "$SECRETS_FILE"
fi
unset NEW_AAP_PASSWORD NEW_KUBEADMIN_PASSWORD

# ── Report what the vault now holds — presence only, never values ─────
MISSING="$(ansible-vault view "$SECRETS_FILE" --vault-id "$VAULT_ID" 2>/dev/null \
  | ENV_NAME="$ENV_NAME" python3 -c "
import sys, yaml, os
env = (yaml.safe_load(sys.stdin).get('env_secrets') or {}).get(os.environ['ENV_NAME']) or {}
missing = 0
for key in ('aap_password', 'kubeadmin_password'):
    value = str(env.get(key) or '')
    ok = value and 'CHANGEME' not in value
    missing += not ok
    print(('  ✅ ' if ok else '  ❌ ') + key + (': present' if ok else ': MISSING'), file=sys.stderr)
print(missing)
")"

if [[ "$MISSING" != "0" ]]; then
  echo "❌ $MISSING credential(s) still missing for $ENV_NAME — re-run and enter them." >&2
  exit 1
fi
echo "✅ Vault holds both passwords for $ENV_NAME"

if $DERIVE_TOKEN; then
  bash utilities/derive-ocp-token.sh "$ENV_NAME" --update-vault
else
  echo "   openshift_api_token is derived by /sales-demos-bootstrap (derive-ocp-token.sh)."
fi
