#!/usr/bin/env bash
# ===========================================================================
# aap-mcp-stdio.sh — stdio bridge for the AAP MCP server. Issue #515.
#
# Called by .mcp.json:
#   { "command": "bash", "args": ["utilities/aap-mcp-stdio.sh", "sandbox"] }
#
# Reads the PAT and route URL from .aap/<env>.token and .aap/<env>.url
# (created by make-aap-mcp.sh), then execs supergateway to bridge
# stdio <-> Streamable HTTP with bearer auth.
#
# WHY A WRAPPER AND NOT INLINE IN .mcp.json. The token is a credential.
# .mcp.json is committed. A wrapper reads the token from a gitignored file
# at launch time — same pattern as the kubeconfig paths for the OpenShift
# servers, except those are read by kubernetes-mcp-server directly.
# ===========================================================================
set -euo pipefail

ENV_NAME="${1:-}"
if [[ -z "$ENV_NAME" ]]; then
  echo "usage: aap-mcp-stdio.sh <sandbox|demo>" >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TOKEN_FILE="$REPO_ROOT/.aap/${ENV_NAME}.token"
URL_FILE="$REPO_ROOT/.aap/${ENV_NAME}.url"

if [[ ! -s "$TOKEN_FILE" ]]; then
  echo "No AAP MCP token for '$ENV_NAME'." >&2
  echo "Run:  bash utilities/make-aap-mcp.sh $ENV_NAME" >&2
  exit 1
fi

if [[ ! -s "$URL_FILE" ]]; then
  echo "No AAP MCP URL for '$ENV_NAME'." >&2
  echo "Run:  bash utilities/make-aap-mcp.sh $ENV_NAME" >&2
  exit 1
fi

TOKEN="$(cat "$TOKEN_FILE")"
URL="$(cat "$URL_FILE")"

exec npx supergateway@3.4.3 \
  --streamableHttp "$URL" \
  --oauth2Bearer "$TOKEN" \
  --logLevel none
