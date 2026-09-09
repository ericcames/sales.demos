# Server inventory — MCP Servers

Reference for the presenter and the run sheet. The tables below are the same
format Claude Code renders when asked "show me the MCP servers" — so the
audience sees the same view the assistant works from.

---

## The six servers at a glance

Measured 2026-09-03 (OpenShift sandbox/demo, AAP), 2026-09-06 (Grafana) and
2026-09-09 (`openshift-edge`) against `kubernetes-mcp-server@0.0.66`, AAP 2.7
(controller 4.8.6), and `mcp-grafana` via `uvx`.

| Server | Platform | Transport | Access | Tools | Auth | Source |
|---|---|---|---|---|---|---|
| `openshift-sandbox` | OpenShift | stdio (local) | read-write | 25 | kubeconfig | `.mcp.json` (committed) |
| `openshift-demo` | OpenShift | stdio (local) | read-only | 16 | kubeconfig | `.mcp.json` (committed) |
| `openshift-edge` | OpenShift | stdio (local) | read-write | 25 | kubeconfig | `.mcp.json` (committed) |
| `aap-sandbox` | AAP | streamable HTTP | read-write | ~140 | bearer token | `claude mcp add --scope local` |
| `aap-demo` | AAP | streamable HTTP | read-only | ~95 | bearer token | `claude mcp add --scope local` |
| `grafana` | Grafana Cloud | stdio (local) | read-only (Viewer) | 81 | SA token | `claude mcp add --scope local` |

**One server per environment, named after it** — except Grafana. The #16
precedent: when two environments were not kept distinct, `--limit demo` silently
resolved to sandbox's hostname and sandbox's token. The environment is in the
server's *name* so you pick it by picking the tool. Grafana Cloud is a single
external instance that spans every environment, so one server named `grafana`
rather than one per cluster.

**`edge` is the third environment, and it is a different kind of thing.**
`sandbox` and `demo` are ephemeral RHDP clusters; `edge` is a persistent
bare-metal Single Node OpenShift box on a home network. It is read-write like
`sandbox` — you own the hardware and no customer is watching it.

**`demo` is read-only on both platforms.** That is the environment customers
watch. The write path runs against `sandbox` — the environment you break for
velocity. Grafana is read-only by a different mechanism — the service account
has the Viewer role, so write tools are exposed but the token lacks permission
to execute them.

**Six is the whole list.** There is no ServiceNow, Dynatrace or network vendor
server here, and the tables below are complete rather than abridged.

**There is no `aap-edge` server.** `edge` runs AAP, but the MCP server for it
has not been built: `utilities/make-aap-mcp.sh` takes only `sandbox` and
`demo`, and it defaults anything that is not `demo` to **write** scope, so
adding `edge` is a posture decision rather than a one-line change. If asked,
say that plainly — three OpenShift servers, two AAP. For why
ServiceNow is absent rather than pending, see [`servicenow.md`](servicenow.md);
for what building one would take, [`building-a-server.md`](building-a-server.md).

---

## OpenShift MCP servers — tool listing

### `openshift-sandbox` — 25 tools (read-write)

| Tool | Description |
|---|---|
| `configuration_view` | View cluster configuration |
| `events_list` | List cluster events |
| `namespaces_list` | List all namespaces |
| `nodes_log` | Get node logs |
| `nodes_stats_summary` | Get node statistics summary |
| `nodes_top` | Show node resource usage |
| `pods_delete` | Delete a pod |
| `pods_exec` | Execute a command in a pod |
| `pods_get` | Get pod details |
| `pods_list` | List pods across all namespaces |
| `pods_list_in_namespace` | List pods in a specific namespace |
| `pods_log` | Get pod logs |
| `pods_run` | Run a new pod |
| `pods_top` | Show pod resource usage |
| `projects_list` | List OpenShift projects |
| `resources_create_or_update` | Create or update a Kubernetes resource |
| `resources_delete` | Delete a Kubernetes resource |
| `resources_get` | Get a specific resource |
| `resources_list` | List resources by type |
| `resources_scale` | Scale a deployment/statefulset |
| `vm_clone` | Clone a virtual machine |
| `vm_create` | Create a virtual machine |
| `vm_guest_info` | Get guest OS information from a VM |
| `vm_lifecycle` | Start, stop, restart, or migrate a VM |
| `vm_troubleshoot` | Diagnose VM issues |

