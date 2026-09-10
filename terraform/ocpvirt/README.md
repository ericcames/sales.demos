# `terraform/ocpvirt` — demo VMs on OpenShift Virtualization

Builds the Linux and Windows demo VMs: t-shirt-sized from a shared catalog, each
with a headless Service for in-cluster DNS, optionally a Route for HTTP and one
for Cockpit.

**`terraform/` is keyed by platform, not by demo** — demos reuse platforms.

## It is normally run by AAP, not by hand

`playbooks/provision_vm.yml` drives this module, and that playbook is what the
`Linux Day 1 - 1 Provision` and `Windows Day 1 - 1 Provision` job templates run.
Launch the workflow, not this. Running `terraform apply` directly is for
developing the module itself.

State and `terraform.tfvars` are gitignored and must stay that way.

## Running it by hand

Rather than writing a token to disk, pass the variables as `TF_VAR_*` straight
from the vault:

```bash
cd terraform/ocpvirt

export TF_VAR_openshift_api_token=$(
  ansible-vault view ../../playbooks/group_vars/all/secrets.yml \
    --vault-id sales.demos@~/secrets/.vault_pass_sales_demos \
  | python3 -c 'import sys,yaml;print(yaml.safe_load(sys.stdin)["env_secrets"]["sandbox"]["openshift_api_token"])')

export TF_VAR_openshift_api_url=https://api.cluster-<id>.dyn.redhatworkshops.io:6443
export TF_VAR_openshift_insecure=true
export TF_VAR_namespace=sales-demos-sandbox
export TF_VAR_vm_size_tier=small             # | medium | large
export TF_VAR_os_type=linux                  # | windows | both
export TF_VAR_vm_count=1                     # server farms, #389

terraform init && terraform apply
```

`terraform.tfvars.example` shows the same inputs in file form.

> **`apply` finishing does not mean the guest is up.** The default
> StorageClass is `WaitForFirstConsumer`, so the disk clones only once the VM
> first schedules — apply returns in about 10s, and the VM reports `Ready`
> well after. Watch the VM, not the recap:


```bash
oc get vm,vmi,pvc -n sales-demos-sandbox -w
```

## Sizing

