---
name: sales-demos-mcp
description: "Connect Claude Code directly to this repo's OpenShift clusters over MCP, so asking the cluster a question costs a tool call instead of a hand-rolled curl plus a vault lookup. Generates a per-environment kubeconfig from connection.yml and the vault, then verifies the server answers. TRIGGER when: the user asks to set up, connect, refresh or fix the MCP servers, says an openshift-sandbox or openshift-demo MCP server is failing or shows no tools, or has just repointed an environment or rotated a token. SKIP: if the user wants to install OpenShift Virtualization or apply AAP configuration — that is ocpvirt-setup — or wants to deploy the AAP MCP server into a cluster, which is playbooks/mcp_server.yml run by ocpvirt-setup."
---

# sales-demos-mcp

Makes the cluster directly queryable from Claude Code. Before this, every
question about an environment cost a `curl`, a vault read and a JSON parse;
after it, `namespaces_list` is a tool call.

**No playbook, by design.** This touches the laptop — it writes a kubeconfig
into your working tree and configures your MCP client. It must never run from
AAP, which is the same reasoning that keeps `collections-sync`,
`sales-demos-first-time` and `sales-demos-ee-build` playbook-free.

## What it sets up

`.mcp.json` is committed and defines **two servers, one per environment**:

| Server | Kubeconfig | Access | Tools |
|---|---|---|---|
| `openshift-sandbox` | `.kube/sandbox.kubeconfig` | full read/write | 25 |
| `openshift-demo` | `.kube/demo.kubeconfig` | `--read-only` | 16 |

**One server per environment, named after it, is the whole design.** #16 is the
precedent: when the two environments were not kept distinct, `--limit demo`
silently resolved to sandbox's hostname and sandbox's token with no warning at
all. A single server whose target changed underneath you would reintroduce
exactly that, so the environment is in the server's *name* and you pick it by
picking the tool.

`demo` is read-only because it is the environment customers watch. That is a
deliberate asymmetry, not an oversight — see #102.

**`--read-only` is not crippled.** Measured against v0.0.66, it removes the nine
mutating tools (`pods_delete`, `pods_exec`, `pods_run`,
`resources_create_or_update`, `resources_delete`, `resources_scale`, `vm_clone`,
`vm_create`, `vm_lifecycle`) and keeps every investigative one — including
`vm_guest_info` and `vm_troubleshoot`. Reading a broken VM still works on
`demo`; changing it does not.

The `kubevirt` toolset is enabled because this repo is an OpenShift
Virtualization demo. It supplies `vm_create`, `vm_clone`, `vm_lifecycle`,
`vm_guest_info` and `vm_troubleshoot`.

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

test -f .mcp.json \
  && echo "✅ .mcp.json present" \
  || echo "❌ .mcp.json missing — it is committed; you may be outside the repo root"

test -d "inventory/group_vars/$ENV" \
  && echo "✅ environment '$ENV' exists" \
  || echo "❌ no such environment '$ENV'"
```

If any fails, stop and tell the user which one and the fix beside it.

## Collect inputs

| Variable | Default | Meaning |
|---|---|---|
| `ENV` | `sandbox` | Which environment to (re)generate a kubeconfig for |

Never prompt for a token and never pass one on the command line — that puts it
in shell history. It is read from the vault.

## Run

```bash
bash utilities/make-kubeconfig.sh sandbox
```

Generate `demo` too only if the user is actually working against it. It is the
environment customers watch, and a stale kubeconfig for it is harmless whereas a
confidently wrong one is not.

The file lands at `.kube/<env>.kubeconfig`, mode `0600`. `.gitignore` covers
`.kube/`, and the script writes the token only after locking the file down, so
the credential is never briefly world-readable.

**Restart Claude Code after generating a kubeconfig for the first time.** MCP
servers are launched at startup; a server whose kubeconfig did not exist then
stays failed until it is relaunched.

## Verify — ask the server, not the config

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

Finally, confirm the client sees them:

```bash
claude mcp list
```

## The AAP MCP server — registered locally, deployed by Phase 0

The OpenShift servers above are stdio and need no hosting. The AAP MCP server is
the other shape: it **runs in the cluster** and is reached over HTTPS, because
it is a component of the platform rather than a client-side tool.

`playbooks/mcp_server.yml` deploys it, and `setup.yml` runs that on every
environment, so a freshly built environment arrives with it already on. Nothing
to do here for the server itself.

What is left is the client half, and it is **deliberately not in `.mcp.json`**:
it needs a bearer token, and `.mcp.json` is committed. Register it in your own
local config instead.

```bash
ENV=${ENV:-sandbox}
VAULT_ID="sales.demos@$HOME/secrets/.vault_pass_sales_demos"

