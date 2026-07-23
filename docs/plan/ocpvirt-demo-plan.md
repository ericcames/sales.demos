# OpenShift Virtualization demos on the RHDP "Ansible Product Demo" catalog item

## Context

The question was whether the RHDP **Ansible Product Demo** catalog item can host OpenShift
Virtualization demos. I probed the live environment as `kube:admin` — read-only, plus one
throwaway debug pod to check for hardware virtualization.

**Answer: yes.** Nothing blocks it, and the one hard prerequisite is confirmed present.

### What the catalog item actually gives you

| Component | Finding |
|---|---|
| OpenShift | 4.20.28, **single-node** (control-plane + worker on one box) |
| Node | AMD EPYC 9554, 16 vCPU (15.5 allocatable), 64 GB RAM |
| Current load | 1.5 vCPU / 28.8 GB used → **~14 vCPU and ~35 GB free** |
| Nested virt | **`/dev/kvm` present, `svm` flag exposed** — `systemd-detect-virt` = kvm, nested virt enabled on the RHDP hypervisor |
| Platform | `None` (assisted-installer) |
| Storage | External ODF/Ceph 4.20.15 — RBD (default, block-capable) + CephFS RWX, **198 TB free** |
| AAP | 2.6.20260715 via `aap-operator.v2.6.0`, namespace `aap` — controller + EDA + gateway routes live |
| Operator catalog | `kubevirt-hyperconverged` **available**, stable → v4.20.21, candidate → v4.20.22. `kubernetes-nmstate-operator` and `mtv-operator` also present |
| Egress | Cluster pulls from `quay.io` and `registry.redhat.io` |

### Constraints that shape the design

1. **Single node ⇒ no live migration.** Drop it from the demo narrative. Everything else
   (VM lifecycle, snapshots, console, hotplug) works.
2. **~35 GB RAM is the real budget.** Sizing tiers must fit a full small+medium+large run
   with Windows in the mix.
3. **No Windows boot source.** CNV ships RHEL/Fedora DataSources; Red Hat cannot
   redistribute Windows. Build a golden image once, publish it, clone thereafter.
4. **AAP is co-resident on the only node.** A standard CNV install does *not* reboot the node
   (no MachineConfig — it deploys operators plus the `virt-handler` DaemonSet), so an AAP job
   template can safely perform the install. But because AAP runs in namespace `aap` on that
   same node, jobs driving cluster-level change should tolerate a brief API disconnect.
   Enabling hugepages or KSM later *would* reboot — keep those out of Phase 0.
5. **RHDP envs expire.** Every setup step must be a re-runnable playbook, not a manual runbook.

### Scope

Terraform CLI provisions Windows and Linux VMs on OpenShift Virt with small/medium/large
t-shirt sizing; the daily demo layers on top; AAP drives it. Every phase is runnable two
ways — as a Claude Code skill, and as an AAP job template.

---

## Repo: `sales.demos` (public), OCP Virt only for now

New public repo `sales.demos`, adopting the `aap_config` methodology. Structured so it *can*
hold more demos later, but **only `demos/ocpvirt/` gets populated now** — no migration of the
existing demo repos is in scope, and that decision stays open.

Not folded into `aap_config` itself: that repo is a *public teaching kit*, and its value is
being generic and clean. There is also a version gap — `aap_config` targets AAP 2.7; this
catalog item is **AAP 2.6.20260715 on the OpenShift operator**, so `sales.demos` pins to 2.6.

### Layout

```
sales.demos/
  .claude/skills/<name>/SKILL.md   # in-repo skills, no marketplace
  demos/ocpvirt/                   # job templates, surveys, demo content
  inventory/group_vars/
    aap/                           #   shared, demo-agnostic config
    sandbox/ demo/                 #   per-env connection + secrets
  terraform/ocpvirt/               # keyed by PLATFORM, not demo
  playbooks/                       # the work — one playbook per phase
  roles/
  requirements.yml                 # one pinned collection set
  .github/workflows/               # path-filtered per demo
```

