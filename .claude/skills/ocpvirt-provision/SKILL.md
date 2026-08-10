---
name: ocpvirt-provision
description: "Phase 3 — build demo VMs on OpenShift Virtualization with Terraform and register them as managed hosts in AAP, ready for the daily-demo content to run against. Runs playbooks/provision_vm.yml. TRIGGER when: the user asks to provision, create, build or spin up demo VMs, wants a Linux or Windows VM for a demo, or asks for a specific size tier. SKIP: if the environment has never been set up — that is ocpvirt-setup — or if the user wants to destroy VMs, which is ocpvirt-teardown."
---

# ocpvirt-provision

Phase 3. Runs `terraform/ocpvirt/` and registers the resulting VMs in AAP so the
demo content has hosts to run against.

This skill contains **no logic**. All the work is in
[`playbooks/provision_vm.yml`](../../../playbooks/provision_vm.yml), which is the
same playbook the `Sales Demos - Provision VM` job template runs, with survey
answers mapped to the same variable names. See `CLAUDE.md` →
*Skills and playbooks*.

**Prefer the job template when AAP is available** — it is the demo-able path and
the one a customer sees. This skill is for when you are working ahead of AAP, or
debugging a run without the controller in the way.

## The inputs are the contract

| Variable | Values | Default |
|---|---|---|
| `vm_size_tier` | `small-1cpu-2gb`, `medium-1cpu-4gb`, `large-2cpu-6gb` | `small-1cpu-2gb` |
| `os_type` | `linux`, `windows`, `both` | `linux` |

These names are shared verbatim with the AAP survey and
`terraform/ocpvirt/variables.tf`. Changing one means changing all three.

**`os_type=windows` or `both` will create a VM that never boots** until Phase 2
(#3) publishes the Windows golden image — CNV ships `win2k22` as an empty
DataSource placeholder. The playbook warns rather than refuses, because the
Terraform side is wired and worth being able to plan against.

## Preflight Check

```bash
# 1. Which environment, and is it the one you mean?
grep -h '^aap_env_name\|^openshift_api_url' \
  inventory/group_vars/sandbox/connection.yml inventory/group_vars/demo/connection.yml

# 2. terraform on PATH — the playbook shells out to it
command -v terraform >/dev/null && echo "✅ $(terraform version | head -1)" || echo "❌ terraform not installed"

# 3. The vault password, or nothing decrypts
test -r ~/secrets/.vault_pass_sales_demos \
  && echo "✅ vault password present" || echo "❌ ~/secrets/.vault_pass_sales_demos missing"

# 4. Is the environment warm? A cold boot source makes this slow, not broken.
#    ocpvirt-new-env answers this properly in about a minute.
echo "run /ocpvirt-new-env if this environment has been idle or is new"
```

## Run

```bash
ansible-playbook playbooks/provision_vm.yml -i inventory --limit sandbox \
  -e target_env=sandbox -e os_type=linux -e vm_size_tier=small-1cpu-2gb \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

Idempotent — re-running converges rather than rebuilding. A second run reports
`changed=0`, and that is the check that it is behaving.

## What it does

1. Ensures the **state namespace** exists — the Terraform kubernetes backend
   needs it before there is any state to describe it with. It does **not** create
   the VM namespace; Terraform owns that.
2. `terraform init` against the kubernetes backend, then `apply`.
3. Reads the outputs and registers each VM in the `Sales Demo VMs` inventory —
   `linuxweb` with SSH vars, `windemo` with WinRM vars.

## Verify against the cluster, not the recap

```bash
oc get vm,vmi -n sales-demos-sandbox
```

`apply` returning does **not** mean the guest is up: the default StorageClass is
`WaitForFirstConsumer`, so the disk clones only when the VM first schedules.
Expect the VM to reach `Running` roughly 45s after apply on a warm environment.

Then confirm AAP can actually reach it — that is what `Sales Demos - Check VMs`
is for, and it is the difference between "a VM exists" and "the demo will work".

## Notes worth having before you debug

- **AAP reaches the VMs over in-cluster DNS on port 22.** It runs on the same
  cluster and each VM has a headless Service. No bastion, and no `virtctl` —
  that is the laptop path, and the execution environment does not ship it.
- **From a laptop, use `virtctl ssh`.** The `ssh_command` Terraform output gives
  you the exact line, and the Provision, Configure and Check job logs print it
  too. If a line you kept from before #49 fails with `unknown flag:
  --local-ssh`, that flag was removed in virtctl v1.x — drop it, and keep the
  `vm/` prefix on the target.
- **`demo_ssh_public_key` must not be empty.** cloud-init then emits
  `ssh_pwauth: true` with no key *and* no password, and the guest has no
  credentials at all. It writes authorized keys on **first boot only**, so a VM
  created that way must be re-created, not restarted.
- **State lives in `sales-demos-tfstate`**, a long-lived namespace of its own,
  keyed per environment by `secret_suffix`. Never delete it.