`tiers.yaml` is the **single catalog, read by two languages** — `locals.tf` via
`yamldecode`, and `playbooks/tasks/ensure_shared_objects.yml`, which creates the
`sd1.*` `VirtualMachineClusterInstancetype` objects from it. Neither owns a copy
(#348).

| Tier | Instance type | CPU / memory | Root disk |
|---|---|---|---|
| `small` | `sd1.small` | 2 / 4 GiB | 30 GiB |
| `medium` | `sd1.medium` | 2 / 8 GiB | 30 GiB |
| `large` | `sd1.large` | 4 / 16 GiB | 50 GiB |

Windows is floored at 60 GiB regardless of tier (`windows_min_disk_gb`).

> **`small-1cpu-2gb` and friends are retained aliases, not descriptions**
>
> `tiers.yaml` still maps `small-1cpu-2gb` -> `small`, `medium-1cpu-4gb` ->
> `medium` and `large-2cpu-6gb` -> `large`, so old invocations keep working.
> **The names no longer describe the shape** — `large-2cpu-6gb` provisions
> 4 CPU and 16 GiB. Prefer the plain names, which is what the AAP surveys
> offer.


These are repo-owned `sd1.*` types; Red Hat's `u1.*` are left untouched.

`available_memory_gb` defaults to **63**, measured by `probe_env.yml` on sandbox
2026-09-03 with Automation Orchestrator installed (#118, #141). A precondition
enforces that budget, so an over-budget request fails in `plan` rather than
leaving a VM `Pending` while Terraform reports success. Re-run
`sales-demos-probe-env` rather than hand-adjusting it.

## Outputs

`os_type`, `namespace`, `linux_inventory`, `windows_inventory`, `memory_budget`,
and — **plural, since VMs come in counts** (#389) — `web_urls`, `cockpit_urls`,
`ssh_commands`.

## SSH access

NodePort was spiked on RHDP and is **filtered** — the RHDP firewall blocks high
ports, so `ssh -p <nodePort>` from a laptop never connects. Use `virtctl ssh`,
which tunnels over the Kubernetes API on 6443.

Prerequisites: `virtctl` (from the cluster's ConsoleCLIDownload), and this repo's
kubeconfig for the environment — **not** `oc login` (#161):

```bash
KUBECONFIG=.kube/sandbox.kubeconfig \
  virtctl ssh -n sales-demos-sandbox cloud-user@vm/web-lnx-1
```

**Name the kubeconfig; do not rely on `~/.kube/config`.** `virtctl` defaults to
it, it is shared with other demo repos, and a rebuilt environment leaves it
pointing at a cluster whose DNS no longer resolves — the failure reads
`dial tcp: lookup api.cluster-... no such host` and says nothing about
kubeconfigs. Generate with `utilities/make-kubeconfig.sh <env>`; check with
`utilities/check-kubeconfig.sh <env>`.

No `-i` is needed: the VM's authorized key is `demo_ssh_public_key`, whose
private half is an ordinary default identity in `~/.ssh`.

```bash
export TF_VAR_demo_ssh_public_key="$(cat ~/.ssh/id_rsa.pub)"
```

> **No `--local-ssh`**
>
> Older notes and anything copied from a pre-#49 `ssh_commands` output carry
> that flag. virtctl v1.x removed its built-in SSH client, so local ssh became
> the only mode and the flag was deleted rather than defaulted — it now fails
> with `unknown flag: --local-ssh` before connecting. Pass ssh options with
> `-t/--local-ssh-opts`. Keep the `vm/` prefix: virtctl takes a `(VM|VMI)`
> resource, not a bare name.


> **`demo_ssh_public_key` must not be empty**
>
> cloud-init then emits `ssh_pwauth: true` with no authorized key *and* no
> password, and the guest has no credentials at all. Because cloud-init writes
> authorized keys only on first boot, a VM created that way must be
> **re-created**, not restarted.


## HTTP access

When `TF_VAR_openshift_apps_domain` is set, Terraform creates a `-web` ClusterIP
Service on port 80 and a Route targeting it. `web_urls` gives the public URLs.

```bash
export TF_VAR_openshift_apps_domain=apps.cluster-<id>.dyn.redhatworkshops.io
# find it with: oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}'
```

**The URL returns 503 until httpd is installed** by the demo content. That is
expected, not a bug.

## Cockpit (browser terminal)

When `openshift_apps_domain` is set and `linux_admin_password` is non-empty,
Terraform creates a `-cockpit` Service on 9090 and a Route. `cockpit_urls` gives
the URLs. Log in as `cloud-user` with the vaulted password for a terminal plus a
system dashboard — the RHEL web console, which demos better than a bare
terminal, and needs **no `virtctl`**. This is the customer-facing path; `virtctl
ssh` remains the operator one.

**The Route is publicly reachable and Cockpit is a root-capable shell.** Use a
strong vaulted password and rely on nightly teardown. Acceptable on an ephemeral
RHDP sandbox; it would not be on anything long-lived.

`cockpit.conf` is written at first boot via cloud-init `write_files` with
`AllowUnencrypted = true` (the Route terminates TLS, not Cockpit) and the Route
hostname as an allowed Origin — Cockpit validates websocket Origin headers, and
getting this wrong makes login appear to succeed while the terminal hangs.

## Windows

CNV ships `win2k22` as an empty DataSource placeholder — Red Hat cannot
redistribute Windows media — so `playbooks/link_windows_image.yml` imports the
published CIS L1 containerdisk and takes that placeholder over, the same
mechanism that keeps `rhel9` populated (#3). The image is built and published by
[image.builder.pipeline](https://github.com/ericcames/image.builder.pipeline);
the tag is `quay_windows_image` in `inventory/group_vars/<env>/connection.yml`.

**Repoint, never overwrite** — tags are immutable, and the import decision is
made on *image identity*, not on whether the DataSource is Ready. Ready and
Bound are both true of the wrong image; that was #358.