A demo is selected by extra-var / CI matrix; an environment by inventory group.

### Why two environments, not three

`aap_config` has dev/qa/prod because it promotes config into real on-prem AAP — an actual
lifecycle with approval gates. Demo work has no such chain: you provision an RHDP env,
configure it, demo it, tear it down.

- **`sandbox`** — the env you're actively building against and breaking.
- **`demo`** — the env you show customers.

There is deliberately **no `golden` environment**. "This config is proven good" is a state of
the config, not a connection target — git already models it with `main` plus a release tag.

### Secrets convention

**`.example` files are for `secrets.yml` only.** Their single purpose is to show others what
that file must look like. No `connection.yml.example`, no proliferation of `.example` twins.

**Every environment-specific value goes in `secrets.yml`** — AAP hostname, OpenShift API URL,
tokens, quay credentials — not just the things that are strictly secret. Committed
`connection.yml` holds only structure and references vars defined in secrets.

The reason is operational, not security: **a new RHDP env means editing exactly one file.**
Re-point `secrets.yml` and everything follows; `connection.yml` never changes because nothing
in it varies per environment. Splitting env-specific values across two files would mean
remembering both every time a demo env is reprovisioned — which is the step you'd skip at the
end of a long day.

Keeping RHDP URLs out of a public repo falls out of this for free. Worth being clear-eyed
about the risk levels, so the rule is applied with judgment rather than fear:

- **Tokens: absolute.** A live bearer token granting `kube:admin` is scraped by bots within
  minutes of a public push. No exceptions.
- **URLs: low direct risk.** `dyn.redhatworkshops.io` is publicly resolvable, a hostname is
  not a credential, and the cluster expires in days. The real reasons to exclude it are that
  it is ephemeral (wrong within a week, so useless to a future cloner) and that it would
  become a genuine disclosure the moment an env is ever named after a customer or opportunity.

**`secrets.yml` is the only secrets mechanism in this repo.** No `docs/dev-environment.sh` —
that convention is retired here. One place to look, one file to gitignore, one example to
maintain. Do not introduce a second sourceable secrets file unless something genuinely cannot
go in `secrets.yml`.

- `.gitignore` covers `*.tfstate*`, `*.tfvars`, `inventory/group_vars/*/secrets.yml`,
  `**/kubeconfig`, `.terraform/`.
- The cluster URL and bearer token used to research this plan stay out of the repo entirely.
- Audit the diff for RHDP specifics before every push.

---

## Skills and playbooks: one contract, two entry points

Every phase is runnable as a Claude Code skill *and* as an AAP job template. The thing that
stops this from doubling the work is that **the skill never reimplements logic** — both
entry points drive the same playbook through the same variable contract.

| Layer | Path | Responsibility |
|---|---|---|
| Playbook | `playbooks/<phase>.yml` | **All** the work. Idempotent, no prompts, every input via `extra_vars`. Runs identically from a laptop or an AAP job. |
| Skill | `.claude/skills/<name>/SKILL.md` | Preflight checks, collect inputs conversationally, explain what's happening, invoke the playbook. Zero business logic. |
| Job template | `demos/ocpvirt/controller_job_templates.yml` | Same playbook, survey questions mapped to the same `extra_vars`. |

**The contract is the variable names.** A survey question, a skill prompt, and a playbook
`extra_var` are the same name or the design has drifted. Assert required vars at the top of
each playbook so both entry points fail the same way with the same message.

Skills live in `.claude/skills/` and are discovered natively when the repo is open — no
marketplace, no `plugin.json`. Tradeoff: project skills load only when you're working in
`sales.demos`, unlike the `aap-skills` plugin which works from anywhere. For skills that
support one repo, that is the correct scope. Leave `aap-skills` installed and untouched for
your other demos.

**Skills to build** (one per phase):

