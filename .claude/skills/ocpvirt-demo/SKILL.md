---
name: ocpvirt-demo
description: "Re-run the demo content on Linux or Windows VMs that ALREADY EXIST: register or patch them, install and configure the web server, rescan for CIS compliance, and turn the demo URL from a 503 into a real page. Launches the Linux Day 1 - Repair or Windows Day 1 - Repair job template in AAP, whichever the VM is. TRIGGER when: the user asks to re-run, repair or reconfigure the demo content, says the demo URL returns 503 or does not load, wants a page tweak applied, or is recovering from a failed step on a VM that is still up. SKIP: if no VMs exist yet — a build from nothing is the Linux Day 1 - 0 Workflow or Windows Day 1 - 0 Workflow, reached through ocpvirt-provision — or if the environment itself has never been set up, which is ocpvirt-setup."
---

# ocpvirt-demo

Takes demo VMs that exist and makes them a demo again — Linux or Windows.

`terraform/ocpvirt` gives every demo VM a Service and a Route (#29 for Linux,
#340 for Windows), so a public URL exists from the moment it is provisioned —
and returns **503**, because nothing is serving on port 80. This is the other
half of that story.

## First: which OS?

**Ask, or look, before doing anything else.** The two chains share a shape and
share nothing else — different group, different credential, different job
template, different reason the middle step exists.

| | Linux | Windows |
|---|---|---|
| AAP inventory group | `linuxweb` | `windemo` |
| Job template | `Linux Day 1 - Repair` | `Windows Day 1 - Repair` |
| Machine credential | `Sales Demos - Linux Machine` | `Sales Demos - Windows Machine` |
| Reached over | SSH, port 22 | WinRM/HTTPS, port 5986 |
| Step 1 | Register to the Red Hat CDN | Patch from Windows Update |
| Web server | httpd | IIS |
| Compliance | OpenSCAP scan | Configuration verification |

If it is not obvious which exists, ask the cluster rather than guessing:

```
mcp__openshift-<env>__resources_list  kubevirt.io/v1 VirtualMachine
```

VMs are named `{role}-{os}-{index}` since #389: `*-lnx-*` is Linux, `*-win-*`
is Windows, and the leading word is the workload role (`web`, `db`, `app`).
`web-lnx-1` and `web-win-1` can exist at once — they have separate Terraform
state since #301 — and so can several members of one farm, and several roles,
each with their own state. Ask which one is broken rather than assuming there
is only one.

The role is a label too, so a farm can be selected without parsing names:

```
mcp__openshift-<env>__resources_list  kubevirt.io/v1 VirtualMachine
  labelSelector: sales-demos/role=web
```

## This is the repair path, not the build path

`Linux Day 1 - 0 Workflow` and `Windows Day 1 - 0 Workflow` are what you launch
to build a demo VM from nothing: each provisions, prepares, configures, scans
and verifies in the only order that works, one button. Use those for a fresh
environment.

This skill is for a VM that is **already up** — a page tweak, a re-run after one
step failed, or the recovery half of a break/fix story. It skips terraform
entirely, so it cannot rebuild a VM that is gone.

## This launches an AAP job template rather than running Ansible locally

That is deliberate, not a shortcut. `repair_linux_vm.yml` targets `linuxweb` and
`repair_windows_vm.yml` targets `windemo`, groups that exist **only in AAP's
inventory** — `provision_vm.yml` registers the VMs there at run time, and this
repo's file inventory has no VM hosts at all. A laptop cannot resolve
`*.svc.cluster.local` in any case. AAP runs on the same cluster and reaches the
guests directly over the pod network.

So the honest path is: launch the template.

---

# Linux

## What it does, and why the order matters

**1. Register to the Red Hat CDN** — `roles/linux_register`

The single most surprising thing about these guests: **the CNV `rhel9` image has
no package repositories and no subscription.** The VM boots perfectly and
answers SSH, and then:

```
dnf repolist       -> No repositories available
dnf install httpd  -> Error: There are no enabled repositories in ...
```

Nothing else in the demo can run until this succeeds. The role uses the
certified `redhat.rhel_system_roles.rhc` role with an activation key from the
vault, and — importantly — **verifies repositories actually appeared**, because
registration can report success while no entitlement matched.

**2. Configure the web server** — `roles/linux_configure`

httpd, firewalld, Cockpit, chrony, the demo page, and security patching.

**3. Rescan for CIS compliance** — `roles/linux_compliance`

## Preflight Check

```bash
# 1. Are there VMs to configure? They must already be registered in AAP.
echo "check the Sales Demo VMs inventory in AAP, group linuxweb"

# 2. Registration credentials present in the vault
ansible-vault view playbooks/group_vars/all/secrets.yml \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos 2>/dev/null \
  | grep -q '^rhsm_activation_key:' \
  && echo "✅ rhsm_activation_key present" \
  || echo "❌ no rhsm_activation_key — registration will fail, and so will everything after it"

# 3. The job template exists
echo "expect: Linux Day 1 - Repair, inventory 'Sales Demo VMs', limit linuxweb"
```

## Run

Launch **`Linux Day 1 - Repair`** in AAP. It runs register, configure and the
compliance rescan in sequence — the same three playbooks the workflow runs as
nodes 2, 3 and 4, so a repaired VM ends in the same state a freshly built one
does. It needs two credentials, and both matter:

| Credential | Why |
|---|---|
| `Sales Demos - Linux Machine` | SSH into the guest |
| `Sales Demos - Vault` | Decrypt the registration credentials |

Missing the Vault credential is the likelier mistake, and it fails in the
registration assert with a message saying so.

## Useful knobs

```bash
# Patch but do not reboot (the default — a reboot mid-demo takes the page away)
-e linux_configure_reboot=false

# Make patching the point of the demo: reboot when the kernel is updated
-e linux_configure_reboot=true

# Skip patching entirely for a fast rebuild
-e linux_configure_patch=false

# Change the message on the page
-e linux_configure_message="Whatever this demo is about"
```

## If it fails

- **`no enabled repositories` after registration** — the activation key is not
  attached to a RHEL subscription, or has no matching entitlement. Check it at
  console.redhat.com. The role fails loudly here rather than letting `dnf` fail
  later with a message pointing nowhere near the cause.
- **The assert about `rhsm_org_id` / `rhsm_activation_key`** — the Vault
  credential is not attached to the job template.
- **Job succeeds but the URL still 503s** — httpd is running but firewalld
  inside the guest is blocking, or the VM was rebuilt after the run. Re-launch;
  it is idempotent.
- **Unreachable** — the VM was recreated and the demo SSH key was not injected.
  cloud-init writes authorized keys on **first boot only**, so a VM created while
  `demo_ssh_public_key` was empty has no credentials at all and must be
  re-created, not restarted.

---

# Windows

Added in #340. Before that there was no Windows configure path at all — the
`windemo` group existed and was referenced by zero playbooks and zero job
templates.

## What it does, and why the order matters

**1. Patch from Windows Update** — `roles/windows_patching`

**This is the slot Linux uses for CDN registration, and the substitution is the
point.** Windows has nothing to register: the golden image ships complete, with
none of the `rhel9` image's missing-repository problem. The honest analogue of
"entitle the guest to content" is "point it at its update source and bring it
current" — and it puts any reboot *before* IIS is installed, which is the safe
order.

It **waits for WinRM first**, and that wait is longer than the Linux one for a
real reason: a freshly cloned Windows guest has to finish sysprep's specialize
and oobeSystem passes and then run the FirstLogonCommands that stand up the
WinRM listener. Default 900 seconds.

Security and Critical updates only by default, so the node does not run for half
an hour in front of a customer.

**2. Configure the web server** — `roles/windows_configure`

IIS, the demo page and its logos, `facts.json`, a pre-authentication legal
notice, and — **not optional** — an inbound firewall rule for port 80. The image
is CIS hardened, so the Public profile is on and blocking by default, and a
KubeVirt NIC lands on Public. Without that rule IIS serves perfectly and the
Route still returns 503.

**3. Verify CIS compliance** — `roles/windows_compliance`

**It verifies; it does not scan.** OpenSCAP has no Windows agent. The role reads
27 controls that `image.builder.pipeline/playbooks/vars/cis_profile.yml` enables
back off the running guest and publishes a report beside the demo page. All
reads, so it is safe to re-run mid-demo.

## Preflight Check

```bash
# 1. Is there a Windows VM to configure, and is it registered in AAP?
echo "check the Sales Demo VMs inventory in AAP, group windemo"

# 2. The Windows admin password must be in the vault — the credential carries
#    it, and it is NOT the Linux one (#338). CIS L1 needs 14 characters and
#    linux_admin_password is deliberately 8.
ansible-vault view playbooks/group_vars/all/secrets.yml \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos 2>/dev/null \
  | grep -q 'windows_admin_password' \
  && echo "✅ windows_admin_password present" \
  || echo "❌ no windows_admin_password — WinRM auth will fail and read like a listener problem"

# 3. The job template exists
echo "expect: Windows Day 1 - Repair, inventory 'Sales Demo VMs', limit windemo"
```

## Run

Launch **`Windows Day 1 - Repair`** in AAP. It runs patch, configure and the
compliance re-verification in sequence — the same three playbooks the workflow
runs as nodes 2, 3 and 4.

| Credential | Why |
|---|---|
| `Sales Demos - Windows Machine` | WinRM into the guest, as `demoadmin` |
| `Sales Demos - Vault` | `group_vars/all/secrets.yml` is parsed for every play |

**Attaching the Linux Machine credential by mistake fails as an authentication
error**, which reads like a listener or firewall problem rather than a wrong
credential. Check the credential before debugging the network.

## Useful knobs

```bash
# Patch faster or wider (survey-controlled on the job template)
-e '{"windows_patching_categories": ["SecurityUpdates", "CriticalUpdates"]}'

# Make patching the point of the demo: reboot when an update requires it
-e windows_patching_reboot=true

# Change the message on the page
-e windows_configure_message="Whatever this demo is about"

# Fail the job on a non-compliant control, rather than just reporting it
-e windows_compliance_fail_on_noncompliant=true
```

## If it fails

- **WinRM auth fails, "the specified credentials were rejected by the server"** —
  most often the wrong Machine credential (see above). If it is the right one,
  the guest may have been created before `windows_admin_password` was set: the
  sysprep unattend sets the password on **first boot only**, so the VM must be
  re-created, not restarted.
- **Job succeeds but the URL still 503s** — IIS is running and the guest's
  firewall is blocking port 80. `Windows Day 1 - 5 Check` distinguishes these
  two on purpose: it asks the guest over loopback *and* asks the Route, because
  loopback is not filtered by Windows Firewall and so proves only IIS.
- **The compliance node reports controls as "not configured"** — that is a real
  finding, not a role bug: the value is absent, so the hardening did not take.
  If *all nine* policy controls report it at once, `secedit /export` failed and
  the report says so at the top.
- **Timed out waiting for WinRM** — the clone is still in sysprep. Watch the VM
  console in the OpenShift UI; a guest stuck at a prompt rather than progressing
  is `image.builder.pipeline` #69 territory, not this repo's.

---

## The check that matters, either OS

```bash
cd terraform/ocpvirt && for u in $(terraform output -json web_urls | jq -r '.[]'); do
  echo "$u"; curl -sI "$u" | head -1
done
```

**Before:** `HTTP/1.1 503 Service Unavailable`
**After:** `HTTP/1.1 200 OK`

`web_url` resolves per-OS (#340), so this is one command for both families
rather than two outputs to remember.

That is the whole point of the phase. A green job recap is not the same thing —
the Route, the Service, the guest's own firewall and the web server all have to
line up, and only this proves it.
