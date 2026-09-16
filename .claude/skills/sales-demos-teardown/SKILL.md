---
name: sales-demos-teardown
description: "Destroy the demo VMs on OpenShift Virtualization and deregister them from AAP, leaving the expensive one-time setup intact — CNV, the boot-source DataSources including the Windows golden image, and the Terraform state namespace. Runs playbooks/teardown.yml from AAP — the "Linux Day 1 - Teardown" and "Windows Day 1 - Teardown" job templates — because the guest deregistration reaches the VMs at a name only the cluster resolves. TRIGGER when: the user asks to tear down, destroy, clean up, or remove demo VMs, wants to free cluster memory before provisioning a different tier, or says a demo is finished. SKIP: if the user wants to remove OpenShift Virtualization itself or rebuild the golden image — this deliberately preserves both — or only wants to stop a VM rather than destroy it."
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

## Teardown runs from AAP, not from a laptop

Before destroying anything, `teardown.yml` SSHes into every Linux guest to
release its Red Hat subscription and remove its Insights host (#47). It reaches
them at `<vm>.<namespace>.svc.cluster.local`, the headless Service DNS name,
which resolves **only from inside the cluster**. An AAP execution environment
pod runs there; your laptop does not.

That is not a soft limit. An unreachable delegate is not a *failed* task, so
Ansible drops the host and the play ends **before `terraform destroy`** — the
run exits 4 with `failed=0` while the VM, its Terraform state and its AAP host
are all still there (#638).

So the playbook now checks the resolver up front and stops with a message
naming the job template, having destroyed nothing. Windows is unaffected: its
teardown never touches an in-cluster name, and still runs from a laptop.

## Preflight Check

```bash
./utilities/preflight.sh "${ENV:-sandbox}" --terraform

# Will the Linux guard let this run? Exit 0 = in-cluster, exit 2 = laptop.
getent hosts kubernetes.default.svc.cluster.local

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

Launch the job template in AAP. `Linux Day 1 - Teardown` and
`Windows Day 1 - Teardown` both run `playbooks/teardown.yml`, and they are the
only supported entry point for Linux.

```
mcp__aap-<env>__job_templates_list            name: Linux Day 1 - Teardown
mcp__aap-<env>__job_templates_launch_create   extra_vars as below
mcp__aap-<env>__jobs_stdout_retrieve
```

The template already supplies `target_env`, which is **required** here unlike
every other playbook in this repo: the shared environment guard only compares it
against the inventory when it is supplied, so omitting it lets a mistyped limit
through — an acceptable risk for an apply and not for a destroy.

**Pass the same `vm_role`, `os_type` and `vm_size_tier` the VMs were
provisioned with**, or Terraform plans against a different shape. `os_type` is
`linux` or `windows`; `both` was removed in #301, so tear each OS down
separately. The template defaults are `vm_role: web`, `os_type: linux`,
`vm_size_tier: small`; override them in the launch's extra vars:

```yaml
vm_role: db
os_type: linux
vm_size_tier: large
```

**To remove every role at once, pass `all_roles: true`** (#393). The playbook
lists the Terraform state Secrets for this environment and OS
(`tfstate-default-<env>-<os>-<role>` in `sales-demos-tfstate`) and tears down
each role it finds; `vm_role` is ignored.

```yaml
all_roles: true
os_type: linux
```

**The nightly schedules do exactly that**: 6 PM and 10 PM in sandbox, 6 PM only
in demo, all `America/Phoenix` (no daylight saving, so they never drift). Every
schedule passes `all_roles: true`, so each sweep removes every role with state
for its OS. A manual launch removes only the template's `vm_role` unless you add
it yourself.

Teardown is the only template that runs against `Sales Demo VMs - Control`,
because it deletes hosts from `Sales Demo VMs` and AAP locks the hosts of the
inventory a running job is using.

### Windows, from a laptop

A Windows teardown never reaches into a guest, so it has no in-cluster
dependency and the guard skips. This still works, and is the exception rather
than the pattern:

```bash
./utilities/run-ansible.sh playbooks/teardown.yml -i inventory --limit sandbox \
  -e target_env=sandbox -e os_type=windows \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

The same command with `-e os_type=linux` stops at the guard, by design.

## Verify it in the EE before merging a change

See `/sales-demos-verify-ee` for why and how. The one command:

```bash
utilities/run-in-ee.sh playbooks/teardown.yml \
  -i inventory --limit sandbox -e target_env=sandbox -e os_type=windows \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

**`os_type=windows` is not incidental.** `run-in-ee.sh` is podman *on your
laptop*: it gives you the EE's collections, python and terraform pin, but it
shares your laptop's resolver, so a Linux run stops at the same guard an
unwrapped laptop run does. That is correct behaviour, not a wrapper bug.

So the EE run verifies the terraform pin, the collection set and the whole
Windows path — but **a Linux teardown can only be verified by launching the job
template**. Do that before merging a change to this playbook.

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

## If it fails

- **`Tearing down Linux guests runs from AAP, not a laptop`** — the guard did
  its job (#638). You are outside the cluster, so the guest deregistration could
  not have reached the VMs and the play stopped before `terraform destroy`.
  Nothing was destroyed and nothing leaked. Launch `Linux Day 1 - Teardown`
  instead. `getent hosts kubernetes.default.svc.cluster.local` tells you which
  side of the line you are on. This also fires under `run-in-ee.sh`, because
  podman shares your laptop's resolver.
- **`UNREACHABLE` on `Disconnect the guest from Insights`** — cluster DNS
  resolved but that particular guest did not answer on port 22: it is stopped,
  already deleted, or the `Sales Demos - Linux Machine` credential is missing
  from the template. An unreachable delegate still ends the play before
  `terraform destroy`, so the VMs survive. Fix the guest or the credential and
  re-run; it is idempotent.
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
- **`all_roles=true` reports `(none — nothing to tear down)` but VMs are still
  running** — the roles come from the state Secrets' `tfstateSecretSuffix`
  label, so a VM with no state behind it is invisible to the sweep (for
  example, built before #389, or its state deleted by hand). Compare the
  `v1 Secret` list in `sales-demos-tfstate` with the VMs' `sales-demos/role`
  label.
- **`Error acquiring the state lock`** — a previous run was cancelled, timed
  out, or had its pod evicted, and never released the lock. Teardown is the
  likelier victim of the two playbooks, because the nightly schedule can start
  while a manual job is still running. The playbook now fails with the lock ID
  and the exact `force-unlock` command (#46); see the same entry in
  `sales-demos-provision` for how to read `Who:` and why nothing unlocks
  automatically.
