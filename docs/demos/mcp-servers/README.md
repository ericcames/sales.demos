# Demo: MCP Servers — Agentic Automation with Governance

**Start here.** A customer watches an AI assistant query a live OpenShift
cluster and launch an Ansible job template — reading everything, changing
nothing except through the governed automation path — in about twenty minutes.

| | |
|---|---|
| **Length** | 20 minutes (15 + 5 for questions) |
| **Audience** | Platform engineers and automation leads evaluating how AI fits into operations |
| **Reader** | The Ansible pre-sales engineer presenting it |
| **Needs a live environment?** | **Yes** — the compelling beats are live queries against a real cluster |
| **Status** | Draft — OpenShift MCP content complete, AAP MCP content is placeholder |

---

## The five documents (plus one)

| File | Read it when |
|---|---|
| [`run-sheet.md`](run-sheet.md) | **While presenting.** Minute markers, what is on screen, exact commands, recovery moves |
| [`talk-track.md`](talk-track.md) | **While rehearsing.** The narrative and the actual words, beat by beat |
| [`architecture.md`](architecture.md) | **When asked "how does that work".** The four servers, the credential flow, the access posture |
| [`objections.md`](objections.md) | **Before you go in.** What this audience asks — especially the security questions |
| [`server-inventory.md`](server-inventory.md) | **When asked "what can it do".** Full tool listings, status tables, verification commands |

Present from the run sheet. Rehearse from the talk track. The other three are
reference.

**Why a sixth file.** The detailed status tables, per-server tool listings, and
verification commands that `run-sheet.md` and `architecture.md` cite would
overwhelm either one — the same reason Private Automation Hub earned
[`clickops.md`](../private-automation-hub/clickops.md).

---

## The 60-second version

1. **Show the four MCP servers and their access posture** — two OpenShift
   (local, one read-write, one read-only), two AAP (in-cluster, same split).
   The environment is in the server's *name*, and the audience sees the posture
   before a single query runs.
2. **Issue a read-only query against the cluster** — ask what VMs are running,
   what pods are in a namespace, what a guest's OS version is. The assistant
   gets real data, not a summary or a slide.
3. **Launch a job template through AAP** — the governed write path. The
   assistant requests a change, AAP enforces its own RBAC and survey, the audit
   trail is in the controller.

**What the demo is actually about** is not that AI can talk to infrastructure.
It is that the boundary between what the AI can read and what it can change is
visible, enforced, and auditable — and that the change path is the same
governed Ansible workflow the customer already trusts.

---

## Why it mostly works without a cluster

The status tables in [`server-inventory.md`](server-inventory.md) are committed
and render on GitHub. The architecture diagram is Mermaid. The tool listings
were measured on live servers and documented with their provenance.

**But the demo's strongest beats need a warm environment.** A live query
returning real cluster state is the cold open, and no screenshot replaces it.
If you are presenting without a cluster, lead with the architecture and the
status tables, and be upfront that these are documented measurements rather
than a live run.

---

## If you want to run it live

```bash
/sales-demos-mcp          # sets up all four servers — kubeconfigs + AAP tokens
```

Then verify the servers answer — the skill does this automatically, but if
you want to confirm independently:

```bash
claude mcp list           # all four servers should appear
```

New to this repo? Run `/sales-demos-first-time` first.

---

## Red Hat resources

| Resource | What it covers |
|---|---|
| [Model Context Protocol specification](https://modelcontextprotocol.io/) | The protocol itself — what MCP is and why it exists |
| [kubernetes-mcp-server](https://github.com/containers/kubernetes-mcp-server) | The upstream project powering the OpenShift MCP servers (Apache-2.0) |
| [Deploying the Ansible MCP Server](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.5/html/using_ansible_automation_platform/extend-assembly_deploying_ansible_mcp_server) | Official Red Hat guide for the AAP MCP server |
| [Deploy MCP servers on OpenShift using ToolHive](https://developers.redhat.com/articles/2025/10/01/how-deploy-mcp-servers-openshift-using-toolhive) | Red Hat Developer article on containerised MCP hosting |
| [ansible.mcp_builder](https://github.com/redhat-cop/ansible.mcp_builder) | Red Hat CoP collection for building MCP servers into container images |

---

## Related

- [`../../plan/platform-addons-plan.md`](../../plan/platform-addons-plan.md) —
  why the MCP servers are built this way: the transport decision, the local-first
  rationale, the in-cluster AAP deployment
- [`../../plan/network-mcp-plan.md`](../../plan/network-mcp-plan.md) — the
  next use case: network vendor MCP servers
- [`../../../ROADMAP.md`](../../../ROADMAP.md) — what is done and what is not
- [`../../../README.md`](../../../README.md) — the repo itself
