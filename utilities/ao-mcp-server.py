#!/usr/bin/env python3
"""MCP server for Automation Orchestrator's REST API.

Exposes AO's key endpoints as MCP tools so Claude Code can inspect
workflows, integrations, identity providers, executions, and AAP
resources proxied through AO — without shelling out to curl.

Auth: JWT via POST /api/v1/auth/login, refreshed automatically before
expiry. Reads credentials from environment variables:
  AO_URL       — base URL (e.g. https://ao-automation-orchestrator.apps.example.com)
  AO_USERNAME  — defaults to "admin"
  AO_PASSWORD  — the AO admin password (= AAP admin password, #143)

Usage (stdio, for .mcp.json or claude mcp add):
  python3 utilities/ao-mcp-server.py

Registered per-environment via `claude mcp add --scope local`, NOT in
the committed .mcp.json, because the password is a credential.
"""

import json
import os
import ssl
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

from mcp.server import MCPServer
from mcp.types import TextContent

AO_URL = os.environ.get("AO_URL", "")
AO_USERNAME = os.environ.get("AO_USERNAME", "admin")
AO_PASSWORD = os.environ.get("AO_PASSWORD", "")

_token: str = ""
_token_expires: float = 0.0

_ssl_ctx = ssl.create_default_context()
_ssl_ctx.check_hostname = False
_ssl_ctx.verify_mode = ssl.CERT_NONE


def _login() -> str:
    global _token, _token_expires
    if _token and time.time() < _token_expires:
        return _token
    body = json.dumps({"username": AO_USERNAME, "password": AO_PASSWORD}).encode()
    req = urllib.request.Request(
        f"{AO_URL}/api/v1/auth/login",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, context=_ssl_ctx) as resp:
        data = json.loads(resp.read())
    _token = data["access_token"]
    _token_expires = time.time() + 840  # 14 minutes (token lasts 15)
    return _token


def _api_get(path: str, params: dict[str, Any] | None = None) -> Any:
    token = _login()
    url = f"{AO_URL}{path}"
    if params:
        # urlencode, not an f-string join: list cursors are opaque tokens
        # and may carry characters that are not safe in a query string.
        qs = urllib.parse.urlencode(
            {k: v for k, v in params.items() if v is not None}
        )
        if qs:
            url = f"{url}?{qs}"
    req = urllib.request.Request(
        url, headers={"Authorization": f"Bearer {token}"}, method="GET"
    )
    try:
        with urllib.request.urlopen(req, context=_ssl_ctx) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        return {"error": e.code, "detail": e.read().decode()[:500]}


def _api_post(path: str, body: dict[str, Any] | None = None) -> Any:
    token = _login()
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(
        f"{AO_URL}{path}",
        data=data,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, context=_ssl_ctx) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        return {"error": e.code, "detail": e.read().decode()[:500]}


def _text(data: Any) -> list[TextContent]:
    return [TextContent(type="text", text=json.dumps(data, indent=2, default=str))]


server = MCPServer("ao-mcp-server")


# ── Version & health ──────────────────────────────────────────────────

@server.tool(description="Get Automation Orchestrator version and API info")
def version() -> list[TextContent]:
    return _text(_api_get("/api/v1/version"))


@server.tool(description="Get the current authenticated user")
def me() -> list[TextContent]:
    return _text(_api_get("/api/v1/auth/me"))


# ── Workflows ─────────────────────────────────────────────────────────

@server.tool(
    description="List workflows in Automation Orchestrator. "
    "Returns name, id, status, and version info. "
    "To page, pass the previous response's `next` value as cursor."
)
def workflows_list(limit: int = 20, cursor: str | None = None) -> list[TextContent]:
    return _text(
        _api_get("/api/v1/workflows", {"limit": limit, "cursor": cursor})
    )


@server.tool(description="Get a specific workflow by ID")
def workflow_get(workflow_id: str) -> list[TextContent]:
    return _text(_api_get(f"/api/v1/workflows/{workflow_id}"))


@server.tool(description="List versions of a specific workflow")
def workflow_versions(workflow_id: str) -> list[TextContent]:
    return _text(_api_get(f"/api/v1/workflows/{workflow_id}/versions"))


# ── Executions ────────────────────────────────────────────────────────

@server.tool(
    description="List workflow executions. "
    "Shows run history with status, start/end times, and workflow reference. "
    "To page, pass the previous response's `next` value as cursor."
)
def executions_list(limit: int = 20, cursor: str | None = None) -> list[TextContent]:
    return _text(
        _api_get("/api/v1/executions", {"limit": limit, "cursor": cursor})
    )


@server.tool(description="Get details of a specific execution")
def execution_get(execution_id: str) -> list[TextContent]:
    return _text(_api_get(f"/api/v1/executions/{execution_id}"))


@server.tool(description="Get activities (steps) for a specific execution")
def execution_activities(execution_id: str) -> list[TextContent]:
    return _text(_api_get(f"/api/v1/executions/{execution_id}/activities"))


# ── Integrations ──────────────────────────────────────────────────────

@server.tool(
    description="List integrations (AAP, MCP servers, LLM providers). "
    "Shows connection status and type."
)
def integrations_list() -> list[TextContent]:
    return _text(_api_get("/api/v1/integrations"))


@server.tool(description="Get a specific integration by ID")
def integration_get(integration_id: str) -> list[TextContent]:
    return _text(_api_get(f"/api/v1/integrations/{integration_id}"))


