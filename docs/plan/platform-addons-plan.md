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

## Measure the environment first

Everything below assumes the cluster can carry it. That assumption was never
checked, and when it finally was, the repo's own figure turned out to be off by
five times.

`terraform/ocpvirt/variables.tf` declared `available_memory_gb = 14`. Measured
on sandbox 2026-09-03 with `playbooks/probe_env.yml`:

| | Value |
|---|---|
| Allocatable | 31.5 vCPU / 124.68 GiB |
| Requested | 14.5 vCPU / 49.05 GiB |
| **Free by requests** | **17.0 vCPU / 75.63 GiB** |
| Free by live usage | 96.42 GiB — informational |
| Recommended `available_memory_gb` | **67** |

**Nothing reported the drift, and nothing could have.** The budget guard in
`locals.tf` fails closed: a too-small figure does not error, it silently refuses
tiers the cluster could run. The demo gets smaller and no one learns why. That
is the failure mode a probe exists to catch — not a crash, a quiet shrinking.

**Requests are what schedule, not usage.** The scheduler places pods and KubeVirt
VMs against requests; live consumption is irrelevant to whether the next one
fits. The 21 GiB gap between the two rows above is the whole reason both are
printed. Optimising against live usage would suggest 96 GiB of room that does
not exist.

Against that measurement the add-ons are not close to a constraint — the four
not-yet-installed candidates in `inventory/group_vars/aap/probe_workloads.yml`
total an estimated 19.7 GiB, leaving ~56 GiB. **Those are estimates**, each
tagged with a `source:` string saying so, because a guessed number and a
measured one look identical once written down — which is exactly how `14`
survived. Replace each as its add-on gets installed.

Both add-on operators this plan depends on were confirmed present on the
cluster's OperatorHub by the same run: `mcp-gateway` and
`automation-orchestrator-operator`.

Re-run it on any new or resized environment: `sales-demos-probe-env`. It is
strictly read-only, so it is safe mid-demo.

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

## The AAP MCP server — the other shape

The OpenShift server is stdio and needs no hosting. The AAP one **runs in the
cluster** and is reached over HTTPS, because it is a component of the platform
rather than a client-side tool. `playbooks/mcp_server.yml` deploys it, and
`setup.yml` runs that as stage 3 of 4, so a freshly built environment arrives
with it already on.

### Use the typed CRD, not the documented shortcut

Red Hat's docs tell you to add an `mcp:` block to the AAP CR. That works and it
is the wrong choice here. Measured on the live 2.7 CRD:

```json
spec.mcp -> { "type": "object", "x-kubernetes-preserve-unknown-fields": true }
```

No sub-properties, so **the API server accepts any key under it — including a
misspelling — and reports success.** A typo yields a green run and no server.

The operator also owns a properly typed CRD, which is what `spec.mcp` produces
anyway: `ansiblemcpservers.mcpserver.ansible.com`, 31 validated fields. Applying
that directly means a bad field name is rejected at apply time. It also avoids
editing the CR that governs controller, hub and EDA on a node AAP shares with
everything else.

