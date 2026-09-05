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
2. **~~~35 GB RAM is the real budget.~~ ~~Corrected in #2: ~14 GiB.~~ Corrected again in
   #118: ~75 GiB.** Each correction was honest when written, and the entries are kept
   rather than overwritten because the pattern is the point — this number has now been
   wrong twice, in both directions, and each time it read as settled fact.
   - **35 GB** was measured *before* CNV was installed.
   - **~14.2 GiB of 61.7 GiB** was measured after CNV, on the original cluster, and is
     why `large` is 6 GiB.
   - **75.63 GiB free of 124.68 GiB** was measured by `playbooks/probe_env.yml` on
     sandbox/`cluster-kbjvc` 2026-09-03 and cross-checked against `oc describe node`.
     The environment itself changed underneath the figure.

   The durable fix is not a better number, it is `sales-demos-probe-env`: read-only,
   safe mid-demo, and it prints what the cluster has rather than what a document
   remembers. See *Sizing design*.
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

> **Superseded — the model below changed in #18.** The original design put *every*
> environment-specific value in a gitignored plaintext `secrets.yml`, one per environment,
> so nothing appeared on GitHub. It now matches `aap_config`: **one vault-encrypted,
> committed `secrets.yml` in `group_vars/aap/`, holding credentials only.** The reasoning
> for the change is recorded below; the original argument is kept because the *shape* of the
> split — one obvious place to look, no `.example` twins, no second sourceable file — was
> right and survived.
>
> **Superseded again, twice more.** #5 moved the file from `group_vars/aap/` to
> `playbooks/group_vars/all/secrets.yml`, because the `aap` group scope did not
> cover plays targeting the demo VMs. #130 then **untracked** it: this repo is
> public, and shipping one person's encrypted credentials hands everyone else a
> blob they cannot decrypt or replace without diverging from upstream. So the
> path and the word "committed" below are both historical. The current model is
> `CLAUDE.md` -> *Secrets: exactly one mechanism*.

**Credentials go in `group_vars/aap/secrets.yml`, vault-encrypted and committed.** It sits in
the `aap` group directory so it loads for every environment: one file, both `sandbox` and
`demo`, with per-environment credentials keyed under `env_secrets` and selected by
`connection.yml` via `env_secrets[aap_env_name]`.

**Everything that is not a credential goes in `group_vars/<env>/connection.yml`,** committed
plaintext — `aap_hostname`, `openshift_api_url`, usernames, namespaces. So `connection.yml`
*does* vary per environment now; that is what makes the environment axis real rather than
decorative.

A new RHDP env means editing that env's `connection.yml` plus two keys in the vault. That is
two files rather than the original one — the cost of the change, taken knowingly, in exchange
for secrets that travel with the repo and survive a laptop loss.

Risk levels, stated plainly so the rule is applied with judgment rather than fear:

- **Tokens: absolute.** A live bearer token granting `kube:admin` is scraped by bots within
  minutes of a public push. Committed only as ciphertext, never in the clear. The CI guard
  enforces this: a tracked `secrets.yml` that does not begin with `$ANSIBLE_VAULT` fails the
  build. Since `secrets.yml` is no longer gitignored, that check is the only thing standing
  between a plaintext credential file and a public push.
- **URLs: not sensitive.** `dyn.redhatworkshops.io` is publicly resolvable, a hostname is not
  a credential, and the cluster expires in days. These are committed in the clear on purpose,
  matching `aap_config`. The original objection — that an env might one day be named after a
  customer — is handled by the standing rule against customer names, not by hiding hostnames.
- **The vault password is the one secret that cannot be vaulted.** It lives at
  `~/secrets/.vault_pass_sales_demos`, outside the repo, and must be backed up.

**Ciphertext in public history is permanent.** A later revert does not remove it, and the
protection is exactly the strength of the vault password. No rotation is planned: RHDP
environments are destroyed when testing finishes, and that destruction is the remediation.

**One secrets mechanism.** No `docs/dev-environment.sh` — that convention is retired here.
Do not introduce a second sourceable secrets file.

- `.gitignore` covers `*.tfstate*`, `*.tfvars`, `**/kubeconfig`, `.terraform/`, `.ansible/`,
  and vault password files. It deliberately does **not** cover `secrets.yml`.
- Audit the diff before every push; `utilities/check-no-secrets.sh` runs the same check in CI.

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
| `ocpvirt-windows-image` | `playbooks/link_windows_image.yml` | Phase 2 — point CNV at the published golden image |
| `ocpvirt-demo` | `playbooks/run_demo.yml` | Phase 4 — launch the layered daily demo |
| `ocpvirt-teardown` | `playbooks/teardown.yml` | `terraform destroy`, leave CNV and golden image intact |

