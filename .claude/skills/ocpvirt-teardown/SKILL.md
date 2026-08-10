---
name: ocpvirt-teardown
description: "Destroy the demo VMs on OpenShift Virtualization and deregister them from AAP, leaving the expensive one-time setup intact — CNV, the boot-source DataSources including the Windows golden image, and the Terraform state namespace. Runs playbooks/teardown.yml. TRIGGER when: the user asks to tear down, destroy, clean up, or remove demo VMs, wants to free cluster memory before provisioning a different tier, or says a demo is finished. SKIP: if the user wants to remove OpenShift Virtualization itself or rebuild the golden image — this deliberately preserves both — or only wants to stop a VM rather than destroy it."
---

# ocpvirt-teardown

Destroys the VMs from `terraform/ocpvirt/` and removes them from the AAP
inventory. This is the counterpart to `ocpvirt-provision`, and it runs the same
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
# 1. Which environment, and is it the one you mean? This playbook destroys.
grep -h '^aap_env_name' inventory/group_vars/sandbox/connection.yml inventory/group_vars/demo/connection.yml

# 2. What is actually running right now
oc get vm,vmi -n sales-demos-sandbox 2>/dev/null || echo "(oc not logged in — the playbook uses the vault token, not your session)"

# 3. The vault password must be present or nothing decrypts
test -r ~/secrets/.vault_pass_sales_demos \
  && echo "✅ vault password present" || echo "❌ ~/secrets/.vault_pass_sales_demos missing"

# 4. terraform must be on PATH for a laptop run (the EE has it for AAP runs)
command -v terraform >/dev/null && echo "✅ $(terraform version | head -1)" || echo "❌ terraform not installed"
```

## Confirm before running

Say which environment is about to be torn down and what is in it, and get an
explicit yes. A teardown is not reversible — the VMs are gone and a rebuild is
a fresh boot, roughly six minutes cold.

Be especially careful with `demo`: it is the environment customers are shown.

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

If the VMs were provisioned with a non-default tier, pass the same values that
built them, or Terraform plans against a different shape:

```bash
  -e os_type=both -e vm_size_tier=large-2cpu-6gb
```

## Verify against the cluster, not the recap

```bash
# Nothing left in the demo namespace
oc get vm,vmi,svc,route -n sales-demos-sandbox

# The things that must have survived
oc get hyperconverged -n openshift-cnv
oc get datasource -n openshift-virtualization-os-images
oc get secret -n sales-demos-tfstate | grep tfstate
```

Expect the first to be empty and the last three to be intact. A green Ansible
recap only says the tasks ran.

## From AAP

The `Sales Demos - Teardown VMs` job template does the same thing, and runs
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
- **`0 destroyed` and VMs still visible** — almost always the wrong environment
  or the wrong `secret_suffix`. Check `aap_env_name` resolved to what you meant.
- **`Error acquiring the state lock`** — a previous run was cancelled, timed
  out, or had its pod evicted, and never released the lock. Teardown is the
  likelier victim of the two playbooks, because the nightly schedule can start
  while a manual job is still running. The playbook now fails with the lock ID
  and the exact `force-unlock` command (#46); see the same entry in
  `ocpvirt-provision` for how to read `Who:` and why nothing unlocks
  automatically.
