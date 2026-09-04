# Building an MCP server when none exists

Reference for the presenter and for anyone extending this repo. What to do when
the platform you want an agent to read has no MCP server — or has one you would
not put in front of a customer.

This is not hypothetical. It is [#94](https://github.com/ericcames/sales.demos/issues/94)'s
situation with every network vendor, and it is why
[`servicenow.md`](servicenow.md) recommends waiting rather than adopting.

---

## First: do you actually need to build one?

Four questions, in order. Stop at the first "no".

| | Question | If no |
|---|---|---|
| 1 | **Does an official vendor server exist?** | Build one. Nothing else to evaluate. |
| 2 | **Can its tool surface be constrained?** | Build one — see below, this is the question people skip. |
| 3 | **Is there a container image, if you need to host it?** | Containerise it, or build one. |
| 4 | **Would you hand it to a customer?** | Build one. |

**Question 2 is the one that gets skipped, and it is the one that matters.**
A server you cannot constrain is a server whose governance lives entirely in the
credential you hand it. That may be fine. It is not fine when the demo's whole
thesis is that the boundary is visible and enforced.

Two live examples from this repo, on either side of that line:

- `kubernetes-mcp-server` has a `--read-only` flag that **removes nine mutating
  tools from the protocol surface**. The agent cannot call what does not exist.
  That is structural, and it is why `openshift-demo` is safe to run in front of
  a customer.
- The community ServiceNow servers have no equivalent — no read-only mode, no
  tool filtering. Enforcement has to move to the account, which is a weaker and
  much less demonstrable place to put it. That is a large part of why
  [`servicenow.md`](servicenow.md) does not recommend them.

---

## What language

The honest answer is that the two servers this repo already runs are the two
answers, and they are different on purpose.

### Go, when the server ships

Reach for Go when the server will run in a cluster, or be handed to somebody
else to run.

A Go MCP server compiles to a **static binary**: a small image, no interpreter,
and no dependency resolution at run time. That is not a micro-optimisation — it
is the difference between a server that works on someone else's laptop and one
that needs a working Python before it starts.

`kubernetes-mcp-server` is the proof, and this repo depends on the consequence.
It is a Go native implementation that talks to the Kubernetes API directly
rather than shelling out to `kubectl`. From that one codebase it ships as a
native binary, an npm package, a PyPI package, a container image, and a Helm
chart. Which is why:

- `.mcp.json` can invoke it with `npx` and get a real binary, not a Node
  reimplementation
- `/sales-demos-first-time` step 4.5 records `npx` as the **only** command-line
  prerequisite MCP adds — and marks it optional at that

### Python, when you are reaching

Reach for Python when you are wrapping something whose SDK is already Python, or
when the point is to get from an idea to a working tool in an afternoon.

It is also the ecosystem this repo lives in. `ansible.mcp_builder` packages
PyPI-published servers into Execution Environments, and an EE is already a
Python container.

The cost is the one Go avoids: your image carries an interpreter and a
dependency tree, and "it works here" stops being portable.

### Everything else

All SDKs speak the same protocol; they differ in tier and in how much of the
current spec they track. Tiers as of the 2026-07-28 specification:

| Tier | SDKs |
|---|---|
| **Tier 1** | TypeScript, Python, C#, Go, Rust |
| **Tier 2** | Java, Ruby |
| **Tier 3** | Swift, PHP, Kotlin |

Current list and per-language guides: [modelcontextprotocol.io/docs](https://modelcontextprotocol.io/docs/2026-07-28/sdk).
Deliberately linked rather than transcribed — this table will go stale and that
one will not.

**TypeScript is Tier 1 and the reference implementation**, and it is the right
answer if your team already writes TypeScript. It is the wrong answer here
purely because it adds a Node runtime to an image for no benefit this repo
would use.

---

## Transport: write stdio, ship streamable HTTP

Write stdio first. It needs no hosting, no TLS, no ingress and no auth layer —
the client launches your process and talks to it over pipes. You can have a
working tool before you have decided anything about deployment.

Ship streamable HTTP when the server has to live somewhere. An in-cluster
server has no stdio to speak.

**This repo runs one of each, and the split is not arbitrary.** The OpenShift
servers are stdio because a local process survives environment churn and works
before a cluster exists; the AAP server is in-cluster over streamable HTTP
because it is a platform component that `setup.yml` deploys. The transport
follows from what the server *is*. Reasoning in
[`docs/plan/platform-addons-plan.md`](../../plan/platform-addons-plan.md).

The step between them — adapting a stdio server to streamable HTTP, putting it
behind a Route, and injecting credentials from the vault — is the work
[`network-mcp-plan.md`](../../plan/network-mcp-plan.md) calls the Foundation
task. Every vendor server it surveyed is stdio-only with no container image, so
that adaptation is not optional there.

---

## Packaging: `ansible.mcp_builder`, and what it actually does

[`ansible.mcp_builder`](https://github.com/redhat-cop/ansible.mcp_builder) is a
Red Hat CoP collection, and it is worth being precise about it because the name
suggests something it is not.

**It does not scaffold a server.** It *installs pre-built* servers — from npm,
PyPI, compiled Go binaries, or source — into an Ansible Execution Environment,
and emits a manifest so the `ansible.mcp` collection can run them. It is a
packaging step that runs after you have a server, not a way to get one.

It works through `append_final`:

```yaml
additional_build_steps:
  append_final: |
    RUN ansible-playbook ansible.mcp_builder.install_mcp \
      -e mcp_servers=github_mcp -e github_mcp_mode=remote
```

Then `ansible-builder build`.

That hook is already familiar here — `execution-environment.yml:107` uses
`append_final` to install the terraform CLI. Note the same gotcha
`utilities/build-ee.sh:18-19` records: **every `append_final` step runs as
root, before `USER 1000`**, so an in-Containerfile check does not prove the
runtime user can execute what you installed. Verify unprivileged after the
build, which is what that script exists to do.

---

## Hosting: options, not a recommendation

Three mechanisms, deliberately not ranked here:

| Mechanism | Shape | Note |
|---|---|---|
| Plain manifests | Deployment + Service + Route | What `playbooks/mcp_server.yml` already does for AAP. Nothing to learn, nothing to depend on |
| `mcp-gateway` operator | One endpoint fronting several servers | In this cluster's catalog on the `preview` channel — attractive, and preview |
| [ToolHive](https://developers.redhat.com/articles/2025/10/01/how-deploy-mcp-servers-openshift-using-toolhive) | Containerised MCP hosting on OpenShift | Red Hat Developer article, not a product commitment |

**This choice is open and stays open.**
[`network-mcp-plan.md`](../../plan/network-mcp-plan.md) holds it as Decision C,
pending network SME review, because the answers to its Decisions A and B change
which mechanism is right — a server holding firewall credentials wants the
gateway's identity-aware routing, a knowledge server needing no credentials does
not. Do not settle it from this page.

---

## Governance, whoever wrote it

The repo's standing stance does not change because you wrote the server:
**the server reads, Ansible writes.** The MCP server supplies context; the
mutation goes through a job template that can be read, versioned, and audited.

Building it yourself buys one real advantage, and it is the one Question 2
above was about: **you choose the tool surface.** You can ship a server that
has no write tools at all — not disabled, not gated behind a flag, absent. That
is the strongest form of the guarantee, and it is unavailable from a
third-party server you cannot constrain.

Two things follow that are easy to get wrong:

- **A credential is not a tool boundary.** A read-only account is a real control
  and a good second gate, but it is invisible to the audience and it fails
  open the moment someone reuses the credential elsewhere. Prefer removing the
  tool.
- **Ship the posture in the server's name.** `openshift-sandbox` versus
  `openshift-demo` is this repo's #16 precedent: one server whose target or
  posture changed underneath you is how cross-environment mistakes happen.
  Picking a tool should *be* picking an environment.

---

## Related

- [`servicenow.md`](servicenow.md) — the worked case: why waiting beats adopting
- [`architecture.md`](architecture.md) — the four servers this repo runs
- [`../../plan/platform-addons-plan.md`](../../plan/platform-addons-plan.md) —
  the transport decision and the credential pattern, with reasoning
- [`../../plan/network-mcp-plan.md`](../../plan/network-mcp-plan.md) — the
  vendor-gap survey and the three open decisions
- [Build a server](https://modelcontextprotocol.io/docs/2026-07-28/develop/build-server) —
  the upstream tutorial
