---
name: sales-demos-mcp
description: "Connect Claude Code directly to this repo's OpenShift clusters over MCP, so asking the cluster a question costs a tool call instead of a hand-rolled curl plus a vault lookup. Generates a per-environment kubeconfig from connection.yml and the vault, then verifies the server answers. TRIGGER when: the user asks to set up, connect, refresh or fix the MCP servers, says an openshift-sandbox or openshift-demo MCP server is failing or shows no tools, or has just repointed an environment or rotated a token. SKIP: if the user wants to install OpenShift Virtualization or apply AAP configuration — that is ocpvirt-setup — or is asking about the AAP MCP server, which is issue #102 and not built yet."
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

## If it fails

| Symptom | Cause | Fix |
|---|---|---|
| MCP server shows as failed at startup | Kubeconfig does not exist yet | Run the generator, then restart Claude Code |
| `401 Unauthorized` on a tool call | Token in the vault is stale or the environment expired | Update `env_secrets.<env>.openshift_api_token`, re-run the generator |
| `could not resolve <env> token` | Vault password wrong, or `env_secrets.<env>` missing | `/sales-demos-first-time` step 2 |
| `dial tcp: no such host` | The RHDP environment has expired | Check `connection.yml` points at a live cluster — both had expired once before (#101) |
| Tools present but every call fails | Kubeconfig points at a different cluster than you think | `oc whoami --show-server` with `KUBECONFIG` set |
| `npx: command not found` | Node not installed | See preflight; a standalone binary is the alternative |

Never paste a live token into a commit message, issue, or PR. This repo is
public — see `CLAUDE.md`.
