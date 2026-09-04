---
name: sales-demos-mcp
description: "Connect Claude Code to this repo's OpenShift clusters and AAP instances over MCP — four servers, one skill. Generates per-environment kubeconfigs for OpenShift and auto-creates bearer tokens for AAP, then verifies every server answers. TRIGGER when: the user asks to set up, connect, refresh or fix the MCP servers, says an openshift-sandbox, openshift-demo, aap-sandbox or aap-demo MCP server is failing or shows no tools, or has just repointed an environment or rotated a token. SKIP: if the user wants to install OpenShift Virtualization or apply AAP configuration — that is ocpvirt-setup — or wants to deploy the AAP MCP server into a cluster, which is playbooks/mcp_server.yml run by ocpvirt-setup."
---

# sales-demos-mcp

Makes both the clusters and AAP instances directly queryable from Claude Code.
Before this, every question about an environment cost a `curl`, a vault read and
a JSON parse; after it, `namespaces_list` or `job_templates_list` is a tool call.

**No playbook, by design.** This touches the laptop — it writes kubeconfigs,
creates tokens, and configures your MCP client. It must never run from AAP,
which is the same reasoning that keeps `collections-sync`,
`sales-demos-first-time` and `sales-demos-ee-build` playbook-free.

## What it sets up

**Four servers, one per environment per platform:**

| Server | Auth | Access | Source |
|---|---|---|---|
| `openshift-sandbox` | kubeconfig | read-write | `.mcp.json` (committed) |
| `openshift-demo` | kubeconfig | read-only | `.mcp.json` (committed) |
| `aap-sandbox` | bearer token | read-write | `claude mcp add --scope local` |
| `aap-demo` | bearer token | read-only | `claude mcp add --scope local` |

**One server per environment, named after it, is the whole design.** #16 is the
precedent: when the two environments were not kept distinct, `--limit demo`
silently resolved to sandbox's hostname and sandbox's token with no warning at
all. A single server whose target changed underneath you would reintroduce
exactly that, so the environment is in the server's *name* and you pick it by
picking the tool.

`demo` is read-only on both platforms because it is the environment customers
watch. That is a deliberate asymmetry, not an oversight — see #102.

### OpenShift servers

`.mcp.json` is committed and defines the two OpenShift servers. `demo` has
`--read-only`, which removes the nine mutating tools and keeps every
investigative one — including `vm_guest_info` and `vm_troubleshoot`.

The `kubevirt` toolset is enabled because this repo is an OpenShift
Virtualization demo. It supplies `vm_create`, `vm_clone`, `vm_lifecycle`,
`vm_guest_info` and `vm_troubleshoot`.

### AAP servers

The AAP MCP servers **run in the cluster** (deployed by `playbooks/mcp_server.yml`,
which `setup.yml` calls). The client side needs a bearer token, and tokens must
not go in tracked files, so they are registered with `claude mcp add --scope
local`.

`utilities/make-aap-mcp.sh` automates the full flow: resolve credentials from
the vault, create a personal access token via the gateway API, find the MCP
route, and register the server. For `demo`, the token scope is `read`; for
`sandbox`, it is `write`. The environment's own
`aap_mcp_allow_write_operations` is a second gate on the server side.

