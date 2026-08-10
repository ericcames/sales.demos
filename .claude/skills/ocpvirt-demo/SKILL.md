---
name: ocpvirt-demo
description: "Phase 4 — run the daily-demo content on the provisioned VMs: register them to the Red Hat CDN, install and configure the web server, and turn the demo URL from a 503 into a real page. Launches the Sales Demos - Run Demo job template in AAP. TRIGGER when: the user asks to run or set up the demo, configure the VMs, install the web server, or says the demo URL returns 503 or does not load. SKIP: if no VMs exist yet — that is ocpvirt-provision — or if the environment itself has never been set up, which is ocpvirt-setup."
---

# ocpvirt-demo

Phase 4. Takes VMs that exist and makes them a demo.

`terraform/ocpvirt` gives every Linux VM a Service and a Route (#29), so a
public URL exists from the moment it is provisioned — and returns **503**,
because nothing is serving on port 80. This is the other half of that story.

## This launches an AAP job template rather than running Ansible locally

That is deliberate, not a shortcut. `playbooks/run_demo.yml` targets `linuxweb`,
a group that exists **only in AAP's inventory** — `provision_vm.yml` registers
the VMs there at run time, and this repo's file inventory has no VM hosts at
all. A laptop cannot resolve `*.svc.cluster.local` in any case. AAP runs on the
same cluster and reaches the guests directly over the pod network.

So the honest path is: launch the template.

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
echo "expect: Sales Demos - Run Demo, inventory 'Sales Demo VMs', limit linuxweb"
```

## Run

Launch **`Sales Demos - Run Demo`** in AAP. It needs two credentials, and both
matter:

| Credential | Why |
|---|---|
| `Sales Demos - Linux Machine` | SSH into the guest |
| `Sales Demos - Vault` | Decrypt the registration credentials |

Missing the Vault credential is the likelier mistake, and it fails in the
registration assert with a message saying so.

## The check that matters

```bash
cd terraform/ocpvirt && curl -sI "$(terraform output -raw web_url)" | head -1
```

**Before:** `HTTP/1.1 503 Service Unavailable`
**After:** `HTTP/1.1 200 OK`

That is the whole point of the phase. A green job recap is not the same thing —
the Route, the Service, firewalld inside the guest and httpd all have to line up.

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

## Windows

Not yet. Phase 2 (#3) has to publish the golden image first — CNV ships
`win2k22` as an empty DataSource, so a Windows VM is created and never boots.
