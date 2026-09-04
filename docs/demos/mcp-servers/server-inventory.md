# Server inventory — MCP Servers

Reference for the presenter and the run sheet. The tables below are the same
format Claude Code renders when asked "show me the MCP servers" — so the
audience sees the same view the assistant works from.

---

## The four servers at a glance

Measured 2026-09-03 against `kubernetes-mcp-server@0.0.66` and AAP 2.7
(controller 4.8.6).

| Server | Platform | Transport | Access | Tools | Auth | Source |
|---|---|---|---|---|---|---|
| `openshift-sandbox` | OpenShift | stdio (local) | read-write | 25 | kubeconfig | `.mcp.json` (committed) |
| `openshift-demo` | OpenShift | stdio (local) | read-only | 16 | kubeconfig | `.mcp.json` (committed) |
| `aap-sandbox` | AAP | streamable HTTP | read-write | ~140 | bearer token | `claude mcp add --scope local` |
| `aap-demo` | AAP | streamable HTTP | read-only | ~95 | bearer token | `claude mcp add --scope local` |

**One server per environment, named after it.** The #16 precedent: when two
environments were not kept distinct, `--limit demo` silently resolved to
sandbox's hostname and sandbox's token. The environment is in the server's
*name* so you pick it by picking the tool.

**`demo` is read-only on both platforms.** That is the environment customers
watch. The write path runs against `sandbox` — the environment you break for
velocity.

**Four is the whole list.** There is no ServiceNow, Dynatrace or network vendor
server here, and the tables below are complete rather than abridged. For why
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

### Confirm the client sees all servers

```bash
claude mcp list
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