**`.claude/settings.json` allowlists `mcp__aap-sandbox__*` and `mcp__aap-demo__*`
for servers that are deliberately NOT in `.mcp.json`, and that mismatch is
correct** (#131). A fresh clone therefore carries two permission entries
pointing at nothing until this skill runs — that is the expected state, not a
broken config, and it resolves the moment the servers are registered. The
alternative would be putting a bearer token in a tracked file. Neither file can
say so in place: both are strict JSON and take no comments, which is why it is
recorded here.

**These tokens do not clean themselves up.** They are the documented exception
in CLAUDE.md — an MCP client needs a durable credential, so the `always:` block
rule does not apply. The script prints cleanup instructions; retiring them is
manual.

## Preflight Check

Every one must pass.

```bash
ENV=${ENV:-sandbox}

test -s "$HOME/secrets/.vault_pass_sales_demos" \
  && echo "✅ vault password file" \
  || echo "❌ ~/secrets/.vault_pass_sales_demos missing — see /sales-demos-first-time step 2"

head -c 15 playbooks/group_vars/all/secrets.yml 2>/dev/null | grep -q '^\$ANSIBLE_VAULT' \
  && echo "✅ secrets.yml is vault-encrypted" \
  || echo "❌ secrets.yml is NOT encrypted — stop, do not commit"

command -v npx >/dev/null \
  && echo "✅ npx ($(node --version)) — needed to launch kubernetes-mcp-server" \
  || echo "❌ npx not found — install Node.js, or fetch the pinned binary from https://github.com/containers/kubernetes-mcp-server/releases"

command -v claude >/dev/null \
  && echo "✅ claude CLI available" \
  || echo "❌ claude CLI not found — needed for 'claude mcp add'"

test -f .mcp.json \
  && echo "✅ .mcp.json present" \
  || echo "❌ .mcp.json missing — it is committed; you may be outside the repo root"

# The kubeconfig for this environment still points AT this environment.
# Generating it once is not enough: repointing an environment edits
# connection.yml and the vault and does NOT regenerate this file (#161). The
# failure is otherwise a DNS error naming a dead cluster, which says nothing
# about kubeconfigs.
bash utilities/check-kubeconfig.sh "$ENV" 2>&1 || true

test -d "inventory/group_vars/$ENV" \
  && echo "✅ environment '$ENV' exists" \
  || echo "❌ no such environment '$ENV'"
```

If any fails, stop and tell the user which one and the fix beside it.

## Collect inputs

| Variable | Default | Meaning |
|---|---|---|
| `ENV` | `sandbox` | Which environment to (re)generate servers for |

Never prompt for a token and never pass one on the command line — that puts it
in shell history. Everything is read from the vault.

## Run

### Step 1 — OpenShift kubeconfig

```bash
bash utilities/make-kubeconfig.sh sandbox
```

Generate `demo` too only if the user is actually working against it. It is the
environment customers watch, and a stale kubeconfig for it is harmless whereas a
confidently wrong one is not.

The file lands at `.kube/<env>.kubeconfig`, mode `0600`. `.gitignore` covers
`.kube/`, and the script writes the token only after locking the file down, so
the credential is never briefly world-readable.

### Step 2 — AAP MCP server

Run **after** the kubeconfig exists — the script needs it to find the MCP route.

```bash
bash utilities/make-aap-mcp.sh sandbox
```

For `demo`:

```bash
bash utilities/make-aap-mcp.sh demo
```

The script creates a personal access token, finds the `aap-mcp` route via the
kubeconfig, and registers the server with `claude mcp add --scope local`.

**Restart Claude Code after running for the first time.** MCP servers are
launched at startup; a server that was not registered then stays absent until
the client is relaunched.

## Verify — ask the server, not the config

### OpenShift

**A generated kubeconfig is not proof.** It proves a file was written, not that
the cluster accepts it. Ask the target:

```bash
KUBECONFIG=$PWD/.kube/sandbox.kubeconfig oc whoami
KUBECONFIG=$PWD/.kube/sandbox.kubeconfig oc get nodes -o name
```

Then prove the MCP server itself starts and answers, independent of the client:

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
send({"jsonrpc":"2.0","id":3,"method":"tools/call",
      "params":{"name":"namespaces_list","arguments":{}}})
got = json.loads(p.stdout.readline())
p.terminate()
ok = info.get("name") == "kubernetes-mcp-server" and len(tools) >= 20 and "result" in got
print(f"server        : {info.get('name')} {info.get('version')}")
print(f"tools exposed : {len(tools)}")
print(f"live call     : {'namespaces_list returned data' if 'result' in got else got}")
print("\nMCP VERIFIED" if ok else "\nVERIFICATION FAILED — do not report success")
sys.exit(0 if ok else 1)
PY
```

Expect 25 tools on `sandbox`. If it returns 16, the `--read-only` flag is being
applied to the wrong server — check which entry in `.mcp.json` was launched.

### AAP

Verify the AAP MCP server by hitting its endpoint directly:

```bash
ENV=${ENV:-sandbox}
VAULT_ID="sales.demos@$HOME/secrets/.vault_pass_sales_demos"
MCP_HOST=$(KUBECONFIG=$PWD/.kube/$ENV.kubeconfig oc get route aap-mcp -n aap -o jsonpath='{.spec.host}')

curl -sk -o /dev/null -w '%{http_code}\n' -X POST "https://$MCP_HOST/mcp" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"verify","version":"0"}}}'
```

`200` and a body naming `"serverInfo":{"name":"aap"}` is the pass. **A `503` means
the Route is admitted but the pod is not serving yet** — wait and retry rather
than assuming a misconfiguration. Measured on a working sandbox: **140 tools**,
including `job_templates_launch_create`, `workflow_job_templates_launch_create`
and `jobs_stdout_retrieve`.

Finally, confirm the client sees all servers:

```bash
claude mcp list
```

## If it fails

| Symptom | Cause | Fix |
|---|---|---|
| MCP server shows as failed at startup | Kubeconfig does not exist yet | Run the generator, then restart Claude Code |
| `401 Unauthorized` on a tool call | Token in the vault is stale or the environment expired | Update `env_secrets.<env>.openshift_api_token`, re-run the generator |
| `could not resolve <env> token` | Vault password wrong, or `env_secrets.<env>` missing | `/sales-demos-first-time` step 2 |
| `dial tcp: no such host` | The RHDP environment has expired | Check `connection.yml` points at a live cluster — both had expired once before (#101) |
| Tools present but every call fails | Kubeconfig points at a different cluster than you think | `oc whoami --show-server` with `KUBECONFIG` set |
| AAP MCP returns `503` | Route admitted, pod not serving yet | Wait — `oc get deploy aap-mcp -n aap`; this is normal for ~60s after deploy |
| AAP MCP returns `401` | Token expired or deleted | Re-create it: `bash utilities/make-aap-mcp.sh <env>` |
| AAP MCP write tools missing | `aap_mcp_allow_write_operations` is false for this environment | Intentional on `demo`. Changing it needs a delete-and-recreate — re-run `mcp_server.yml`, which handles that |
| `npx: command not found` | Node not installed | See preflight; a standalone binary is the alternative |
| `no aap-mcp route` from make-aap-mcp.sh | MCP server not deployed | Run `/ocpvirt-setup` or `playbooks/mcp_server.yml` first |

Never paste a live token into a commit message, issue, or PR. This repo is
public — see `CLAUDE.md`.