| Skill | Playbook | Does |
|---|---|---|
| `ocpvirt-setup` | `playbooks/setup.yml` | Phase 0 — bootstrap AAP *and* install CNV, self-contained |
| `ocpvirt-provision` | `playbooks/provision_vm.yml` | Phase 1/3 — run Terraform, register hosts in AAP |
| `ocpvirt-windows-image` | `playbooks/build_windows_golden.yml` | Phase 2 — build and publish the golden image |
| `ocpvirt-demo` | `playbooks/run_demo.yml` | Phase 4 — launch the layered daily demo |
| `ocpvirt-teardown` | `playbooks/teardown.yml` | `terraform destroy`, leave CNV and golden image intact |

Follow the existing `aap-skills` SKILL.md shape: frontmatter `name` + `description` with
explicit **TRIGGER** and **SKIP** clauses, then a Preflight Check section of shell one-liners
that verify each prerequisite before doing anything.

---

## Sizing design

Map t-shirt tiers to **CNV cluster instance types + preferences**, not raw CPU/memory
numbers. This is native OpenShift Virt functionality and demos better than hand-rolled specs.
`u1.*` instance types ship with CNV.

| Tier | Instance type | vCPU / RAM | Root disk |
|---|---|---|---|
| `small-1cpu-2gb` | `u1.small` | 1 / 2 GB | 30 GB |
| `medium-1cpu-4gb` | `u1.medium` | 1 / 4 GB | 30 GB |
| `large-2cpu-8gb` | `u1.large` | 2 / 8 GB | 50 GB |

Budget check: `both` OS at `large` = 16 GB, inside the ~35 GB free. All three tiers × both OS
= 28 GB — fits, but that is the ceiling; document it. Windows uses the same tiers with
`preference: windows.2k22` and a 60 GB disk minimum.

---

## Tonight's scope — repo creation only

**No code, no CNV install, no Terraform.** Tonight is only: create the repo and land the
planning in it. Execution starts tomorrow with a fresh Claude instance, which will read the
committed plan as its starting context.

1. **Create the repo** — `gh repo create ericcames/sales.demos --public` with a description.
   Init locally, `main` branch.

2. **`.gitignore` first, before anything else is committed** — `*.tfstate*`, `*.tfvars`,
   `inventory/group_vars/*/secrets.yml`, `**/kubeconfig`, `.terraform/`.

3. **Seed the skeleton** (directories with `.gitkeep`, no implementation):
   ```
   .claude/skills/  demos/ocpvirt/  terraform/ocpvirt/
   inventory/group_vars/{aap,sandbox,demo}/  playbooks/  roles/  docs/plan/
   ```
   Plus `inventory/group_vars/sandbox/secrets.yml.example` with placeholder values only.

4. **Commit the planning docs:**
   - `docs/plan/ocpvirt-demo-plan.md` — this plan.
   - `ROADMAP.md` — the five phases as the near-term roadmap.
   - `README.md` — what the repo is, the two-axis layout, the sandbox/demo env model, the
     skill+playbook contract, and a note that only `demos/ocpvirt/` is populated.
   - `CHANGELOG.md` — seeded per the standing convention.
   - `CLAUDE.md` — conventions for tomorrow's instance: AAP 2.6 pinning, `ansible.platform`
     over `ansible.controller`, token cleanup in `always:`, no project-local `ansible.cfg`,
     issue-before-code, the secrets-only-`.example` rule, public-repo data rules.
   - `LICENSE`, `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md` — copy the pattern from `aap_config`.

5. **Open labeled GitHub issues** — one per phase. Run
   `gh label list --repo ericcames/sales.demos` first and apply every label that fits.

6. **Pre-push audit** — the repo is public. Confirm no RHDP cluster ID, URL, or token appears
   in any tracked file:
   ```
   git ls-files -z | xargs -0 grep -nEi 'redhatworkshops|sha256~|[0-9]{1,3}(\.[0-9]{1,3}){3}|BEGIN [A-Z ]*PRIVATE KEY'
   ```
   Must return nothing except `secrets.yml.example` placeholder lines. Note the pattern is
   deliberately generic — do not hardcode a real cluster ID into the check itself.

Everything below is **tomorrow's work**, committed as the plan of record.

---

## Implementation plan (tomorrow)

