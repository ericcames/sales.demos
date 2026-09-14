#!/usr/bin/env bash
# ===========================================================================
# portal-mcp-stdio.sh — stdio bridge for the RHDH portal MCP server (#555).
#
# Called by .mcp.json:
#   { "command": "bash", "args": ["utilities/portal-mcp-stdio.sh", "sandbox"] }
#
# Reads the static token and portal URL from .portal/<env>.token and
# .portal/<env>.url (created by make-portal-mcp.sh), then execs supergateway
# to bridge stdio <-> Streamable HTTP with bearer auth.
#
# Same pattern as aap-mcp-stdio.sh — a wrapper that reads credentials from
# gitignored files at launch time, keeping .mcp.json credential-free.
# ===========================================================================
set -euo pipefail

ENV_NAME="${1:-}"
if [[ -z "$ENV_NAME" ]]; then
  echo "usage: portal-mcp-stdio.sh <sandbox|demo>" >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TOKEN_FILE="$REPO_ROOT/.portal/${ENV_NAME}.token"
URL_FILE="$REPO_ROOT/.portal/${ENV_NAME}.url"

if [[ ! -s "$TOKEN_FILE" ]]; then
  echo "No portal MCP token for '$ENV_NAME'." >&2
  echo "Run:  bash utilities/make-portal-mcp.sh $ENV_NAME" >&2
  exit 1
fi

if [[ ! -s "$URL_FILE" ]]; then
  echo "No portal MCP URL for '$ENV_NAME'." >&2
  echo "Run:  bash utilities/make-portal-mcp.sh $ENV_NAME" >&2
  exit 1
fi

TOKEN="$(cat "$TOKEN_FILE")"
URL="$(cat "$URL_FILE")"

exec npx supergateway@3.4.3 \
  --streamableHttp "$URL" \
  --oauth2Bearer "$TOKEN" \
  --logLevel none
