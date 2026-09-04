# Roadmap

Three use cases. Full detail and rationale in
[`docs/plan/ocpvirt-demo-plan.md`](docs/plan/ocpvirt-demo-plan.md),
[`docs/plan/pah-plan.md`](docs/plan/pah-plan.md) and
[`docs/plan/network-mcp-plan.md`](docs/plan/network-mcp-plan.md).

Each phase ships two entry points — a Claude Code skill and an AAP job template —
both driving the same playbook. `pah-sync` is the one documented exception; see
below.

## Platform add-ons — MCP servers

Both tooling and a demonstrable use case. Connects Claude Code straight to the
clusters so asking an environment a question costs a tool call rather than a
hand-rolled `curl` plus a vault read — and the governed read/write boundary is
itself a demo worth showing customers. Full detail in
[`docs/plan/platform-addons-plan.md`](docs/plan/platform-addons-plan.md);
demo documentation in
[`docs/demos/mcp-servers/`](docs/demos/mcp-servers/).

| | Skill | Playbook | Outcome | Status |
|---|---|---|---|---|
| OpenShift MCP | `sales-demos-mcp` | — (laptop-only, by design) | Two committed servers, `openshift-sandbox` (full, 25 tools) and `openshift-demo` (read-only, 16). Runs locally, so it survives environment churn and works before a cluster exists. | **Done** ([#102](https://github.com/ericcames/sales.demos/issues/102)) |
| AAP MCP | `sales-demos-mcp` | `playbooks/mcp_server.yml` | A typed `AnsibleMCPServer` CR, deployed by `setup.yml` so a new environment arrives with it on. 140 tools including job-template launch. Write posture is per-environment and never defaulted. | **Done** ([#102](https://github.com/ericcames/sales.demos/issues/102)) |
| Cluster probe | `sales-demos-probe-env` | `playbooks/probe_env.yml` | Read-only capacity measurement, safe mid-demo. Found `available_memory_gb` five times too small and recommends a replacement. Both add-on operators confirmed present on OperatorHub. | **Done** ([#100](https://github.com/ericcames/sales.demos/issues/100)) |
| Automation Orchestrator | `sales-demos-orchestrator` | `playbooks/install_ao.yml` | Runs on every build, default-on and skippable with `install_ao=false`. CloudNativePG supplies the three databases Temporal actually needs — the CRD asks for two and the third, `temporal_visibility`, is undocumented. Measured 1.91 vCPU / 2.47 GiB, which moved `available_memory_gb` 67 → 63. | **Done** ([#108](https://github.com/ericcames/sales.demos/issues/108), [#141](https://github.com/ericcames/sales.demos/issues/141)) |

## Use case 3 — Network MCP servers

AI-assisted development of Cisco, Palo Alto and Aruba use cases. Nothing is built
yet: three decisions are held open for network SME review, and the implementation
issues are deliberately unopened until they land — Decisions A and B change what
the Palo Alto and Aruba issues *are*. See
[`docs/plan/network-mcp-plan.md`](docs/plan/network-mcp-plan.md).

| | Skill | Playbook | Outcome | Status |
|---|---|---|---|---|
| Research and decide | — | — | The vendor MCP landscape, the Red Hat hosting layer, and Decisions A (what PAN-OS and Aruba build), B (where the devices come from) and C (hosting mechanism). Vendor-supplied servers exist for Cisco only. | **In progress** ([#94](https://github.com/ericcames/sales.demos/issues/94)) |
| Foundation | `sales-demos-mcp-deploy` | `playbooks/mcp_server.yml` | Every server found is stdio-only with no container image, so the pattern is containerize → stdio to streamable HTTP → Route → auth → credentials from the vault. Depends on [#92](https://github.com/ericcames/sales.demos/issues/92). | Not started — blocked on Decision C |
| Cisco | — | — | **The only unblocked vendor.** DevNet Content Search (no target needed), then Catalyst Center — the one pairing of an official MCP server with an always-on sandbox, confirmed live 2026-09-02 — then Meraki, whose sandbox is reservable. Seven always-on sandboxes exist in total, including IOS XE, IOS XR and NSO. | Not started — ready to start |
| Palo Alto | — | — | No official PAN-OS server exists — the official Cortex MCP serves SecOps data. Shape depends on Decision A. | Not started — blocked on Decision A |
| Aruba | — | — | Nothing official exists; the portal-documented server is disclaimed by HPE. Shape depends on Decision A. | Not started — blocked on Decision A |

## Use case 2 — Private Automation Hub as code

| | Skill | Playbook | Outcome | Status |
|---|---|---|---|---|
| Populate PAH | `pah-sync` | `playbooks/sync_hub.yml` | Certified (214) and validated (47) windowed to 3 versions each, plus 15 curated community collections at their current version. Configured on every build by `config.yml`. | **Draft** ([#68](https://github.com/ericcames/sales.demos/issues/68)) |
| Curate a repository | `pah-sync` | `playbooks/curate_hub.yml` | A fourth repository, `approved`, with no remote. Contents declared in `hub/approved-collections.yml` and reconciled — it adds **and removes**, which a sync cannot. The one to point consumers at. | **Done** ([#70](https://github.com/ericcames/sales.demos/issues/70)) |
| Point AAP at PAH | — | — | Organization Galaxy credentials, so project syncs resolve from the hub. Deliberately deferred behind gates — gate 2 already fails. | Not started ([#69](https://github.com/ericcames/sales.demos/issues/69)) |

**`pah-sync` has no job template, on purpose.** The Red Hat offline token lives
in `~/.ansible.cfg` and an execution environment has no such file. A vaulted
fallback was built, verified, and removed — it bought one job template at the
cost of a second copy of a rotating credential.

## Use case 1 — OpenShift Virtualization

| Phase | Skill | Playbook | Outcome | Status |
|---|---|---|---|---|
| 0 | `ocpvirt-setup` | `playbooks/setup.yml` | Bare RHDP env → CNV installed, AAP configured, and a real VM built and timed to prove it. One command. | **Done** ([#1](https://github.com/ericcames/sales.demos/issues/1)) |
| 0.5 | `ocpvirt-new-env` | `playbooks/prepare_env.yml` | Prove an environment is demo-ready — boot source, clone strategy, ingress — in about a minute. | **Done** ([#30](https://github.com/ericcames/sales.demos/issues/30)) |
| 1 | — | `terraform/ocpvirt/` | Terraform module: Windows + Linux VMs, t-shirt sized, state on the kubernetes backend. | **Done** ([#2](https://github.com/ericcames/sales.demos/issues/2)) |
| 2 | `ocpvirt-windows-image` | `playbooks/build_windows_golden.yml` | Windows Server 2022 golden image, published to a private quay.io containerdisk so it outlives the cluster. | Not started ([#3](https://github.com/ericcames/sales.demos/issues/3)) |
| 3 | `ocpvirt-provision` | `playbooks/provision_vm.yml` | Terraform run from AAP; new VMs registered as managed hosts. | **Done** ([#4](https://github.com/ericcames/sales.demos/issues/4)) |
| 4 | `ocpvirt-demo` | `playbooks/run_demo.yml` | Existing daily-demo content layered on the provisioned VMs. | Not started ([#5](https://github.com/ericcames/sales.demos/issues/5)) |
| — | `ocpvirt-teardown` | `playbooks/teardown.yml` | `terraform destroy`; CNV, the boot-source DataSources and the state namespace survive. Scheduled nightly. | **Done** ([#6](https://github.com/ericcames/sales.demos/issues/6)) |

Supporting work, not a phase:

| | | Status |
|---|---|---|
| Execution environment with terraform | `execution-environment.yml`, `/sales-demos-ee-build` | **Done** ([#31](https://github.com/ericcames/sales.demos/issues/31)) |
| EE pulled from Private Automation Hub | `hub_ee_*.yml` | **Done** ([#35](https://github.com/ericcames/sales.demos/issues/35)) |

**Both environments are live.** `sandbox` and `demo` are separate RHDP clusters;
`--limit` selects between them.

## Sizing tiers

Mapped to cluster instance types rather than hand-rolled CPU/memory — but to
**repo-owned `sd1.*` types**, not Red Hat's shipped `u1.*` series (#2,
`terraform/ocpvirt/instancetypes.tf`).

| Tier | Instance type | vCPU / RAM | Root disk |
|---|---|---|---|
| `small-1cpu-2gb` | `sd1.small` | 1 / 2 GiB | 30 GB |
| `medium-1cpu-4gb` | `sd1.medium` | 1 / 4 GiB | 30 GB |
| `large-2cpu-6gb` | `sd1.large` | 2 / 6 GiB | 50 GB |

**Why not `u1.*`.** That series has no 6 GiB size — it goes 2 / 4 / 8 / 16. At
`u1.large`'s 8 GiB, `os_type=both` needs about 16.6 GiB against the ~14.2 GiB
this node actually has free once AAP and CNV are running, so it would never
schedule. The `sd1.*` types keep every tier/OS combination inside that budget
while preserving the mechanism: sizing still comes from a cluster instance type.
The `u1.*` types are left untouched.

The real ceiling is enforced in code, not by this table:
`terraform/ocpvirt/locals.tf` fails `plan` when a run exceeds
`available_memory_gb` (default 67, measured — #118), so an over-budget request is caught before
it schedules and sits Pending.

## Not scheduled

Whether this repo becomes home to the other daily-demo repos is deliberately
open. The layout admits them; nothing forces the decision.