AAP_HOST=$(ansible -i inventory --limit "$ENV" aap -m debug --vault-id "$VAULT_ID" \
  -a 'msg={{ aap_hostname }}' 2>/dev/null | sed -n 's/.*"msg": "\(.*\)"/\1/p')
AAP_PASS=$(ansible-vault view playbooks/group_vars/all/secrets.yml --vault-id "$VAULT_ID" 2>/dev/null \
  | ENV="$ENV" python3 -c 'import sys,yaml,os; print(yaml.safe_load(sys.stdin)["env_secrets"][os.environ["ENV"]]["aap_password"])')

# Tokens moved in 2.7: /api/controller/v2/tokens/ is 404, the gateway owns them.
TOKEN=$(curl -sk -u "admin:$AAP_PASS" -X POST "https://$AAP_HOST/api/gateway/v1/tokens/" \
  -H 'Content-Type: application/json' \
  -d "{\"description\":\"sales.demos MCP ($ENV)\",\"scope\":\"write\"}" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["token"])')

MCP_HOST=$(KUBECONFIG=$PWD/.kube/$ENV.kubeconfig oc get route aap-mcp -n aap -o jsonpath='{.spec.host}')

claude mcp add --transport http --scope local "aap-$ENV" "https://$MCP_HOST/mcp" \
  --header "Authorization: Bearer $TOKEN"
```

**`--scope local` is the load-bearing flag.** It writes to your own config, not
to the committed `.mcp.json`, so the token never becomes a tracked file. That is
the same reasoning that keeps the Red Hat offline token (#22) and the PAH API
token (#68) out of the vault: a rotating credential should have exactly one
copy, in the place that issued it.

Two consequences to be honest about:

- **This token does not clean itself up.** `CLAUDE.md` requires playbooks that
  create tokens to delete them in an `always:` block, and this one deliberately
  survives — an MCP client needs a durable credential. It is therefore the one
  token in this repo you must retire by hand. List and delete them with:
  ```bash
  curl -sk -u "admin:$AAP_PASS" "https://$AAP_HOST/api/gateway/v1/tokens/"
  curl -sk -u "admin:$AAP_PASS" -X DELETE "https://$AAP_HOST/api/gateway/v1/tokens/<id>/"
  ```
- **The token inherits your permissions.** Red Hat's docs: *"The AI tool will
  inherit the user's permissions for API token-based authentication."* Creating
  it as `admin` gives the agent admin. Use `scope=read` on anything you care
  about — the environment's own `allow_write_operations` is a second gate, not
  the only one.

Verify by asking the server, as ever:

```bash
curl -sk -o /dev/null -w '%{http_code}\n' -X POST "https://$MCP_HOST/mcp" \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"verify","version":"0"}}}'
```

`200` and a body naming `"serverInfo":{"name":"aap"}` is the pass. **A `503` means
the Route is admitted but the pod is not serving yet** — wait and retry rather
than assuming a misconfiguration. Measured on a working sandbox: **140 tools**,
including `job_templates_launch_create`, `workflow_job_templates_launch_create`
and `jobs_stdout_retrieve`.

## If it fails

| Symptom | Cause | Fix |
|---|---|---|
| MCP server shows as failed at startup | Kubeconfig does not exist yet | Run the generator, then restart Claude Code |
| `401 Unauthorized` on a tool call | Token in the vault is stale or the environment expired | Update `env_secrets.<env>.openshift_api_token`, re-run the generator |
| `could not resolve <env> token` | Vault password wrong, or `env_secrets.<env>` missing | `/sales-demos-first-time` step 2 |
| `dial tcp: no such host` | The RHDP environment has expired | Check `connection.yml` points at a live cluster — both had expired once before (#101) |
| Tools present but every call fails | Kubeconfig points at a different cluster than you think | `oc whoami --show-server` with `KUBECONFIG` set |
| AAP MCP returns `503` | Route admitted, pod not serving yet | Wait — `oc get deploy aap-mcp -n aap`; this is normal for ~60s after deploy |
| AAP MCP returns `401` | Token expired or deleted | Re-create it and re-run `claude mcp add --scope local` |
| AAP MCP write tools missing | `aap_mcp_allow_write_operations` is false for this environment | Intentional on `demo`. Changing it needs a delete-and-recreate — re-run `mcp_server.yml`, which handles that |
| `npx: command not found` | Node not installed | See preflight; a standalone binary is the alternative |

Never paste a live token into a commit message, issue, or PR. This repo is
public — see `CLAUDE.md`.
