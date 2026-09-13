---
name: sales-demos-teardown
description: "Destroy the demo VMs on OpenShift Virtualization and deregister them from AAP, leaving the expensive one-time setup intact — CNV, the boot-source DataSources including the Windows golden image, and the Terraform state namespace. Runs playbooks/teardown.yml. TRIGGER when: the user asks to tear down, destroy, clean up, or remove demo VMs, wants to free cluster memory before provisioning a different tier, or says a demo is finished. SKIP: if the user wants to remove OpenShift Virtualization itself or rebuild the golden image — this deliberately preserves both — or only wants to stop a VM rather than destroy it."
---

# sales-demos-teardown

Destroys the VMs from `terraform/ocpvirt/` and removes them from the AAP
inventory. This is the counterpart to `sales-demos-provision`, and it runs the same
Terraform state.

## What survives, and why it matters

`terraform destroy` can only remove what is in its state, so scoping is a
property of the module rather than a flag anyone has to remember:

| Destroyed | Preserved |
|---|---|
| The demo namespace (`sales-demos-<env>`) | OpenShift Virtualization (`openshift-cnv`) |
| The Linux and Windows VMs | The boot-source DataSources, incl. the Windows golden image |
| Their Services and Routes | The published quay containerdisk |
| The `sd1.*` cluster instance types | `sales-demos-tfstate`, the state namespace |

Rebuilding CNV or the golden image is roughly a 45-minute cost. **Do not "tidy
up" anything by hand after a teardown** — the reason this is safe is that
Terraform never had those objects, and a manual `oc delete` has no such
guardrail.

The state namespace surviving is load-bearing: it holds the Secret describing
every VM Terraform tracks, for **both** environments. Deleting it orphans
everything.

## Preflight Check

```bash
./utilities/preflight.sh "${ENV:-sandbox}" --terraform

# What is actually running right now
#    mcp__openshift-<env>__resources_list  kubevirt.io/v1 VirtualMachine  namespace: sales-demos-<env>
#    mcp__openshift-<env>__resources_list  kubevirt.io/v1 VirtualMachineInstance  namespace: sales-demos-<env>
```

## Confirm before running

Say which environment is about to be torn down, which `vm_role` is being
destroyed, and what is in it, and get an explicit yes. A teardown is not
reversible — the VMs are gone and a rebuild is a fresh boot, roughly six minutes
cold.

**`vm_role` must match the role the VMs were provisioned with.** Each role has
its own Terraform state (`secret_suffix=<env>-<os>-<role>`), so a teardown
without the correct role inits an empty state, destroys nothing, and still
reports success. The default is `web`.

Be especially careful with `demo`: it is the environment customers are shown.

**Never pipe the run through `tee`.** In a pipeline the exit status comes from
`tee`, not `ansible-playbook`, so a failed run reports success.

## Run

```bash
ansible-playbook playbooks/teardown.yml -i inventory --limit sandbox \
  -e target_env=sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

`-e target_env=` is **required**, unlike every other playbook here. The shared
environment guard only compares it against the inventory when it is supplied, so
omitting it lets a mistyped `--limit` through — an acceptable risk for an apply
and not for a destroy.

Pass the same `vm_role`, `os_type` and `vm_size_tier` the VMs were provisioned
with, or Terraform plans against a different shape:

```bash
  -e vm_role=db -e os_type=both -e vm_size_tier=large
```

## Verify it in the EE before merging a change

See `/sales-demos-verify-ee` for why and how. The one command:

```bash
utilities/run-in-ee.sh playbooks/teardown.yml \
  -i inventory --limit sandbox -e target_env=sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

## Verify against the cluster, not the recap

```
# Nothing left in the demo namespace
mcp__openshift-<env>__resources_list  kubevirt.io/v1 VirtualMachine  namespace: sales-demos-<env>
mcp__openshift-<env>__resources_list  v1 Service  namespace: sales-demos-<env>
mcp__openshift-<env>__resources_list  route.openshift.io/v1 Route  namespace: sales-demos-<env>

# The things that must have survived
mcp__openshift-<env>__resources_list  hco.kubevirt.io/v1beta1 HyperConverged  namespace: openshift-cnv
mcp__openshift-<env>__resources_list  cdi.kubevirt.io/v1beta1 DataSource  namespace: openshift-virtualization-os-images
mcp__openshift-<env>__resources_list  v1 Secret  namespace: sales-demos-tfstate
```

Expect the first to be empty and the last three to be intact. A green Ansible
recap only says the tasks ran.

## From AAP

The `Linux Day 1 - Teardown` job template does the same thing, and runs
**nightly on a schedule** — 6 PM and 10 PM in sandbox, 6 PM only in demo, all
`America/Phoenix` (no daylight saving, so they never drift).

It is the only template that runs against `Sales Demo VMs - Control`, because it
deletes hosts from `Sales Demo VMs` and AAP locks the hosts of the inventory a
running job is using.

## If it fails

- **`terraform init` errors** — the backend needs the same `secret_suffix` the
  provisioning run wrote. Pointing it elsewhere finds an empty state, reports
  success, and leaves every VM running.
- **Destroy fails partway** — hosts are deliberately left registered in AAP.
  Deregistering them while the VMs still exist would leave the cluster holding
  resources nothing points at. Fix the cause and re-run; it is idempotent.
- **`0 destroyed` and VMs still visible** — almost always the wrong `vm_role`,
  wrong environment, or wrong `secret_suffix`. Each role has its own state, so a
  teardown without `-e vm_role=<role>` defaults to `web` and inits an empty state
  for the role that was actually provisioned. Check `vm_role` first, then
  `aap_env_name`.
- **`Error acquiring the state lock`** — a previous run was cancelled, timed
  out, or had its pod evicted, and never released the lock. Teardown is the
  likelier victim of the two playbooks, because the nightly schedule can start
  while a manual job is still running. The playbook now fails with the lock ID
  and the exact `force-unlock` command (#46); see the same entry in
  `sales-demos-provision` for how to read `Who:` and why nothing unlocks
  automatically.