### Phase 0 — `ocpvirt-setup`: bootstrap AAP and install CNV

Self-contained: takes a bare RHDP env to demo-ready in one flow.

1. **Bootstrap AAP** — Hub certified/validated credentials, vault credential, organization,
   project, base job templates. Derive from `aap.as.code`'s bootstrap path; `sales.demos`
   owns its own copy so the repo stands alone. *Known cost of self-containment: this
   duplicates logic `aap-skills`/`aap.as.code` already owns and can drift. Re-check it against
   the source whenever AAP versions move.*
2. **Install CNV** — namespace `openshift-cnv`, OperatorGroup, Subscription to
   `kubevirt-hyperconverged` channel `stable`, then the `HyperConverged` CR. Set the storage
   default to `ocs-external-storagecluster-ceph-rbd` with `volumeMode: Block`. Use
   `kubernetes.core.k8s`. Do not enable hugepages or KSM — those reboot the node.
3. **Wait for readiness** — poll `HyperConverged` conditions until Available, then confirm
   `DataSource rhel9` is ready in `openshift-virtualization-os-images`.

Any playbook creating an AAP token must delete it in an `always:` block.

### Phase 1 — Terraform module

Mirror `dc1.azure/terraform/` file-for-file; it already implements this exact t-shirt +
multi-OS pattern:

- `providers.tf` — replace `azurerm` with `hashicorp/kubernetes` (~> 2.30) + `random`. Use the
  **official `kubernetes` provider with `kubernetes_manifest`**, not a community KubeVirt
  provider — no third-party dependency, and the CRDs exist after Phase 0.
- `variables.tf` — port `vm_size_tier` and `os_type` (`windows` | `linux` | `both`) with their
  `validation` blocks verbatim from `dc1.azure/terraform/variables.tf:24-48`; swap the tier
  strings for the table above. Add `namespace`, `kubeconfig_path`.
- `locals.tf` — port the `vm_size_map` → `instancetype` mapping, `random_string.suffix`,
  `create_windows` / `create_linux` conditionals, and the naming/tag scheme.
- `main.tf` — `kubernetes_manifest` VirtualMachine resources with
  `count = local.create_* ? 1 : 0`. Linux clones `DataSource rhel9`; Windows clones the golden
  DataSource from Phase 2. cloud-init for Linux, sysprep/unattend for Windows.
- `outputs.tf` — port the `windows_inventory` / `linux_inventory` output shape from
  `dc1.azure/terraform/outputs.tf` unchanged. The daily-demo layer depends on that shape.

Backend: local state initially; optionally the NooBaa S3 endpoint later.

### Phase 2 — `ocpvirt-windows-image`: golden image (one time, ~45 min)

1. CDI-import a Windows Server 2022 ISO to a PVC (`DataVolume` with `source.blank` + ISO
   `cdrom` volume).
2. Boot a VM with the virtio-win containerdisk attached
   (`registry.redhat.io/container-native-virtualization/virtio-win`), install Windows, install
   virtio drivers and the QEMU guest agent, enable and configure WinRM for Ansible.
3. `sysprep /generalize /oobe /shutdown`.
4. Snapshot the disk to a `DataSource` named `windows2k22-golden`.
5. Publish it durably — below.

#### Durable storage: private quay.io containerdisk

The image must outlive the cluster — RHDP envs expire, and rebuilding from ISO every time
defeats the purpose. **Decision: a private `quay.io` repository, in containerdisk format.**

- **Not the GitHub repo.** A sysprepped Windows Server 2022 qcow2 is ~8–12 GB; GitHub's file
  limit is 100 MB and Git LFS caps at 2 GB per file. Beyond size, `sales.demos` is public and
  a Windows image cannot be redistributed publicly — that rules it out regardless of backend.
- **Why quay works.** Containerdisk is KubeVirt's native format, consumed directly by a
  `containerDisk` volume or CDI `source.registry`. The cluster already pulls from quay.io
  (verified). Survives teardown, free on a personal account.