`ingress_type` and `service_type` are both stated rather than inherited:
`ingress_type: Route` is what makes the server reachable at all, and
`service_type: ClusterIP` keeps it off `LoadBalancer` and `NodePort`, which are
dead on RHDP (#29). `Route` is not a legal `service_type` — the two keys carry
different enums, and it is the service type that #29 constrains. Each value is
also the CRD's current default; both are pinned anyway, so an operator upgrade
cannot move them out from under a working deployment.

### The one genuine trap

Red Hat's documentation, verbatim:

> "If you changed the permissions of the MCP server after it was created and
> deployed, you must delete the `AnsibleMCPServer` custom resource and recreate
> it."

So `allow_write_operations` is **not idempotent in the usual sense** — a plain
apply that flips it leaves a server still enforcing the old permission while the
CR claims the new one. `mcp_server.yml` reads the live object and deletes it when
the flag differs. That is why the playbook looks more complicated than an apply,
and it should not be simplified.

The write posture itself is per-environment and **deliberately not defaulted** —
the playbook refuses to run without it, because a silent default is the wrong way
to decide whether an agent can POST, PATCH and DELETE:

| Environment | `aap_mcp_allow_write_operations` |
|---|---|
| `sandbox` | `true` |
| `demo` | `false` |

### What it exposes

Measured on a working sandbox: **140 tools**, including
`job_templates_launch_create`, `workflow_job_templates_launch_create` and
`jobs_stdout_retrieve` — precisely steps 4 and 5 of the demo stories in #93 and
#99.

**This is not an ungoverned agent, and the distinction is worth stating.** #93's
thesis is *"the MCP server reads; every write goes through an Ansible job
template."* Launching a job template through the AAP MCP server **is** that
governed path: versioned, surveyed, RBAC-gated, and logged where the audit trail
is the AAP job output rather than a chat log. Write access adds the ability to
launch the governed thing, not to bypass it.

### Authentication, and an honest exception

The client authenticates with an AAP OAuth 2 token. Red Hat's docs: *"The AI
tool will inherit the user's permissions for API token-based authentication."*
So the token, not just `allow_write_operations`, bounds what the agent can do —
creating it as `admin` gives the agent admin.

That token is **not** in `.mcp.json`, which is committed. It is registered with
`claude mcp add --scope local`, writing to the operator's own config. And it is
a documented exception to `CLAUDE.md`'s rule that a created token must be
deleted in an `always:` block — an MCP client needs a durable credential, so
cleanup would destroy the thing it was made for. Three things keep that honest:
no playbook creates it, it is never committed, and it is the one token in this
repo you retire by hand.

Tokens moved in 2.7, incidentally: `/api/controller/v2/tokens/` returns **404**,
and the gateway owns them at `/api/gateway/v1/tokens/`.

### A Route is not proof

The first live run returned **503** on a freshly admitted Route — the router had
a backend with nothing behind it yet. `mcp_server.yml` now waits for the
Deployment to report a ready replica, not merely for the Route to exist. A 503
shortly after deploy is normal and means "wait", not "misconfigured".

## Verification

The rule this repo already holds itself to — *ask the target, do not trust the
recap* — is what `/sales-demos-mcp` does: it starts the server over stdio,
enumerates tools, and makes a live `namespaces_list` call. A written kubeconfig
proves a file exists, not that a cluster accepts it.

## Automation Orchestrator — the experiment, and its answer

Issue [#108](https://github.com/ericcames/sales.demos/issues/108), split out of
#102 so an entitlement failure could not block the MCP work.

**Installed on `sandbox`/`cluster-kbjvc` 2026-09-03.** #92 could only say the
operator was *present in the catalog*, and was careful that catalog presence is
not entitlement. It has now been installed, so the guess is retired.

### Outcome 1: it installs, and the images pull

```
automation-orchestrator-operator.v2026.8.1787147047   Succeeded   InstallSucceeded
automation-orchestrator-operator-controller-manager-5bf5bb...   1/1   Running
```

`stable` still resolves to **v2026.8.1787147047**, the exact version #92
recorded, so the catalog has not moved under us. The bundle unpacked and the
controller image pulled from `registry.redhat.io` under this environment's
existing pull secret with no extra credential. **No separate pull secret was
needed to install the operator.**

That is the narrow claim, and it is worth keeping narrow: the *operator*
installs. Whether the product it manages is licensed here is a different
question, and the manifest is explicit that it is separately subscribed —
`operators.openshift.io/valid-subscription: ["Red Hat Ansible Automation
Orchestrator"]`. It also self-describes as `certified: "false"`,
`maturity: "alpha"`, and `operator-type: non-standalone`.

### The footprint, measured twice

`probe_env.yml` was run immediately before and immediately after, which is the
whole reason #100 landed first:

| | Requested CPU | Requested memory | Free by requests |
|---|---|---|---|
| Before | 15.00 vCPU | 50.30 GiB | 74.38 GiB |
| After | 15.01 vCPU | 50.37 GiB | 74.31 GiB |
| **Delta** | **+0.01 vCPU** | **+0.07 GiB** | −0.07 GiB |

Read back from the pod itself, the operator requests `cpu: 10m` /
`memory: 64Mi` (limits `500m` / `256Mi`) in a single `manager` container. The
two numbers agree, which is the point of measuring both ways.

`available_memory_gb` is **unchanged at 66** — the recommendation was 66 before
the install and 66 after. Nothing in `terraform/` needs to move.

**The estimate it replaces was 2.0 vCPU / 4.0 GiB** — about 64x the memory. It
was honestly labelled the least trustworthy figure in
`probe_workloads.yml`, and it was.

### The real blocker is not entitlement, it is PostgreSQL

Installing the operator gets you a CRD and a controller. Getting a *running*
Automation Orchestrator needs an `AutomationOrchestrator` CR, and the CRD
requires this and will not default it:

```
spec required:              ['postgres']
spec.postgres required:     ['backendDatabase', 'host', 'temporalDatabase']
```

**There is no embedded database option.** It is bring-your-own PostgreSQL, and
it needs *two distinct databases* — one for the backend, one for Temporal — each
supplied as a secret with `database`, `username`, `password`, plus a host, and
optionally a CA cert secret for TLS. The operator ships images for a backend, a
Temporal server, a UI and a redis, but not for a database.

So the answer to *"can we demo Automation Orchestrator on RHDP?"* is: **not as
it stands.** The operator installs for free, and the next person hits a
provisioning problem, not a licensing one. That is a materially better place to
start than #92 could offer, and it is a different obstacle than the one the
issue expected to find.

### What is left installed, and how to remove it

The operator is **left running on `sandbox`** — 64 MiB is not worth reclaiming,
and leaving it lets the next session go straight at the CR question. It is
scoped to its own namespace, labelled `sales.demos/experiment=issue-108`, and
the entire experiment reverses with one delete:

```bash
oc delete namespace automation-orchestrator-operator-system
oc delete crd automationorchestrators.aap.ansible.com
```

It is deliberately **not** in `setup.yml` and has no playbook or skill. #108
left that decision open pending this outcome, and the outcome says the operator
is the cheap part — a playbook that installs a controller nobody can
instantiate would be automating the wrong half.

Only `AllNamespaces` install mode is supported (`OwnNamespace`,
`SingleNamespace` and `MultiNamespace` are all `supported: false`), so it needs
a cluster-scoped OperatorGroup. That is why it went into its own namespace with
an empty-spec OperatorGroup rather than alongside CNV.