### `openshift-edge` — 25 tools (read-write)

Identical to `openshift-sandbox` above — same `kubernetes-mcp-server` version,
same `core,config,kubevirt` toolsets, no `--read-only`. The list is not
repeated here because it is the same list; if the two ever differ, one of the
three `.mcp.json` entries has drifted.

Measured 2026-09-09 against the live SNO: `namespaces_list` returns a cluster
running `openshift-cnv`, `openshift-compliance`, `aap` and `grafana-alloy`.

### `openshift-demo` — 16 tools (read-only)

The same list minus the nine mutating tools below.

| Tool | Description |
|---|---|
| `configuration_view` | View cluster configuration |
| `events_list` | List cluster events |
| `namespaces_list` | List all namespaces |
| `nodes_log` | Get node logs |
| `nodes_stats_summary` | Get node statistics summary |
| `nodes_top` | Show node resource usage |
| `pods_get` | Get pod details |
| `pods_list` | List pods across all namespaces |
| `pods_list_in_namespace` | List pods in a specific namespace |
| `pods_log` | Get pod logs |
| `pods_top` | Show pod resource usage |
| `projects_list` | List OpenShift projects |
| `resources_get` | Get a specific resource |
| `resources_list` | List resources by type |
| `vm_guest_info` | Get guest OS information from a VM |
| `vm_troubleshoot` | Diagnose VM issues |

### The nine tools `--read-only` removes

| Tool | What it does | Why it is removed |
|---|---|---|
| `pods_delete` | Delete a pod | Mutating |
| `pods_exec` | Execute a command in a running pod | Arbitrary command execution |
| `pods_run` | Run a new pod | Creates a workload |
| `resources_create_or_update` | Create or update any Kubernetes resource | Mutating |
| `resources_delete` | Delete any Kubernetes resource | Mutating |
| `resources_scale` | Scale a deployment or statefulset | Mutating |
| `vm_clone` | Clone a virtual machine | Creates a workload |
| `vm_create` | Create a virtual machine | Creates a workload |
| `vm_lifecycle` | Start, stop, restart, or migrate a VM | Mutating |

`vm_guest_info` and `vm_troubleshoot` survive read-only — they query the guest
agent, they do not change anything.

---

## AAP MCP servers — tool listing

<!-- Phase 2: fill in the AAP tool listings with representative tools and
     categories. The ~140 tools on aap-sandbox include job_templates_launch_create,
     workflow_job_templates_launch_create, jobs_stdout_retrieve, and the full
     CRUD surface for AAP objects. The ~95 tools on aap-demo are the read-only
     subset. -->

*AAP tool listings will be added when the AAP MCP content is filled in
(Phase 2). Tool counts above are measured; the per-tool breakdown is pending.*

---

## Grafana Cloud MCP server — 81 tools

Measured 2026-09-06. The server is the official `mcp-grafana` from Grafana Labs
(Apache-2.0), run locally via `uvx`. The service account has the **Viewer**
role — write tools are exposed but return `403` when called.

| Category | Representative tools | Count |
|---|---|---|
| Dashboards | `search_dashboards`, `get_dashboard_by_uid`, `get_dashboard_summary`, `get_dashboard_panel_queries`, `get_panel_image`, `update_dashboard` | 8 |
| Prometheus | `query_prometheus`, `query_prometheus_histogram`, `list_prometheus_metric_names`, `list_prometheus_label_names` | 6 |
| Loki | `query_loki_logs`, `query_loki_patterns`, `query_loki_stats`, `list_loki_label_names`, `analyze_loki_labels` | 8 |
| Alerting | `alerting_manage_rules`, `alerting_manage_routing`, `alerting_manage_silences`, `get_alert_group`, `list_alert_groups`, `update_alert_group` | 6 |
| Incidents | `create_incident`, `get_incident`, `list_incidents`, `update_incident`, `add_activity_to_incident`, `list_incident_custom_fields` | 6 |
| Tempo (traces) | `tempo_traceql-search`, `tempo_get-trace`, `tempo_trace-diff`, `tempo_traceql-metrics-range`, `tempo_get-attribute-names` | 9 |
| Pyroscope (profiling) | `query_pyroscope`, `list_pyroscope_profile_types`, `list_pyroscope_label_names` | 4 |
| OnCall | `get_current_oncall_users`, `list_oncall_schedules`, `list_oncall_teams`, `list_oncall_users`, `get_oncall_shift` | 5 |
| Datasources | `list_datasources`, `get_datasource`, `create_datasource`, `update_datasource`, `check_datasources_health` | 5 |
| Annotations | `create_annotation`, `get_annotations`, `update_annotation`, `get_annotation_tags` | 4 |
| Sift | `get_sift_analysis`, `get_sift_investigation`, `list_sift_investigations`, `find_error_pattern_logs`, `find_slow_requests` | 5 |
| Navigation & docs | `generate_deeplink`, `search_docs`, `get_doc`, `search_plugin_information` | 4 |
| Snapshots | `create_snapshot`, `delete_snapshot`, `get_snapshot`, `list_snapshots` | 4 |
| Other | `user_info`, `grafana_api_request`, `get_assertions`, `search_folders`, `create_folder`, `get_plugin`, `install_plugin`, `validate_provisioning_file`, `list_provisioning_repositories`, `suggest_loki_alloy_label_config` | 11 |