- **Private is required**, for the same Windows redistribution reason.
- **Not in-cluster NooBaa S3** — it dies with the cluster, which is the whole problem.

```
podman build -t quay.io/<user>/windows2k22-golden:<date> -f - . <<'EOF'
FROM scratch
ADD --chown=107:107 windows2k22-golden.qcow2 /disk/
EOF
podman push quay.io/<user>/windows2k22-golden:<date>
```

Cluster side: create an image pull secret for the private quay repo and link it to the CDI
service account. On a fresh RHDP env, Phase 2 then collapses to a single CDI import from the
registry — minutes instead of ~45. Tag by date, never overwrite a tag. Quay credentials go in
`secrets.yml`.

### Phase 3 — `ocpvirt-provision`: AAP integration

Port `dc1.azure/playbooks/provision_vm.yml` — it already asserts inputs, runs `terraform init`
/ `apply -var vm_size_tier=... -var os_type=...`, then registers hosts into an AAP inventory
(`windemo` group with WinRM vars, `linuxweb` group with SSH vars). Changes:

- Swap the `arm_env` Azure block for an OpenShift `K8S_AUTH_*` / kubeconfig credential.
- Keep the `request_timeout` workaround documented at `provision_vm.yml:47-57` — it applies to
  AAP 2.6 the same way.
- Reuse `aap.dailydemo.openshift/roles/create-vm/tasks/main.yml` as the reference for the
  `kubevirt_vm` spec shape; it already parameterizes cpu/memory/storage and uses `sourceRef`
  DataSource cloning. Its two-NIC bridge setup needs nmstate — drop the second NIC for v1 and
  use pod networking only.
- Prefer `redhat.openshift_virtualization` and `ansible.platform` modules
  (`ansible.controller` is legacy).

Job templates and surveys: port `dc1.azure/aap_config/files/controller_job_templates.yml`
(`"DC1.Azure - Provision VM"` at line 11 with its `VM size tier` survey; the launcher template
at line 148 with its `Operating system` + `VM size tier` survey) into `demos/ocpvirt/`,
renamed for OCP Virt. Survey variable names must match the skill prompts and playbook
`extra_vars` exactly.

### Phase 4 — `ocpvirt-demo`: layer the daily demo

With hosts registered by Phase 3, existing daily-demo content (patching, compliance, webserver
setup) runs unchanged against VM-hosted RHEL and Windows — the inventory contract is the same
one `dc1.azure` already produces.

---

## Verification

1. **CNV health** — `oc get hyperconverged -n openshift-cnv` Available; `oc get pods -n openshift-cnv`
   all Running; `oc get datasource -n openshift-virtualization-os-images` shows rhel9 ready.
2. **Terraform** — `terraform init && terraform plan` clean, then apply each tier:
   `-var os_type=linux -var vm_size_tier=small-1cpu-2gb`, then `medium`, then `large`.
   Confirm `oc get vm,vmi -n <ns>` shows Running and the instance type matches the tier.
3. **Windows** — apply `-var os_type=both -var vm_size_tier=large-2cpu-8gb`; confirm the
   Windows VMI reaches Running and WinRM answers.
4. **Resource ceiling** — with all VMs up, `oc adm top node` must stay under ~90% memory.
   This is the test that proves the tier table fits the box.
5. **Both entry points agree** — run each phase once via its skill and once via its AAP job
   template, and confirm identical results. This is the test that the contract held.
6. **AAP end-to-end** — launch the provision job template from the controller UI with the
   survey, confirm hosts land in the inventory, then run one daily-demo job template.
7. **Teardown** — `terraform destroy` leaves the golden DataSource and CNV install intact.
8. **Repo hygiene** — the `git ls-files` grep from tonight's step 6 returns nothing. Run
   before every push.

---

## Open items

- Quay.io namespace for the golden image needs choosing and a private repo created before
  Phase 2 can complete. Nothing else depends on it.
- Whether `sales.demos` becomes the home for the other ~12 demo repos is deliberately
  deferred. The layout admits them; nothing forces the decision now.
