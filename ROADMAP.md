# Roadmap

Three use cases plus two platform capabilities. Full detail and rationale in the
six [Design Plans](https://ericcames.github.io/sales.demos-docs/plan/ocpvirt-demo-plan/)
— `ocpvirt-demo-plan`, `pah-plan`, `network-mcp-plan`, `platform-addons-plan`,
`automation-orchestrator-plan` and `grafana-plan`.

Each phase ships two entry points — a Claude Code skill and an AAP job template —
both driving the same playbook. `pah-sync` is the one documented exception; see
below.

**The tables no longer carry Skill and Playbook columns, deliberately**
([#652](https://github.com/ericcames/sales.demos/issues/652)). They used to, and
seven of the thirteen names were wrong — the `ocpvirt-*` → `sales-demos-*` rename
never reached here, and one name had never existed at all. An inventory of skills
belongs to [`.claude/skills/`](.claude/skills/) and the skills table in
[`README.md`](README.md), which change when the skills change; a copy here only
rots. A name still appears below where it is load-bearing to a point being made,
but nothing here tries to enumerate them.

What is left is the part with no other home: what each capability is for, what it
cost, and what is deliberately not being built.

## Platform add-ons — MCP servers

Both tooling and a demonstrable use case. Connects Claude Code straight to the
clusters so asking an environment a question costs a tool call rather than a
hand-rolled `curl` plus a vault read — and the governed read/write boundary is
itself a demo worth showing customers. Full detail in
[`platform-addons-plan`](https://ericcames.github.io/sales.demos-docs/plan/platform-addons-plan/);
demo documentation in
[MCP Servers demo](https://ericcames.github.io/sales.demos-docs/demos/mcp-servers/).

|  | Outcome | Status |
| --- | --- | --- |
| OpenShift MCP | Three committed servers: `openshift-sandbox` (full, 25 tools), `openshift-demo` (read-only, 16) and `openshift-edge` (full, 25) for the bare-metal SNO. Runs locally, so it survives environment churn and works before a cluster exists. | **Done** ([#102](https://github.com/ericcames/sales.demos/issues/102)) |
| AAP MCP | A typed `AnsibleMCPServer` CR, deployed by `setup.yml` so a new environment arrives with it on. 140 tools including job-template launch. Write posture is per-environment and never defaulted. | **Done** ([#102](https://github.com/ericcames/sales.demos/issues/102)) |
| ServiceNow MCP | **Not built, deliberately.** The native MCP Server Console needs Zurich Patch 9+ or Australia Patch 2+; the demo instance is Yokohama, measured 2026-09-02. The write path is `servicenow.itsm`, already pinned, and needs no MCP server at all. Community servers are read-write with no way to constrain them and are not recommended. Reasoning and the build-your-own path in [ServiceNow](https://ericcames.github.io/sales.demos-docs/demos/mcp-servers/servicenow/). | **Documented, blocked on an instance upgrade** |
| Cluster probe | Read-only capacity measurement, safe mid-demo. Found `available_memory_gb` five times too small and recommends a replacement. Both add-on operators confirmed present on OperatorHub. | **Done** ([#100](https://github.com/ericcames/sales.demos/issues/100)) |
| Automation Orchestrator — install | Runs on every build, default-on and skippable with `install_ao=false`. CloudNativePG supplies the three databases Temporal actually needs — the CRD asks for two and the third, `temporal_visibility`, is undocumented. Measured 1.91 vCPU / 2.47 GiB, which moved `available_memory_gb` 67 → 63. | **Done** ([#108](https://github.com/ericcames/sales.demos/issues/108), [#141](https://github.com/ericcames/sales.demos/issues/141)) |
| Automation Orchestrator — configure | AAP OIDC SSO and the AAP integration, plus the SSRF allowlist on every component that reaches AAP — the backend *and* the worker, which is where the first rehearsal died. | **Done** ([#457](https://github.com/ericcames/sales.demos/issues/457)) |
| Automation Orchestrator — workflow as code | The demo workflow declared in `ao_workflows.yml` and resolved to each environment's IDs on import, rather than exported as an opaque blob. A rebuilt environment gets its workflow back. | **Done** ([#474](https://github.com/ericcames/sales.demos/issues/474)) |
| Automation Orchestrator — rehearsal | Preflights every fault the first rehearsal hit, breaks compliance on the guest, and reports a finished run's per-step timings and approval record. Rehearsed end to end 2026-09-15: 2 m 48 s, about 76 s of it automation. | **Done** ([#623](https://github.com/ericcames/sales.demos/issues/623)) |
| Self-service portal | Red Hat Developer Hub with the AAP plugin, so a non-admin can launch a template from a browser. The AAP plugin has no workflow provider, so workflows need a launcher job template. | **Done** ([#103](https://github.com/ericcames/sales.demos/issues/103)) |

## Grafana Cloud observability

Push cluster metrics and logs to Grafana Cloud so the AI agent can answer
infrastructure questions through the Grafana MCP server. Full detail in
[`grafana-plan`](https://ericcames.github.io/sales.demos-docs/plan/grafana-plan/).

|  | Outcome | Status |
| --- | --- | --- |
| Deploy Alloy | DaemonSet in `grafana-alloy` namespace. Prometheus federation from `prometheus-k8s`, AAP controller scrape via the gateway (`/api/controller/v2/metrics/`), and Kubernetes API log streaming for four namespaces. ~2,098 series of the 10k free-tier budget. Reversible with `-e alloy_state=absent`. | **Done on `sandbox`** ([#265](https://github.com/ericcames/sales.demos/issues/265)) |
| Dashboard as code | Cluster-health dashboard deployed from the repo rather than clicked together, so the panel set is reviewable in a PR. | **Done on `sandbox`**, shipped 2026-09-15 ([#275](https://github.com/ericcames/sales.demos/issues/275)) |
| Alert rules as code | Alert rules deployed the same way, behind `AAP Observability - 3 Deploy Alerts`. | **Done on `sandbox`**, shipped 2026-09-15 ([#629](https://github.com/ericcames/sales.demos/issues/629)) |

## Use case 3 — Network MCP servers

AI-assisted development of Cisco, Palo Alto and Aruba use cases. Nothing is built
yet: three decisions are held open for network SME review, and the implementation
issues are deliberately unopened until they land — Decisions A and B change what
the Palo Alto and Aruba issues *are*. See
[`network-mcp-plan`](https://ericcames.github.io/sales.demos-docs/plan/network-mcp-plan/).

|  | Outcome | Status |
| --- | --- | --- |
| Research and decide | The vendor MCP landscape, the Red Hat hosting layer, and Decisions A (what PAN-OS and Aruba build), B (where the devices come from) and C (hosting mechanism). Vendor-supplied servers exist for Cisco only. | **In progress** ([#94](https://github.com/ericcames/sales.demos/issues/94)) |
| Foundation | Every server found is stdio-only with no container image, so the pattern is containerize → stdio to streamable HTTP → Route → auth → credentials from the vault. Depends on [#92](https://github.com/ericcames/sales.demos/issues/92). | Not started — blocked on Decision C |
| Cisco | **The only unblocked vendor.** DevNet Content Search (no target needed), then Catalyst Center — the one pairing of an official MCP server with an always-on sandbox, confirmed live 2026-09-02 — then Meraki, whose sandbox is reservable. Seven always-on sandboxes exist in total, including IOS XE, IOS XR and NSO. | Not started — ready to start |
| Palo Alto | No official PAN-OS server exists — the official Cortex MCP serves SecOps data. Shape depends on Decision A. | Not started — blocked on Decision A |
| Aruba | Nothing official exists; the portal-documented server is disclaimed by HPE. Shape depends on Decision A. | Not started — blocked on Decision A |

## Use case 2 — Private Automation Hub as code

|  | Outcome | Status |
| --- | --- | --- |
| Populate PAH | Certified (214) and validated (47) windowed to 3 versions each, plus 15 curated community collections at their current version. Configured on every build by `config.yml`. | **Draft** ([#68](https://github.com/ericcames/sales.demos/issues/68)) |
| Curate a repository | A fourth repository, `approved`, with no remote. Contents declared in `hub/approved-collections.yml` and reconciled — it adds **and removes**, which a sync cannot. The one to point consumers at. | **Done** ([#70](https://github.com/ericcames/sales.demos/issues/70)) |
| Point AAP at PAH | An organization Galaxy credential aimed at `approved`, so project syncs resolve from the hub with no internet egress. The token is minted at run time from credentials the environment already holds, never stored. Reversible in one flag. | **Done on `sandbox`** ([#69](https://github.com/ericcames/sales.demos/issues/69)) |

**`pah-sync` has no job template, on purpose.** The Red Hat offline token lives
in `~/.ansible.cfg` and an execution environment has no such file. A vaulted
fallback was built, verified, and removed — it bought one job template at the
cost of a second copy of a rotating credential.

## Use case 1 — OpenShift Virtualization

| Phase | Outcome | Status |
| --- | --- | --- |
| 0 | Bare RHDP env → CNV installed, AAP configured, and a real VM built and timed to prove it. One command. | **Done** ([#1](https://github.com/ericcames/sales.demos/issues/1)) |
| 0.5 | Prove an environment is demo-ready — boot source, clone strategy, ingress — in about a minute. | **Done** ([#30](https://github.com/ericcames/sales.demos/issues/30)) |
| 1 | Terraform module: Windows + Linux VMs, t-shirt sized, state on the kubernetes backend. | **Done** ([#2](https://github.com/ericcames/sales.demos/issues/2)) |
| 2 | Point CNV at a published Windows containerdisk via a `DataImportCron`, so `os_type=windows` boots. Split producer/consumer: building the CIS-hardened image is [image.builder.pipeline#24](https://github.com/ericcames/image.builder.pipeline/issues/24). | **Done** ([#3](https://github.com/ericcames/sales.demos/issues/3)) |
| 2R | The same for RHEL 9: the `rhel9-cis-l1` DataSource alongside stock `rhel9`, so Terraform clones the hardened image by default. No pull secret — that quay repo is public. | **Done** ([#202](https://github.com/ericcames/sales.demos/issues/202)) |
| 3 | Terraform run from AAP; new VMs registered as managed hosts. | **Done** ([#4](https://github.com/ericcames/sales.demos/issues/4)) |
| 4 | Re-run the daily-demo content on Linux VMs that already exist. | **Done** ([#5](https://github.com/ericcames/sales.demos/issues/5)) |
| 4W | The same for Windows: patch, IIS and the demo page, CIS L1 verification. Completes the eight-object `Windows Day 1` family — workflow, five numbered steps, Repair, Teardown. | **Done** ([#340](https://github.com/ericcames/sales.demos/issues/340)) |
| 5 | Day 2 begins. Fact gathering folded into step 5 of both Day 1 chains and offered off-chain as `Linux Day 2 - Gather Facts` / `Windows Day 2 - Gather Facts`. The full set is in AAP's database (`use_fact_cache` has been on since [#47](https://github.com/ericcames/sales.demos/issues/47) and nothing said so), a curated summary prints in the job log, and the same summary is published at `<web_url>/facts.html`. | **Done**, merged 2026-09-16 ([#647](https://github.com/ericcames/sales.demos/issues/647)) |
| 5b | Drift: the gather reads the host's *previously* cached facts back out of AAP and reports what changed. AAP writes the cache after a job finishes, so a job reading it mid-run gets the previous run's set — that is what makes the diff real. Adds the `Sales Demos - Controller` credential. `uptime.last_boot` is rounded to the minute and `network.domain` is excluded, both because they moved on an idle guest. | **Done**, merged 2026-09-16 ([#648](https://github.com/ericcames/sales.demos/issues/648)) |
| — | `terraform destroy`; CNV, the boot-source DataSources and the state namespace survive. Scheduled nightly. | **Done** ([#6](https://github.com/ericcames/sales.demos/issues/6)) |

Supporting work, not a phase:

| | Detail | Status |
|---|---|---|
| Execution environment with terraform | `execution-environment.yml`, `/sales-demos-ee-build` | **Done** ([#31](https://github.com/ericcames/sales.demos/issues/31)) |
| EE pulled from Private Automation Hub | `hub_ee_*.yml` | **Done** ([#35](https://github.com/ericcames/sales.demos/issues/35)) |

**All three environments are live.** `sandbox` and `demo` are separate RHDP
clusters; `edge` is a persistent bare-metal SNO on a NUC, not an RHDP
environment. `--limit` selects between them.

## Sizing tiers

Mapped to cluster instance types rather than hand-rolled CPU/memory — but to
**repo-owned `sd1.*` types**, not Red Hat's shipped `u1.*` series (#2). Sizes are
declared once in `terraform/ocpvirt/tiers.yaml`, read by both Terraform and
`playbooks/tasks/ensure_shared_objects.yml`, which creates the objects — Ansible
rather than Terraform since #348, so they outlive a per-OS teardown. Updated for
doubled RHDP hardware (#239).

| Tier | Instance type | vCPU / RAM | Root disk | Azure equivalent |
|---|---|---|---|---|
| `small` | `sd1.small` | 2 / 4 GiB | 30 GB | Standard_B2s |
| `medium` | `sd1.medium` | 2 / 8 GiB | 30 GB | Standard_B2ms |
| `large` | `sd1.large` | 4 / 16 GiB | 50 GB | Standard_B4ms |

Legacy names (`small-1cpu-2gb`, `medium-1cpu-4gb`, `large-2cpu-6gb`) are
accepted as aliases and resolve to the current specs.

The real ceiling is enforced in code, not by this table:
`terraform/ocpvirt/locals.tf` fails `plan` when a run exceeds
`available_memory_gb` (measured — #118), so an over-budget request is caught
before it schedules and sits Pending. The RHDP environments (`sandbox` and
`demo`) currently use 63 GiB; the persistent `edge` environment uses a 50 GiB
budget because the NUC has ~64 GiB RAM.