**Read-only is not enforced at the server.** Unlike OpenShift's `--read-only`
(which removes tools) or AAP's `aap_mcp_allow_write_operations` (which changes
the tool surface), the Grafana server exposes all 81 tools regardless of the
service account's role. Write calls (`update_dashboard`, `create_incident`,
etc.) simply fail with `403`. The governance is in the token, not the tool
surface.

---

## Credential flow

### OpenShift — kubeconfig

```
secrets.yml (vault-encrypted)
    └── openshift_api_token
connection.yml (plaintext, committed)
    └── openshift_api_url

        ↓  utilities/make-kubeconfig.sh <env>

.kube/<env>.kubeconfig (gitignored, mode 0600)

        ↓  read at server startup

kubernetes-mcp-server (stdio, local process)
```

The kubeconfig is generated, not committed. `.kube/` is gitignored. The script
writes the token only after locking down file permissions, so the credential is
never briefly world-readable.

### AAP — bearer token

```
secrets.yml (vault-encrypted)
    └── aap_admin_password
connection.yml (plaintext, committed)
    └── aap_hostname

        ↓  utilities/make-aap-mcp.sh <env>

1. Creates a personal access token via the gateway API
   POST /api/gateway/v1/tokens/
   scope: "write" (sandbox) or "read" (demo)

2. Finds the aap-mcp Route via the kubeconfig
   oc get route aap-mcp -n aap

3. Registers with Claude Code
   claude mcp add --transport http --scope local

        ↓  stored in user's local Claude config (not tracked)

aap-<env> MCP server (streamable HTTP, in-cluster)
```

**The AAP token does not clean itself up.** It is the one documented exception
to the repo's rule that created tokens must be deleted in an `always:` block.
To retire stale tokens:

```bash
# List tokens
curl -sk -H "Authorization: Bearer <token>" \
  https://<aap_hostname>/api/gateway/v1/tokens/ | python3 -m json.tool

# Delete a token by ID
curl -sk -X DELETE -H "Authorization: Bearer <token>" \
  https://<aap_hostname>/api/gateway/v1/tokens/<id>/
```

### Grafana Cloud — service account token

```
secrets.yml (vault-encrypted)
    ├── grafana_cloud_url
    └── grafana_cloud_sa_token

        ↓  utilities/make-grafana-mcp.sh

claude mcp add --scope local
    -e GRAFANA_URL=...
    -e GRAFANA_SERVICE_ACCOUNT_TOKEN=...
    grafana -- uvx mcp-grafana

        ↓  env vars read at server startup

mcp-grafana (stdio, local process via uvx)
```

**No token creation step.** Unlike the AAP flow, which mints a token via the
gateway API, the Grafana Cloud service account token is created once in the
Grafana UI and stored in the vault. `make-grafana-mcp.sh` reads it from the
vault and passes it as an environment variable — there is nothing to mint and
nothing to rotate automatically.

**The token does not clean itself up either.** Same exception as AAP. Revoke it
in the Grafana Cloud UI: Administration > Service Accounts > \<account\> >
Tokens > Delete.

---

## Verification commands

### OpenShift — prove the server starts and answers

```bash
KUBECONFIG=$PWD/.kube/sandbox.kubeconfig oc whoami
KUBECONFIG=$PWD/.kube/sandbox.kubeconfig oc get nodes -o name
```

