# Architecture — MCP Servers

Reference for the presenter. What exists, how it connects, and how long each
part takes to set up.

This describes the demo as it is *shown*. For **why** it is built this way —
the transport decision, the local-first rationale, the in-cluster AAP
deployment — read
[`docs/plan/platform-addons-plan.md`](../../plan/platform-addons-plan.md).

---

## The flow

```mermaid
flowchart TD
    CC["<b>Claude Code</b><br/><i>laptop</i>"]

    subgraph local ["Local (stdio)"]
        OS["<b>openshift-sandbox</b><br/>read-write · 25 tools"]
        OD["<b>openshift-demo</b><br/>read-only · 16 tools"]
    end

    subgraph cluster ["In-cluster (streamable HTTP)"]
        AS["<b>aap-sandbox</b><br/>read-write · ~140 tools"]
        AD["<b>aap-demo</b><br/>read-only · ~95 tools"]
    end

    CC -->|"kubeconfig<br/>(gitignored)"| OS
    CC -->|"kubeconfig<br/>(gitignored)"| OD
    CC -->|"bearer token<br/>(scope local)"| AS
    CC -->|"bearer token<br/>(scope local)"| AD
```

**Two transports, one reason.** The OpenShift servers run locally because a
stdio server needs no hosting, survives environment churn, and works before a
cluster exists. The AAP servers run in the cluster because they are a platform
component deployed by `setup.yml`. The transport choice follows from that — not
the other way around.

**The environment is in the server's name.** `openshift-sandbox` and
`openshift-demo` are two servers, not one server with a switch. Issue #16 is
the precedent — a single server whose target changed underneath you would
reintroduce the cross-environment confusion. Picking a tool *is* picking an
environment.

---

## Server overview

Full tool listings and verification commands are in
[`server-inventory.md`](server-inventory.md). The condensed table:

| Server | Platform | Transport | Access | Tools | Auth | Source |
|---|---|---|---|---|---|---|
| `openshift-sandbox` | OpenShift | stdio (local) | read-write | 25 | kubeconfig | `.mcp.json` (committed) |
| `openshift-demo` | OpenShift | stdio (local) | read-only | 16 | kubeconfig | `.mcp.json` (committed) |
| `aap-sandbox` | AAP | streamable HTTP | read-write | ~140 | bearer token | `claude mcp add --scope local` |
| `aap-demo` | AAP | streamable HTTP | read-only | ~95 | bearer token | `claude mcp add --scope local` |

Measured 2026-09-03 against `kubernetes-mcp-server@0.0.66` (OpenShift) and
AAP 2.7 / controller 4.8.6 (AAP).

---

## The read-only asymmetry

`--read-only` removes exactly nine tools from the OpenShift server. It does
**not** remove all tools that could theoretically have side effects:

| Survives read-only | Removed by read-only |
|---|---|
| `vm_guest_info` — queries the guest agent | `vm_create`, `vm_clone`, `vm_lifecycle` |
| `vm_troubleshoot` — diagnostic, not mutating | `pods_delete`, `pods_exec`, `pods_run` |
| `pods_log`, `pods_get`, `pods_top` | `resources_create_or_update`, `resources_delete`, `resources_scale` |

The classification is the upstream project's (`kubernetes-mcp-server`), not
ours. The talk track's honest-bits beat says so.

On the AAP side, read-only is controlled by the `aap_mcp_allow_write_operations`
flag on the `AnsibleMCPServer` CR. `demo` is `false`; `sandbox` is `true`.
Changing it requires deleting and recreating the CR — the flag is not idempotent
on the operator. `playbooks/mcp_server.yml` handles the detect-and-recreate
sequence.

---

## What gets created

### OpenShift MCP servers

| Resource | Purpose |
|---|---|
| `.kube/<env>.kubeconfig` | Auth for `kubernetes-mcp-server`, gitignored, mode 0600 |
| `.mcp.json` entries | Server definitions, committed — Claude Code reads these at startup |

Nothing is deployed to the cluster. The server runs as a local subprocess.

### AAP MCP servers

| Resource | Purpose |
|---|---|
| `AnsibleMCPServer` CR in the `aap` namespace | The in-cluster MCP server, deployed by `playbooks/mcp_server.yml` |
| `aap-mcp` Route | Ingress for the MCP server (`ingress_type: Route`, not LoadBalancer — RHDP constraint) |
| Personal access token | OAuth2 bearer token, created via the gateway API |
| `claude mcp add --scope local` registration | Client-side config, not tracked |

---

## What AAP holds

| Type | Name |
|---|---|
| Custom Resource | `AnsibleMCPServer` (`ansiblemcpservers.mcpserver.ansible.com/v1alpha1`) |
| Route | `aap-mcp` in the `aap` namespace |
| Deployment | `aap-mcp` — the pod that serves the MCP endpoint |

**The typed CRD, not `spec.mcp`.** `spec.mcp` is an unvalidated shortcut on the
AAP CR. The typed CRD gets schema validation from the operator and is the path
Red Hat documents.

---

## Credential flow

See [`server-inventory.md`](server-inventory.md#credential-flow) for the full
diagram. Summary:

- **OpenShift:** vault → `make-kubeconfig.sh` → `.kube/<env>.kubeconfig`
  (gitignored) → read by `kubernetes-mcp-server` at startup
- **AAP:** vault → `make-aap-mcp.sh` → creates OAuth token via gateway API →
  `claude mcp add --scope local` (user config, not tracked)

All credentials originate from `playbooks/group_vars/all/secrets.yml`
(vault-encrypted). Nothing is committed in plaintext except the hostnames in
`connection.yml`.

---

## Timing

| Step | Time | Notes |
|---|---|---|
| `make-kubeconfig.sh` per environment | ~5 s | Vault decrypt + file write |
| `make-aap-mcp.sh` per environment | ~10 s | Token creation + route lookup + client registration |
| `/sales-demos-mcp` full run (both environments) | ~2 min | Includes verification |
| `mcp_server.yml` (deploy AAP MCP to cluster) | ~3 min | Part of `/ocpvirt-setup`, not part of `/sales-demos-mcp` |
| AAP MCP pod readiness after deploy | ~60 s | Route returns 503 until the pod serves |

---

## What does not work yet

- **Network vendor MCP servers** — Cisco, Palo Alto, Aruba. Options brief at
  [`docs/plan/network-mcp-plan.md`](../../plan/network-mcp-plan.md), tracked as
  [#94](https://github.com/ericcames/sales.demos/issues/94)
- **Agentic ITSM** — ServiceNow MCP server, read-only, with Ansible as the
  write path.
  [#93](https://github.com/ericcames/sales.demos/issues/93)
- **Agentic observability** — Dynatrace MCP server.
  [#99](https://github.com/ericcames/sales.demos/issues/99)

---

## Cleanup

| Destroyed | Preserved |
|---|---|
| Bearer tokens (manual — see [`server-inventory.md`](server-inventory.md#aap--bearer-token)) | `.mcp.json` (committed) |
| Kubeconfigs (re-generated on next run) | `AnsibleMCPServer` CR (in-cluster, survives client-side cleanup) |
| `claude mcp add` registrations (local only) | Server definitions and access posture |