@server.tool(description="List tools discovered by a specific integration")
def integration_tools(integration_id: str) -> list[TextContent]:
    return _text(_api_get(f"/api/v1/integrations/{integration_id}/tools"))


@server.tool(description="List models available from a specific integration")
def integration_models(integration_id: str) -> list[TextContent]:
    return _text(_api_get(f"/api/v1/integrations/{integration_id}/models"))


# ── Identity providers ────────────────────────────────────────────────

@server.tool(
    description="List identity providers (OIDC/AAP SSO). "
    "Shows whether AAP SSO is configured."
)
def identity_providers_list() -> list[TextContent]:
    return _text(_api_get("/api/v1/identity_providers"))


# ── Credentials ───────────────────────────────────────────────────────

@server.tool(
    description="List credentials stored in AO. "
    "Shows name, type, and which integrations use them. "
    "Sensitive values are always masked."
)
def credentials_list() -> list[TextContent]:
    return _text(_api_get("/api/v1/credentials"))


@server.tool(description="List credential types available in AO")
def credential_types_list() -> list[TextContent]:
    return _text(_api_get("/api/v1/credential_types"))


# ── Projects ──────────────────────────────────────────────────────────

@server.tool(description="List projects in Automation Orchestrator")
def projects_list() -> list[TextContent]:
    return _text(_api_get("/api/v1/projects"))


@server.tool(description="Get a specific project by ID")
def project_get(project_id: str) -> list[TextContent]:
    return _text(_api_get(f"/api/v1/projects/{project_id}"))


# ── Users & groups ────────────────────────────────────────────────────

@server.tool(
    description="List users in Automation Orchestrator. "
    "To page, pass the previous response's `next` value as cursor."
)
def users_list(limit: int = 20, cursor: str | None = None) -> list[TextContent]:
    return _text(
        _api_get("/api/v1/users", {"limit": limit, "cursor": cursor})
    )


@server.tool(description="List groups in Automation Orchestrator")
def groups_list() -> list[TextContent]:
    return _text(_api_get("/api/v1/groups"))


# ── Service accounts ─────────────────────────────────────────────────

@server.tool(description="List service accounts")
def service_accounts_list() -> list[TextContent]:
    return _text(_api_get("/api/v1/service_accounts"))


# ── AAP proxies (AO's view of AAP resources) ─────────────────────────

@server.tool(
    description="List AAP job templates visible through AO's proxy. "
    "These are the JTs AO can use in workflow steps."
)
def proxies_aap_job_templates() -> list[TextContent]:
    return _text(_api_get("/api/v1/proxies/aap/job_templates"))


@server.tool(
    description="Get a specific AAP job template by ID through AO's proxy"
)
def proxies_aap_job_template_get(job_template_id: str) -> list[TextContent]:
    return _text(
        _api_get(f"/api/v1/proxies/aap/job_templates/{job_template_id}")
    )


@server.tool(
    description="List AAP workflow job templates visible through AO's proxy"
)
def proxies_aap_workflow_job_templates() -> list[TextContent]:
    return _text(_api_get("/api/v1/proxies/aap/workflow_job_templates"))


@server.tool(description="List AAP inventories visible through AO's proxy")
def proxies_aap_inventories() -> list[TextContent]:
    return _text(_api_get("/api/v1/proxies/aap/inventories"))


@server.tool(
    description="List AAP execution environments visible through AO's proxy"
)
def proxies_aap_execution_environments() -> list[TextContent]:
    return _text(_api_get("/api/v1/proxies/aap/execution_environments"))


@server.tool(
    description="List AAP credentials visible through AO's proxy"
)
def proxies_aap_credentials() -> list[TextContent]:
    return _text(_api_get("/api/v1/proxies/aap/credentials"))


@server.tool(
    description="List AAP organizations visible through AO's proxy"
)
def proxies_aap_organizations() -> list[TextContent]:
    return _text(_api_get("/api/v1/proxies/aap/organizations"))


# ── Settings ──────────────────────────────────────────────────────────

@server.tool(description="Get AO settings categories")
def settings_categories() -> list[TextContent]:
    return _text(_api_get("/api/v1/settings/categories"))


@server.tool(description="Get a specific AO setting by key")
def setting_get(key: str) -> list[TextContent]:
    return _text(_api_get(f"/api/v1/settings/{key}"))


# ── Tools (AO's tool registry) ───────────────────────────────────────

@server.tool(
    description="List all tools registered in AO (from all integrations)"
)
def tools_list() -> list[TextContent]:
    return _text(_api_get("/api/v1/tools"))


# ── Policies ──────────────────────────────────────────────────────────

@server.tool(description="List policies in Automation Orchestrator")
def policies_list() -> list[TextContent]:
    return _text(_api_get("/api/v1/policies"))


# ── Approvals ─────────────────────────────────────────────────────────

@server.tool(
    description="List pending and completed approvals in AO. "
    "To page, pass the previous response's `next` value as cursor."
)
def approvals_list(limit: int = 20, cursor: str | None = None) -> list[TextContent]:
    return _text(
        _api_get("/api/v1/approvals", {"limit": limit, "cursor": cursor})
    )


if __name__ == "__main__":
    import asyncio
    import sys

    if not AO_URL:
        print("AO_URL environment variable is required", file=sys.stderr)
        raise SystemExit(1)
    if not AO_PASSWORD:
        print("AO_PASSWORD environment variable is required", file=sys.stderr)
        raise SystemExit(1)

    asyncio.run(server.run_stdio_async())
