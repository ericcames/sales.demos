# Roadmap

Near-term work for the OpenShift Virtualization demo. Full detail and rationale
in [`docs/plan/ocpvirt-demo-plan.md`](docs/plan/ocpvirt-demo-plan.md).

Each phase ships two entry points — a Claude Code skill and an AAP job template —
both driving the same playbook.

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
`available_memory_gb` (default 14), so an over-budget request is caught before
it schedules and sits Pending.

## Not scheduled

Whether this repo becomes home to the other daily-demo repos is deliberately
open. The layout admits them; nothing forces the decision.