Then confirm the MCP server itself starts (independent of the client):

```bash
python3 - <<'PY'
import json, subprocess, os, sys
kc = os.path.abspath(".kube/sandbox.kubeconfig")
p = subprocess.Popen(
    ["npx","-y","kubernetes-mcp-server@0.0.66","--kubeconfig",kc,
     "--toolsets","core,config,kubevirt","--disable-multi-cluster"],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
send = lambda o: (p.stdin.write(json.dumps(o)+"\n"), p.stdin.flush())
send({"jsonrpc":"2.0","id":1,"method":"initialize","params":{
    "protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"verify","version":"0"}}})
info = json.loads(p.stdout.readline())["result"]["serverInfo"]
send({"jsonrpc":"2.0","method":"notifications/initialized"})
send({"jsonrpc":"2.0","id":2,"method":"tools/list"})
tools = json.loads(p.stdout.readline())["result"]["tools"]
p.terminate()
print(f"server        : {info.get('name')} {info.get('version')}")
print(f"tools exposed : {len(tools)}")
print("\nMCP VERIFIED" if len(tools) >= 20 else "\nVERIFICATION FAILED")
sys.exit(0 if len(tools) >= 20 else 1)
PY
```

Expect 25 tools on `sandbox`, 16 on `demo`.

### AAP — prove the route serves

```bash
ENV=sandbox
MCP_HOST=$(KUBECONFIG=$PWD/.kube/$ENV.kubeconfig oc get route aap-mcp -n aap -o jsonpath='{.spec.host}')

curl -sk -o /dev/null -w '%{http_code}\n' -X POST "https://$MCP_HOST/mcp" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"verify","version":"0"}}}'
```

`200` with `"serverInfo":{"name":"aap"}` is the pass. A `503` means the Route
is admitted but the pod is not serving yet — wait, do not reconfigure.

### Grafana Cloud — prove the server connects

The Grafana MCP server is stdio — it starts and stops with Claude Code. After
running `make-grafana-mcp.sh`, restart Claude Code and confirm:

```bash
claude mcp list   # grafana should appear
```

Then call a read-only tool to verify the SA token works:

```bash
# Inside Claude Code, ask:
#   "What datasources are configured in Grafana?"
# The assistant calls mcp__grafana__list_datasources
```

A fresh free-tier instance may have no datasources yet — an empty list with no
error is a pass.

### Confirm the client sees all servers

```bash
claude mcp list   # all six servers should appear
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| MCP server shows as failed at startup | Kubeconfig does not exist yet | Run the generator, then restart Claude Code |
| `401 Unauthorized` on a tool call | Token in the vault is stale or the environment expired | Update `env_secrets.<env>.openshift_api_token`, re-run the generator |
| `could not resolve <env> token` | Vault password wrong, or `env_secrets.<env>` missing | `/sales-demos-first-time` step 2 |
| `dial tcp: no such host` | The RHDP environment has expired | Check `connection.yml` points at a live cluster |
| Tools present but every call fails | Kubeconfig points at a different cluster than you think | `oc whoami --show-server` with `KUBECONFIG` set |
| AAP MCP returns `503` | Route admitted, pod not serving yet | Wait — `oc get deploy aap-mcp -n aap`; normal for ~60 s after deploy |
| AAP MCP returns `401` | Token expired or deleted | Re-create: `bash utilities/make-aap-mcp.sh <env>` |
| AAP MCP write tools missing | `aap_mcp_allow_write_operations` is false | Intentional on `demo`. Changing it requires delete-and-recreate — re-run `mcp_server.yml` |
| `npx: command not found` | Node not installed | See preflight in the `/sales-demos-mcp` skill |
| `no aap-mcp route` | MCP server not deployed | Run `/ocpvirt-setup` or `playbooks/mcp_server.yml` first |
| `grafana` not in `claude mcp list` | Server not registered yet | Run `bash utilities/make-grafana-mcp.sh`, then restart Claude Code |
| Grafana tool returns `401` | SA token revoked or expired | Recreate the token in the Grafana Cloud UI, update the vault, re-run `make-grafana-mcp.sh` |
| Grafana tool returns `403` | SA has Viewer role, cannot write | Intentional — read-only governance is in the token. If write access is needed, change the SA role in the Grafana UI |
| `uvx: command not found` | uv not installed | Install uv: `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