Follow the existing `aap-skills` SKILL.md shape: frontmatter `name` + `description` with
explicit **TRIGGER** and **SKIP** clauses, then a Preflight Check section of shell one-liners
that verify each prerequisite before doing anything.

---

## Sizing design

Map t-shirt tiers to **cluster instance types + preferences**, not raw CPU/memory numbers.
This is native OpenShift Virt functionality and demos better than hand-rolled specs.

> **Revised in #2 after measuring the cluster.** The tiers are now repo-owned `sd1.*`
> instance types created by `terraform/ocpvirt/instancetypes.tf`, not Red Hat's shipped
> `u1.*`, and `large` is 6 GiB rather than 8. Red Hat's `u1.*` remain on the cluster
> untouched; reverting a tier to them is a one-line change in `locals.tf`.

| Tier | Instance type | vCPU / RAM | Root disk |
|---|---|---|---|
| `small-1cpu-2gb` | `sd1.small` | 1 / 2 GiB | 30 Gi |
| `medium-1cpu-4gb` | `sd1.medium` | 1 / 4 GiB | 30 Gi |
| `large-2cpu-6gb` | `sd1.large` | 2 / 6 GiB | 50 Gi |

**Why not `u1.large` at 8 GiB.** Post-CNV the node has ~14.2 GiB free, not the ~35 GiB the
pre-install probe showed, so `both` at 8 GiB needs ~16.6 GiB and never schedules. 7 GiB does
not fit either (~14.6). At 6 GiB, `both` + `large` is ~12.7 GiB — **measured, not estimated:
`terraform plan` reports `requested_memory_gb = 12.68`** — and every tier/OS combination fits.
There is no `u1` type at 6 GiB (the series is 2 / 4 / 8 / 16), which is why the tiers are
repo-owned rather than hand-rolling `spec.domain.memory.guest` and losing the instance-type
mechanism entirely.

The tier string says `large-2cpu-6gb` rather than `-8gb` deliberately: those strings are the
contract shared with the AAP survey and the skill, so they must not promise memory the tier
does not give.

