# Platform add-ons — MCP servers on this repo's environments

Issue [#102](https://github.com/ericcames/sales.demos/issues/102), a phase of
[#92](https://github.com/ericcames/sales.demos/issues/92).

## Context

This document exists to be **read by someone who has not used MCP before**, and
it explains the mechanism rather than only recording the decision. That is a
departure from the other plan docs here, and it is deliberate.

The goal is narrower than it looks. It is **not** "demo agentic AI." It is: stop
paying a `curl` + vault read + JSON parse every time we need to ask a cluster a
question. That cost is real and this repo pays it constantly — the work in #101
alone hand-rolled that sequence a dozen times.

## What an MCP server actually is

Strip the branding and it is unremarkable: **a process that advertises a list of
typed tools, and runs one when asked.** A tool is a name, a JSON schema for its
arguments, and a result. That is the whole protocol surface that matters here.

The part that decides everything architecturally is **transport** — how the
client talks to the server:

| Transport | Shape | Consequence |
|---|---|---|
| **stdio** | Client launches the server as a subprocess, speaks JSON-RPC over stdin/stdout | Local only. No network, no ports, no TLS, no auth layer — the process boundary *is* the security boundary. |
| **streamable HTTP** | Server is a long-running service at a URL | Remote. Needs hosting, ingress, and its own authentication. |

**This single distinction explains why the network vendor work in
[`network-mcp-plan.md`](network-mcp-plan.md) is hard and this is easy.** Every
vendor server found there is stdio-only and ships no container image, so putting
one on OpenShift means containerize → adapt stdio to streamable HTTP → expose a
Route → authenticate → inject credentials from the vault. That is a real
project, and it is #94's Decision C.

Here we simply *do not need to cross that gap*. Claude Code runs on the laptop.
A stdio server runs on the laptop. There is nothing to host.

## The decision that follows

**The OpenShift MCP server runs locally, not in the cluster.** #92 recorded
`kubernetes-mcp-server` as a "zero-footprint fallback." It is the correct
primary, for three reasons in increasing order of importance:

1. **No hosting.** No operator, no Route, no preview-channel risk, no
   entitlement question. Nothing to install on a cluster at all.
2. **It survives environment churn.** RHDP environments expire — this repo
   discovered *both* of its had (#101). An in-cluster MCP server dies with its
   cluster every time. A local one just re-reads `connection.yml`.
3. **It predates the cluster.** An in-cluster MCP server can never help you
   bootstrap the environment it runs in. A local one is available before an
   environment exists — which was the actual requirement.

The trade is that it is not visible as a platform capability to someone watching
a demo. That matters for the customer-facing story in #93 and #99, and those can
add an in-cluster deployment later. It does not matter for the primary purpose,
which is development speed.

## What is running

`.mcp.json` is **committed**, and defines two servers:

| Server | Kubeconfig | Access | Tools |
|---|---|---|---|
| `openshift-sandbox` | `.kube/sandbox.kubeconfig` | full | 25 |
| `openshift-demo` | `.kube/demo.kubeconfig` | `--read-only` | 16 |

Upstream is [`containers/kubernetes-mcp-server`](https://github.com/containers/kubernetes-mcp-server),
Apache-2.0, pinned at **v0.0.66**. It is a Go binary distributed through npm, so
`npx` is a launcher rather than a real Node dependency; standalone binaries exist
for seven platforms if you would rather not install Node.

### One server per environment, and why that is not fussy

The environment is in the **server's name**, so you select it by selecting the
tool. The alternative — one server whose target changes underneath you — is
precisely the failure #16 fixed: when `sandbox` and `demo` were not kept
distinct, `--limit demo` silently resolved to sandbox's hostname and sandbox's
token, with no warning at all. Repeating that with cluster-write tools attached
would be considerably worse than repeating it with a playbook.

### The asymmetry is deliberate

`sandbox` gets full read/write. It is the environment you break, and the
velocity is the entire point.

`demo` is read-only. It is the environment customers watch.

**And read-only is not crippled** — measured against v0.0.66, `--read-only`
removes exactly the nine mutating tools:

```
pods_delete  pods_exec  pods_run  resources_create_or_update  resources_delete
resources_scale  vm_clone  vm_create  vm_lifecycle
```

Every investigative tool survives, including `vm_guest_info` and
`vm_troubleshoot`. You can still diagnose a broken VM on `demo`; you just cannot
change it. That is #93's *"the agent reads, Ansible writes"* thesis costing
nothing, which is the happy case — on Dynatrace (#99) the same stance costs a
withheld scope, and on ServiceNow (#93) a dedicated `snc_read_only` account.

The `kubevirt` toolset is enabled because this repo is an OpenShift
Virtualization demo: it adds `vm_create`, `vm_clone`, `vm_lifecycle`,
`vm_guest_info` and `vm_troubleshoot` on top of the `core` and `config` defaults.

## Credentials

`kubernetes-mcp-server` authenticates by kubeconfig, and this repo keeps cluster
credentials in a vault. `utilities/make-kubeconfig.sh <env>` bridges the two,
deriving `.kube/<env>.kubeconfig` from the same two sources as everything else:

- `openshift_api_url` — committed plaintext, `group_vars/<env>/connection.yml`
- `openshift_api_token` — vault-encrypted, `playbooks/group_vars/all/secrets.yml`

**Nothing new is stored.** The kubeconfig is a derived artifact: gitignored via
`.kube/`, mode `0600`, regenerable at any time, and safe to delete. That matters
because `CLAUDE.md` twice refuses to keep a second copy of a rotating credential
— the Red Hat offline token (#22) and the PAH API token (#68). A generated file
is not a second copy in that sense; it is a cache with an obvious refresh.

It does go stale silently after a token rotation, which is the one failure mode
to remember. Re-running the generator is the fix.

The script accepts **both** token shapes — `sha256~` OAuth tokens and
ServiceAccount JWTs. #105 exists because a check that accepted only the first
rejected a valid, non-expiring ServiceAccount token and blamed the vault.

## Reusability

Someone else cloning this repo gets the server definitions, the environment
split, and the access asymmetry, because all three live in tracked files rather
than in anyone's setup. What they still need is what the repo already required:
the vault password, and their own environment. MCP adds one prerequisite, `npx`,
recorded in `/sales-demos-first-time` step 4.5.

One rough edge, stated plainly: **a fresh clone shows a failing MCP server until
`/sales-demos-mcp` has been run**, because the committed config references a
kubeconfig that does not exist yet. The alternative was following whatever
`~/.kube/config` happens to point at, which trades a visible, self-explaining
failure for a silent, wrong-environment success. The visible failure is better.

## Still to do — the AAP MCP server

Not built yet. The research is done and recorded in #102:

- The operator owns a **typed** `AnsibleMCPServer` CRD at
  `mcpserver.ansible.com/v1alpha1` — 31 validated spec fields. Use it rather
  than the `spec.mcp` passthrough on the AAP CR, which is
  `x-kubernetes-preserve-unknown-fields` and will accept a misspelled key
  silently.
- `allow_write_operations` is the write toggle. Per Red Hat's own docs,
  **changing it after deployment requires deleting and recreating the CR** — it
  is not idempotent in the usual sense.
- Authentication is an AAP OAuth 2 token that *inherits the user's permissions*,
  which reopens the rotating-credential question above. The proposed answer is
  the same one used here: generate it at skill run time into a gitignored file.
- `service_type` offers `LoadBalancer` and `NodePort`. Both are dead on RHDP
  (#29). Pin `Route` explicitly rather than trusting the default.

## Verification

The rule this repo already holds itself to — *ask the target, do not trust the
recap* — is what `/sales-demos-mcp` does: it starts the server over stdio,
enumerates tools, and makes a live `namespaces_list` call. A written kubeconfig
proves a file exists, not that a cluster accepts it.
