# Roadmap

Near-term work for the OpenShift Virtualization demo. Full detail and rationale
in [`docs/plan/ocpvirt-demo-plan.md`](docs/plan/ocpvirt-demo-plan.md).

Each phase ships two entry points — a Claude Code skill and an AAP job template —
both driving the same playbook.

| Phase | Skill | Playbook | Outcome |
|---|---|---|---|
| 0 | `ocpvirt-setup` | `playbooks/setup.yml` | Bare RHDP env → AAP bootstrapped and OpenShift Virtualization installed. Self-contained. |
| 1 | — | `terraform/ocpvirt/` | Terraform module: Windows + Linux VMs, t-shirt sized. |
| 2 | `ocpvirt-windows-image` | `playbooks/build_windows_golden.yml` | Windows Server 2022 golden image, published to a private quay.io containerdisk so it outlives the cluster. |
| 3 | `ocpvirt-provision` | `playbooks/provision_vm.yml` | Terraform run from AAP; new VMs registered as managed hosts. |
| 4 | `ocpvirt-demo` | `playbooks/run_demo.yml` | Existing daily-demo content layered on the provisioned VMs. |
| — | `ocpvirt-teardown` | `playbooks/teardown.yml` | `terraform destroy`; CNV and golden image survive. |

## Sizing tiers

Mapped to native CNV cluster instance types rather than hand-rolled CPU/memory.

| Tier | Instance type | vCPU / RAM | Root disk |
|---|---|---|---|
| `small-1cpu-2gb` | `u1.small` | 1 / 2 GB | 30 GB |
| `medium-1cpu-4gb` | `u1.medium` | 1 / 4 GB | 30 GB |
| `large-2cpu-8gb` | `u1.large` | 2 / 8 GB | 50 GB |

The target is a single-node cluster with roughly 35 GB free. All three tiers ×
both operating systems is about 28 GB — that is the ceiling.

## Not scheduled

Whether this repo becomes home to the other daily-demo repos is deliberately
open. The layout admits them; nothing forces the decision.
