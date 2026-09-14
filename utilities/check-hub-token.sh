#!/usr/bin/env bash
# ===========================================================================
# check-hub-token.sh — is the Red Hat offline token in ~/.ansible.cfg LIVE?
# Issue #597.
#
#   bash utilities/check-hub-token.sh
#   HUB_TOKEN_CFG=/path/to/other.cfg bash utilities/check-hub-token.sh
#
# PRESENT IS NOT LIVE. Every preflight used to grep for `token=.+` or count
# characters, and an expired token passes both. On 2026-09-14 one did: a
# well-formed token that Red Hat SSO answered with invalid_grant, "Token is
# not active". Certified installs and every Red Hat hub sync fail on it while
# each check says ✅.
#
# This makes the exchange Pulp and ansible-galaxy make -- grant_type
# refresh_token, client_id cloud-services -- and reports the answer. The
# access token SSO returns is thrown away; the offline token is not rotated.
# Nothing about the token is printed except its length.
#
# Both [galaxy_server.rh_certified] and [galaxy_server.rh_validated] are read:
# they are meant to hold the same token, and a rotation that updates one of
# them is half a fix.
#
# The one implementation for shell callers -- utilities/preflight.sh
# --hub-token, /sales-demos-first-time and /sales-demos-collections-sync.
# Playbooks use playbooks/tasks/check_hub_token.yml, which makes the same call
# with ansible.builtin.uri.
#
# Exit 0 live, 1 missing or rejected, 2 Red Hat SSO unreachable.
# ===========================================================================
set -euo pipefail

exec python3 - "${HUB_TOKEN_CFG:-$HOME/.ansible.cfg}" <<'PY'
import configparser
import json
import sys
import urllib.error
import urllib.parse
import urllib.request

SSO = "https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token"
NEW = "https://console.redhat.com/ansible/automation-hub/token"
SECTIONS = ("galaxy_server.rh_certified", "galaxy_server.rh_validated")
cfg_path = sys.argv[1]

cfg = configparser.ConfigParser(interpolation=None)
cfg.read(cfg_path)

status = 0
by_token: dict[str, list[str]] = {}
for section in SECTIONS:
    token = cfg.get(section, "token", fallback="").strip()
    if len(token) <= 100:
        print(f"❌ no offline token in {cfg_path} [{section}] — get one at {NEW}")
        status = 1
    else:
        by_token.setdefault(token, []).append(section)

if len(by_token) > 1:
    print("⚠️  [rh_certified] and [rh_validated] hold DIFFERENT tokens — both are checked,"
          " but they are meant to be the same one")

for token, sections in by_token.items():
    where = " and ".join(f"[{s}]" for s in sections)
    body = urllib.parse.urlencode(
        {"grant_type": "refresh_token", "client_id": "cloud-services", "refresh_token": token}
    ).encode()
    try:
        with urllib.request.urlopen(urllib.request.Request(SSO, data=body), timeout=30) as resp:
            print(f"✅ offline token in {where} is live ({len(token)} chars, Red Hat SSO HTTP {resp.status})")
    except urllib.error.HTTPError as err:
        try:
            detail = json.load(err)
        except ValueError:
            detail = {}
        print(f"❌ Red Hat SSO rejected the offline token in {where}:"
              f" {detail.get('error', f'HTTP {err.code}')} — {detail.get('error_description', 'no description')}."
              f" Load a new one at {NEW} and replace it in both sections.")
        status = 1
    except (urllib.error.URLError, OSError) as err:
        print(f"❌ could not reach Red Hat SSO to check the offline token in {where}: {err}")
        status = status or 2

sys.exit(status)
PY