A `terraform plan` precondition enforces the budget against `available_memory_gb` (default
67, measured by the probe — #118), so an over-budget request fails in the plan instead of
leaving a VM `Pending` with an `Insufficient memory` event while Terraform reports success.

Windows uses the same tiers with `preference: windows.2k22` and a 60 Gi disk minimum.

---

## Tonight's scope — repo creation only

> **Historical.** This section, and the implementation plan below, are the
> original day-one framing. Phases 0, 1 and 3 plus teardown are **built,
> merged, and verified against two live environments**; Phases 2 (#3) and 4 (#5)
> are not. `ROADMAP.md` carries current status — read that first and treat what
> follows as the reasoning behind the decisions, not a description of what
> exists.

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

6. **Pre-push audit** — the repo is public. Confirm no credential appears in the clear in any
   tracked file. *(Pattern updated in #18: RHDP hostnames are no longer flagged — they are
   committed in `connection.yml` on purpose.)*
   ```
   git ls-files -z | xargs -0 grep -nEi 'sha256~|BEGIN [A-Z ]*PRIVATE KEY|AKIA[0-9A-Z]{16}'
   ```
   Must return nothing except `secrets.yml.example` placeholder lines. Note the pattern is
   deliberately generic — do not hardcode a real value into the check itself.

Everything below is **tomorrow's work**, committed as the plan of record.

---

## Implementation plan (tomorrow)

> **Historical — see the note above.** Kept because the *rationale* in each
> phase is still the best record of why things are shaped the way they are.
> Where a decision was later reversed, it is marked at the point of reversal.

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

#### Phase 0: validated — step 2 and 3 are built and proven

Steps 2 and 3 are implemented in `playbooks/install_cnv.yml`, imported by
`playbooks/setup.yml` and wrapped by the `ocpvirt-setup` skill. **Step 1, the AAP bootstrap,
is still open** — see [#1](https://github.com/ericcames/sales.demos/issues/1).

The research above stands: `kubevirt-hyperconverged` is present in the operator catalog and
nested virt is real. What that research did *not* say, and what is worth saying outright:

> **A freshly provisioned environment has no `kubevirt.io` API group at all.** CNV is
> *available* in the catalog, not *installed*. Nothing can create a VM on a new provision
> until Phase 0 runs. Do not assume otherwise when a fresh env lands.

Observed on the validated run:

| Observation | Value |
|---|---|
| API groups | 86 before the install → **102** after |
| Operator | `kubevirt-hyperconverged-operator.v4.20.21`, channel `stable` |
| StorageClass chosen | `ocs-external-storagecluster-ceph-rbd` — the cluster default, discovered at run time |
| `devices.kubevirt.io/kvm` on node | absent before → **`1k`** after |
| Operator `Succeeded` | ~80s |
| `HyperConverged` `Available` | ~2.5 min |
| Re-run of the whole play | `changed=0` — idempotent in practice, not just by design |

The sizing tiers are confirmed against the real `u1` cluster instance types, with the exact
shapes the [sizing design](#sizing-design) assumes: `u1.small` 1 vCPU/2Gi, `u1.medium`
1 vCPU/4Gi, `u1.large` 2 vCPU/8Gi. The `ocpvirt-setup` skill re-checks these shapes after
every run — if they ever drift, Phase 1 sizing is wrong and this table is what needs fixing.

One design change against the plan above: the storage default is **discovered** (the
StorageClass annotated `storageclass.kubernetes.io/is-default-class`) rather than hard-coded
to `ocs-external-storagecluster-ceph-rbd`, with `cnv_storage_class` as an override. Hard-coding
would have tied Phase 0 to one catalog item. `volumeMode: Block` is left to CDI's StorageProfile
auto-detection, which already resolves to Block for Ceph RBD.

**OpenShift version and cluster ID vary per provisioned environment** — the `4.20.28` in the
research table and the `4.20.32` this was validated on are both just what one env happened to
ship. Treat them as samples, not as properties of the catalog item.

##### What this cost, and the lesson worth keeping

Two defects shipped through a fully green CI gate — yamllint, ansible-lint, secret hygiene,
and skill portability all passed while the playbook could not run at all:

1. Ansible's interpreter discovery selected a stale `/usr/bin/python3.13` that lacked the
   `kubernetes` client. Fixed by pinning `ansible_python_interpreter` to
   `{{ ansible_playbook_python }}` in `inventory/hosts.yml` — not in an `ansible.cfg`, which
   would shadow `~/.ansible.cfg` and break certified collection installs.
2. The default-StorageClass lookup used `selectattr` with a bracket-indexed annotation key.
   Jinja's dotted attribute syntax cannot address `storageclass.kubernetes.io/is-default-class`,
   so it failed at run time. Rewritten as a `loop` with a `when`.

**The CI gate validates syntax and hygiene. It cannot validate that a playbook works.** Every
phase must be run against `sandbox` and then verified against the cluster before its PR
merges. That is why the `ocpvirt-setup` skill ends in a cluster-side check rather than
trusting the Ansible recap.

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

Backend: **the `kubernetes` backend** — superseding this plan's original "local
state initially; optionally the NooBaa S3 endpoint later", which #4 found to be
unworkable. Local state is fine on a laptop and fatal from AAP: an execution
environment pod is ephemeral, so state vanishes with the job and teardown has
nothing to destroy from.

State lives in a Secret in a long-lived namespace of its own
(`sales-demos-tfstate`), deliberately **not** the VM namespace — `oc delete
project sales-demos-<env>` is the obvious way to clean up a demo and must not
take the state with it. `secret_suffix` keys `sandbox` and `demo` apart. See
`terraform/ocpvirt/backend.tf`.

### Phase 2 — `ocpvirt-windows-image`: point CNV at a published golden image

**Split producer/consumer.** This phase is the *consumer* half only —
`playbooks/link_windows_image.yml`, issue #3. Building and publishing the
containerdisk is [`image.builder.pipeline#24`](https://github.com/ericcames/image.builder.pipeline/issues/24) — **it lives in the image
factory repo, not here.** The contract between the halves is one string: a
containerdisk tag in a private quay repository.

The home was deliberately deferred when #3 shipped, on the grounds that a
one-string contract keeps the producer swappable at zero cost, and then resolved
in favour of the factory: that repo's `CLAUDE.md` already states
*"producer/consumer across repos is intentional — different audiences, different
lifecycles"*, its ROADMAP already claimed Windows Server 2022 / CIS L1 as Phase 3,
and choosing a CIS-hardened image pulled that way regardless, because hardening
plus compliance evidence is that repo's purpose and not this one's.

Splitting it means this half ships without waiting on a factory decision, and it
can be proven with a throwaway plain image before the real hardened one exists.

#### Superseded: "snapshot to a DataSource", replaced by a DataImportCron

This section used to say: CDI-import a Windows ISO, boot it, sysprep, then
*"snapshot the disk to a `DataSource` named `windows2k22-golden`"*. **That is not
how boot sources are kept on a cluster, and the cluster is the proof.**

Measured on sandbox, CNV 4.20.24: `HyperConverged.status.dataImportCronTemplates`
carries six entries — fedora, centos-stream 9/10, rhel 8/9/10 — each with
`managedDataSource`, `garbageCollect: Outdated` and a registry source. Windows is
absent only because Red Hat cannot redistribute the media, not because the
mechanism differs. A hand-created PVC is a one-shot artifact with no refresh
path; a cron makes a fresh RHDP environment a *config* step instead of a
data-movement one.

**Taking over the SSP placeholder is the designed handoff, not a fight.**

| | `win2k22` (placeholder) | `rhel9` (managed) |
|---|---|---|
| `managed-by` | `ssp-operator` | `cdi-controller` |
| `dataImportCron` label | absent | `rhel9-image-cron` |
| `spec.source` | `pvc {name: win2k22}` | `snapshot {name: rhel9-…}` |
| `generation` | 2 | 7 |
| Ready | `False` — "PVC not found" | `True` |

SSP creates the placeholder; the cron takes ownership, relabels it, and rewrites
`spec.source` from `pvc` to `snapshot`. The six built-in templates are not at
risk: `spec.dataImportCronTemplates` is *empty* on a stock cluster — they live in
HCO itself and appear only in `status`, flagged `commonTemplate: true`.

**Fallback if HCO ever refuses the takeover:** set `win_managed_datasource` to a
name SSP does not own and repoint `windows_datasource_name` in
`terraform/ocpvirt/variables.tf` to match. One line each.

#### What the consumer half does

1. Create a `kubernetes.io/dockerconfigjson` pull secret for the **private** quay
   repository. Private is not optional — a Windows image cannot be redistributed
   publicly.
2. Patch `HyperConverged.spec.dataImportCronTemplates` with a `win2k22-image-cron`
   entry sourcing `docker://{{ quay_windows_image }}` via `secretRef`, at 60Gi to
   match `windows_min_disk_gb`. No `pullMethod`: the default (`pod`) is the one
   that honours `secretRef`; `node` ignores it and needs cluster-wide credentials.
3. Wait for the DataSource to report Ready, then verify the **backing volume** —
   expect a `VolumeSnapshot`, not a PVC. A DataSource reports Ready while the
   snapshot behind it is still materializing, which is the slow-clone case
   `prepare_env.yml` exists to catch.
4. Reverse with `-e windows_image_link_state=absent`.

#### Durable storage: private quay.io containerdisk

Unchanged, and still the right call. The image must outlive the cluster — RHDP
environments expire, and rebuilding from ISO every time defeats the purpose.

- **Not the GitHub repo.** A sysprepped Windows Server 2022 qcow2 is ~8–12 GB;
  GitHub's file limit is 100 MB and Git LFS caps at 2 GB per file. Beyond size,
  `sales.demos` is public and a Windows image cannot be redistributed publicly —
  that rules it out regardless of backend.
- **Why quay works.** Containerdisk is KubeVirt's native format, consumed
  directly by CDI `source.registry`. The cluster already pulls from quay.io.
  Survives teardown, free on a personal account.
- **Private is required**, for the same redistribution reason.
- **Not in-cluster NooBaa S3** — it dies with the cluster, which is the whole
  problem.

Tag by date, never overwrite a tag. Quay credentials go in `secrets.yml`. Note
that with an immutable date tag the cron's poll is a no-op by design; pointing
`quay_windows_image` at a moving tag is what makes it refresh anything.

#### The producer half (ericcames/image.builder.pipeline#24), in one paragraph

Unattended install from an answer file — nobody clicks through an installer in a
real image factory. Apply `ansible-lockdown/Windows-2022-CIS` (MIT) with patch
tags, install virtio drivers and the QEMU guest agent, configure **WinRM over
HTTPS on 5986** (the contract this repo settles on; the Service published 5985
until #3, a mismatch nothing had exercised), re-run the role with audit tags to
capture evidence, `sysprep /generalize /oobe /shutdown`, wrap as a containerdisk
and push. Media is the 180-day evaluation ISO — **the expiry must be documented
in the tag, the run-sheet and the cron comment**, because a hardened image on
eval media is doubly a time bomb.

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
3. **Windows** — link the golden image, then apply `-var os_type=both -var
   vm_size_tier=large-2cpu-6gb`; confirm the Windows VMI reaches Running and WinRM
   answers on 5986. (This step said `large-2cpu-8gb`, a tier that has never existed.)
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

- ~~Quay.io namespace needs choosing~~ — **resolved: `quay.io/zigfreed`**, already
  publishing the execution environment (#31). Phase 2 still needs a **private**
  repository created under it for the Windows containerdisk, since Windows media
  cannot be redistributed publicly. Nothing else depends on it.
- Whether `sales.demos` becomes the home for the other ~12 demo repos is deliberately
  deferred. The layout admits them; nothing forces the decision now.
