# Network MCP servers on OpenShift — the repo's third use case

## Context

The question: **can an AI assistant be given real, grounded context about Cisco,
Palo Alto and Aruba networks — served from MCP servers running on the RHDP
OpenShift environment — so that developing network automation stops being an
exercise in guessing module names and remembering what the firewall is actually
configured to do?**

**Answer: partly, and the gap is not where you would expect it.** The protocol
side is solved and the hosting side has good Red Hat answers. What is *not*
solved is supply: **vendor-supplied MCP servers exist for Cisco only.** Palo
Alto's official server serves the wrong product, and Aruba has nothing official
at all despite appearances.

> **This document is an options brief, not a settled design.** That is a
> deliberate departure from the other two plan docs in this repo, which record
> decisions already made and the evidence behind them. Three decisions here —
> **A**, **B** and **C** below — are held open on purpose, because they turn on
> network-engineering judgement rather than on anything measurable from this
> repo. They are written to be read by someone who has never seen this codebase.
> Tracked in [#94](https://github.com/ericcames/sales.demos/issues/94).

This is not greenfield. It **depends on
[#92](https://github.com/ericcames/sales.demos/issues/92)**, whose Phase 3 is MCP
servers and whose live probe of the sandbox recorded an `mcp-gateway` operator in
the catalog. It inherits the governance thesis established in
[#93](https://github.com/ericcames/sales.demos/issues/93): **the MCP server is
read-only; every write goes through an Ansible job template in AAP.**

### What the vendor landscape actually gives you

Researched 2026-09-02. Every support-status claim below is quoted from the
vendor, not inferred from where the code is hosted.

| Vendor | Component | Finding |
|---|---|---|
| Cisco | [`devnet-content-search-mcp`](https://github.com/CiscoDevNet/devnet-content-search-mcp) | **Official.** Semantic search over Cisco's own API specifications. Needs no device and no tenant — it grounds code, not operations. |
| Cisco | [`cisco-meraki-mcp-official`](https://blogs.cisco.com/developer/build-agentic-networking-experiences-with-meraki-and-catalyst-center-mcp-servers) | **Official OSS, beta.** Meraki Dashboard, read-only. A Cisco-hosted remote variant also exists for teams wanting no operational overhead. |
| Cisco | [`catc-mcp-oss`](https://github.com/cisco-en-programmability/catc-mcp-oss) | **Official OSS, beta.** Catalyst Center, read-only — inventory, device health, wireless experience, compliance. |
| Cisco | IOS / NX-OS CLI | **No official server.** Community only, e.g. [pyATS_MCP](https://github.com/automateyournetwork/pyATS_MCP). |
| Palo Alto | [Cortex MCP server](https://www.paloaltonetworks.com/blog/security-operations/introducing-the-cortex-mcp-server/) | **Official** (Dec 2025) — but it serves **XSIAM / Cortex Cloud SecOps data, not PAN-OS firewall configuration**. |
| Palo Alto | PAN-OS firewall | **No official server.** Community only: [cdot65](https://github.com/cdot65/pan-os-mcp), [edoscars](https://github.com/edoscars/pan-os-mcp), [apius-tech](https://github.com/apius-tech/Palo-MCP). All wrap the PAN-OS XML API. |
| Aruba | [`central-mcp-server`](https://developer.arubanetworks.com/new-central/docs/central-mcp-server) | **Not official**, despite being documented on HPE's own developer portal. Read-only (GET only), stdio, `uvx`-installed, credentials in a local config file, **no container image**. |
| Aruba | AOS-CX | **No official server.** Community only, e.g. [aruba-cx-mcp-server](https://github.com/slientnight/aruba-cx-mcp-server). |

The Aruba entry is the one to read twice. HPE's portal hosts the documentation,
which makes the server look sanctioned. The page says otherwise, verbatim:

> "This is **not** an officially supported product of HPE. It is provided as-is,
> with no warranty or guarantee of fitness for any purpose."

Repos under the `CiscoDevNet` org suffixed `-community`
(`meraki-magic-mcp-community`, `catalyst-sdwan-mcp-community`) are org-hosted but
are likewise **not** supported product. Org ownership is not a support statement.

### What the Red Hat platform actually gives you

| Component | Finding |
|---|---|
| [`redhat-cop/ansible.mcp_builder`](https://github.com/redhat-cop/ansible.mcp_builder) | Technology Preview. Roles that build MCP servers from npm, PyPI or source **into a container image via `ansible-builder`** — the exact shape of the problem below. This repo already owns that machinery: `execution-environment.yml`, `utilities/build-ee.sh`, and the `sales-demos-ee-build` skill. |
| [ToolHive / MCP lifecycle operator](https://developers.redhat.com/articles/2025/10/01/how-deploy-mcp-servers-openshift-using-toolhive) | An `MCPServer` CR produces a proxyrunner pod that runs the server as a StatefulSet behind a reverse HTTP proxy with session management, converting HTTP into JSON-RPC over the server's stdin/stdout. Purpose-built for stdio servers on Kubernetes. |
| MCP gateway (Red Hat Connectivity Link 1.4) | Istio plus Gateway API. Identity-aware routing and per-tool metrics across registered servers. Very likely what the `mcp-gateway` v0.7.1 preview operator found in #92 is. A **front door**, complementary to the runtime above rather than a replacement for it. |
| [AAP MCP server](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/extend-assembly_deploying_ansible_mcp_server) | Technology Preview on **2.6 as well as 2.7**. Exposes job query, fact gathering and workflow launch. This is the ready-made **write path** for the #93 governance thesis. |
| `ansible.mcp` | **Runs the opposite direction from what the name suggests.** It gives *playbooks* modules to discover and call tools on MCP servers — Ansible as MCP *client*. It is not a way to expose Ansible as MCP. Already syncing into this repo's PAH at `hub/certified-requirements.yml:37` and referenced nowhere else. Useful later for agentic workflows; not useful for this foundation. |

Because the AAP MCP server exists on 2.6, **#92 is a sequencing preference here,
not a hard block.** The work could begin on the current sandbox.

### Constraints that shape the design

1. **Every server found is stdio transport and ships no container image.**
   Cisco's, Palo Alto's community ones, Aruba's — all of them. So "run MCP servers
   on OpenShift" is not a deployment exercise. The actual work is
   **containerize → adapt stdio to streamable HTTP → expose via Route →
   authenticate → inject credentials from the vault.** That adaptation layer is
   the foundation, and it is vendor-independent.

2. **They are all read-only already.** Every vendor-supplied and portal-documented
   server found exposes GET operations only. The #93 governance stance —
   read-only MCP, writes through AAP — therefore costs nothing here. It is a
   description of what the software already does, not a restriction imposed on it.

3. **There is no network gear yet.** Not in RHDP, not on the cluster, not on a
   vendor tenant. Any option that requires a live device is blocked until one is
   sourced, and that sourcing is itself an open question (Decision B). Any option
   that does not require a device can start today. This asymmetry drives more of
   the plan than the vendor-support question does.

4. **The consumer is Claude Code on the laptop**, over streamable HTTP through an
   OpenShift Route. Not an in-cluster agent. That fixes the transport target and
   means authentication has to work for a client outside the cluster.

5. **Credentials go in the vault, and only in the vault.** PAN-OS API keys and
   Aruba Central OAuth tokens would land in
   `playbooks/group_vars/all/secrets.yml` under `env_secrets`, and reach a pod as
   a Secret. See `CLAUDE.md` → *Secrets: exactly one mechanism*. Every device
   server added is new secret surface; every server that needs no device is none.

6. **Catalog presence is not entitlement.** #92's own caveat. `mcp-gateway`
   appearing in the sandbox operator catalog does not mean it can be installed and
   used.

### Scope

In scope: the hosting pattern for third-party MCP servers on OpenShift, and the
per-vendor decision about what to host.

Out of scope, deliberately: Red Hat's own MCP servers — the AAP MCP server and
`mcp-gateway` themselves belong to **#92 Phase 3**. This document owns the
*third-party vendor* servers that sit on top of that. The two are cited as
dependencies, not merged.

Also out of scope for now: F5 and Infoblox. They appear in the DC1 roadmap and
would inherit this identical foundation, so the SME conversation may be worth
widening — see Open items.

---

## The transport problem is the design

Strip away the vendor question and the foundation reduces to one thing. An MCP
server written for a laptop assumes it is a subprocess: the client launches it,
writes JSON-RPC to its stdin, reads from its stdout, and owns its lifetime. None
of that survives contact with Kubernetes, where the process must outlive any one
client, be reachable over the network, authenticate strangers, and hold
credentials it did not get from a file in someone's home directory.

Four mechanisms can bridge that gap, and they are not mutually exclusive —
C2 is a front door that expects C1 or C3 behind it.

| | Mechanism | For | Against |
|---|---|---|---|
| **C1** | ToolHive / MCP lifecycle operator (`MCPServer` CR) | Purpose-built for exactly this: stdio→HTTP with session management, least custom code, declarative CR | Another operator to install; preview maturity |
| **C2** | `mcp-gateway` (Connectivity Link; already in the sandbox catalog per #92) | Identity-aware routing, per-tool metrics, one front door for every server | It is a gateway, not a runtime — needs C1 or C3 behind it |
| **C3** | `ansible.mcp_builder` + Deployment + Route | Reuses this repo's existing EE build pipeline and `sales-demos-ee-build` skill; most idiomatic to this codebase; Red Hat CoP content | Technology Preview; still needs a stdio→HTTP wrapper of its own |
| **C4** | Hand-rolled Containerfile + supergateway-style wrapper | No new dependencies, fully understood, nothing preview | Most code to own; reinvents C1 badly |

**C3 deserves a closer look than its novelty suggests**, because the argument for
it is not technical merit in isolation — it is that this repo already builds
container images from Ansible content, already has a skill that does it, and
already has a job template that consumes the result. C1 is the better tool;
C3 is the better fit. That tension is a real decision, not a formality.

## Governance: read-only, and the write path already exists

Inherited from #93 and free here, per Constraint 2.

The assistant reads live network state and official documentation through MCP.
When something must *change*, it does not change it — it launches an AAP job
template that runs `cisco.ios`, `paloaltonetworks.panos` or
`arubanetworks.aoscx`, and the change is executed by automation that is version
controlled, logged, surveyed and RBAC-gated.

The AAP MCP server closes the loop: it exposes job query, fact gathering and
workflow launch as MCP tools, so the assistant can *invoke* the sanctioned write
path without ever holding device credentials itself.

This is the demo argument as much as the security one. "The AI can see
everything and change nothing except through Ansible" is a sentence a customer's
change-control board can accept.

---

## Decisions pending network review

These are the reason #94 exists. They turn on network-engineering judgement.

### Decision A — what do the PAN-OS and Aruba issues actually build?

No official server exists for either vendor. Five paths.

**A1 — pin a community device server, unmodified.** A specific server at a
specific commit SHA, containerized unchanged, support status documented honestly.
*For:* symmetric with Cisco, so one hosting pattern serves all three; live device
state in the assistant's context; preserves a clean per-vendor issue structure.
*Against:* requires a device (Decision B); hosts unvetted third-party Python that
talks to a firewall; adds API keys and OAuth tokens to the vault and to pods;
upstream may go stale — Aruba's own portal already disclaims its server.

**A2 — fork and vendor into this repo.** *For:* full control, auditable, no
upstream surprise. *Against:* this repo would own Python codebases when it is
otherwise Ansible and Terraform, and would inherit the CVE surface.

**A3 — substitute the official adjacent product.** Palo Alto → the official
Cortex MCP server. *For:* keeps "vendor-supplied" literally true for Palo Alto.
*Against:* changes the story from network configuration to SecOps, and does
nothing for Aruba, which has no official equivalent to substitute.

**A4 — collection knowledge instead of device access.** Expose
`paloaltonetworks.panos` and `arubanetworks.aoscx` module documentation, argument
specifications and validated content as MCP tools.
*For:* fixes the failure that actually costs time — hallucinated module names and
invented parameters; **needs no device**, so it is unblocked today; no
third-party code; the grounding corpus is the Private Automation Hub built in
#68/#69/#70, which is a differentiated Red Hat story rather than a generic one.
*Against:* **no vendor-supplied implementation exists for this either**, so it
means writing a server; it is one server covering every vendor, which collapses
the per-vendor issue structure; and it shows no live network state, so it is
weaker on stage than in daily use.

**A5 — both, sequenced.** The foundation carries A4 — one knowledge server, all
vendors, no device, ships now. Each vendor issue then adds its device server per
A1, gated on sourcing a target. Nothing blocks on hardware that does not exist,
and the four-issue structure survives.

> **The framing that matters: A1 and A4 are not alternatives.**
> A4 answers *"how do I write this playbook correctly?"*
> A1 answers *"what is the network currently doing?"*
> Developing a network use case needs both. Only A4 is on the critical path today.

### Decision B — where do the target devices come from?

**B1 — Cisco DevNet sandboxes.** A Meraki *always-on read-only* sandbox and a
24×7 hosted Catalyst Center sandbox (virtualized controller plus real hardware
topology) both exist, and their read-only nature matches the governance stance
exactly. *Verify before relying on it:* community reports indicate the Meraki
Dashboard, Catalyst Center, ISE and Catalyst SD-WAN sandboxes were temporarily
offline as of February 2026 — confirm current reachability at
`devnetsandbox.cisco.com`.

**B2 — RHDP catalog items.** Check whether RHDP offers PAN-OS or Aruba items to
reserve, the way `aap.dailydemo.Panos` already does for Palo Alto. Connection
details go in the environment's `connection.yml` plus two keys in the vault,
matching repo convention exactly. Ephemeral: details change every reservation.

**B3 — vendor trial or eval tenants.** Palo Alto VM-Series trial, Aruba Central
eval tenant. Requires investigating licence terms and whether API access is
included — trials frequently gate exactly the API the MCP server needs.

**B4 — simulated in-cluster.** Virtual appliances running on the same OpenShift
Virtualization cluster this repo already provisions against. Self-contained and
always available; expensive to build, and licence-constrained for VM-Series.

**B5 — defer.** Make "source and document a reachable target" task 1 of each
vendor issue, resolved by probing before designing — the way #93 resolved its
ServiceNow instance version from `/stats.do` before writing anything else.

### Decision C — hosting mechanism

The four-row table above. The SME's answer to Decision A and B may constrain it:
a device server holding firewall credentials raises the value of C2's
identity-aware routing, while a knowledge server needing no credentials makes C3's
reuse of existing repo machinery the cheaper path.

---

## What gets built once the decisions land

Four issues, sketched here and **deliberately not yet opened** — Decisions A and
B change what the Palo Alto and Aruba issues *are*, so opening them now would
guarantee rewriting them.

**Foundation.** Depends on #92. The Decision C mechanism; the stdio→streamable
HTTP + Route + auth pattern; the vault→Secret→pod credential path;
`playbooks/mcp_server.yml`; a `sales-demos-mcp-deploy` skill; registering the
endpoint in the laptop's Claude Code MCP configuration; and the read-only +
AAP-write-path governance statement. If A4 or A5 wins, the collection-knowledge
server lands here rather than in a vendor issue.

**Cisco.** Official Meraki and Catalyst Center servers plus DevNet Content
Search; targets per B1. **The only vendor fully unblocked today** — there is no
open Decision A for it — so it should prove the pattern first.

**Palo Alto.** Shape depends on Decision A; target per Decision B.

**Aruba.** Shape depends on Decision A, with the HPE non-support disclaimer
quoted rather than paraphrased; target per Decision B.

No epic. #92 already serves that role.

Every phase stays runnable as both a skill and an AAP job template, with the
playbook doing all the work and the skill reimplementing none of it — see
`CLAUDE.md` → *Skills and playbooks*. Note that `README.md` is not touched until
a skill directory actually exists: the `skills-frontmatter` CI job enforces the
skill-table ↔ directory mapping in **both** directions.

## Verification

1. `bash utilities/check-no-secrets.sh` — no device credentials, API keys or
   tokens in any tracked file. RHDP `*.dyn.redhatworkshops.io` hostnames remain
   the documented exception; DevNet sandbox hostnames are public and fine.
2. `yamllint .` and `ansible-lint` both clean.
3. `gh issue view 94` — the issue exists, carries `mcp` and `network`, and cites
   this document. `gh issue view 92` and `93` both carry `mcp`, so the whole body
   of MCP work is filterable as one query.
4. Every claim in the two findings tables resolves to its cited source, and every
   support-status statement is quoted verbatim rather than summarized. The Aruba
   disclaimer in particular must survive editing intact.
5. **The real acceptance test:** a network engineer who has never seen this repo
   can read *Decisions pending network review* and argue with it. If any option
   requires knowing what `connection.yml` or a job template survey is in order to
   evaluate it, that option is written wrong.

Nothing is deployed and no environment is touched by this document. Per
`CLAUDE.md`, nothing deploys from CI.

## Open items

- **Decisions A, B and C** — the reason #94 is open.
- Confirm DevNet sandbox availability before the Cisco issue commits to B1.
- Confirm `mcp-gateway` entitlement, not merely catalog presence.
- Whether the AAP MCP server write path gets proved on 2.6 now or waits for #92's
  2.7 adoption.
- Whether the SME conversation should also cover **F5 and Infoblox**, which appear
  in the DC1 roadmap and would inherit this identical foundation. Asking once is
  cheaper than asking twice.
- Whether a knowledge server (A4/A5), if chosen, should index from the Private
  Automation Hub built in #68/#69/#70 or from collection source directly. The
  former is the better story; the latter is the simpler build.
