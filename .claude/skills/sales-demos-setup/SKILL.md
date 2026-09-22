---
name: sales-demos-setup
description: "Phase 0 of the sales.demos platform — take a bare RHDP environment to demo-ready in one command. Fourteen stages: tune the node's image GC thresholds and container log caps, persist the cluster monitoring storage, install OpenShift Virtualization, link the RHEL 9 CIS image, link the Windows CIS image, create shared cluster objects, apply the AAP configuration, deploy the MCP server, install and configure Automation Orchestrator, deploy the self-service portal, generate the environment URL reference, probe the cluster for available_memory_gb, then prove it by building and timing a real VM. Checks prerequisites, confirms the cluster is reachable, then runs playbooks/setup.yml. TRIGGER when: the user has a new or rebuilt RHDP environment, asks to set one up or prepare it for the ocpvirt demo, says OpenShift Virtualization or KubeVirt is missing, hits a missing kubevirt.io API, or asks to install CNV. SKIP: if the environment is already set up and the user wants to create demo VMs — that is sales-demos-provision — or only wants to re-check readiness, which is sales-demos-verify-env."
---

# sales-demos-setup

## Most of this runs from AAP now (#330)

`Cluster Day 0` is a workflow: install OpenShift Virtualization, link the RHEL 9
CIS L1 golden image, then verify the environment really works. Use it once
`config.yml` has run for the environment.

**`config.yml` is still the one laptop command**, and it has to be: it creates
the job templates, so it cannot be one of them. Run it first, then everything
else is buttons — which is also the point, since work in a terminal is invisible
to a customer and work in AAP is the demo.

`setup.yml` stays as the single-command laptop path. This is additive.

Phase 0. Takes a bare RHDP "Ansible Product Demo" environment to demo-ready in
**one command**.

This skill contains **no logic**. All the work is in
[`playbooks/setup.yml`](../../../playbooks/setup.yml), which imports fourteen
playbooks in order. The same playbooks run from AAP job templates with survey
answers mapped to the same variable names. See `CLAUDE.md` →
*Skills and playbooks*.

## What it does

**1. Tune node disk management** (`configure_node.yml`)

The RHDP single-node clusters put RHCOS, etcd, every container image and all pod
ephemeral storage on one ~107 GB filesystem. kubelet evicts at
`imagefs.available<15%` — 85% used — and `imageGCHighThresholdPercent` ships at
85 too, so image GC and pod eviction begin at the same instant. There is no band
in which GC rescues the node before pods die. That is the shape of #782 and #788.

Applies a `KubeletConfig` (`sales-demos-disk-tuning`) setting image GC to
**80/79** and capping container logs at 10Mi × 3 (from a shipped default of
50Mi × 5 — the default is a 250Mi ceiling, not "uncapped"). Opening that band matters more
than the bytes it reclaims: measured on sandbox, only **2.26 GB** of the 62.67 GB
image store is genuinely GC-eligible, because 170 of 174 images are held by
running containers.

**This reboots the node**, which is why it runs first — on a bare environment
there is nothing to disturb. It is also why it is laptop-only and has no job
template: a job running it would kill its own pod. Skip with
`-e configure_node=false` on any environment you cannot reboot right now.

It deliberately does **not** touch the apiserver audit profile. Disabling audit
would reclaim a further ~3.36 GB, and that trade — an ephemeral demo cluster's
API audit trail for disk — was declined (#796). Do not add it back without
revisiting that decision.

**2. Persist the cluster monitoring storage** (`configure_monitoring.yml`)

Stock OpenShift puts the cluster Prometheus TSDB on an **emptyDir** with 15 days
of retention and no size cap. On a single-node cluster with one ~107 GB disk
that grows into ~10 GB of the same filesystem the kubelet's 85% eviction
threshold watches — measured at 9.4% of the whole disk on sandbox, and the
reason jobs 591, 593 and 638 were evicted (#782, #793).

Creates the `cluster-monitoring-config` ConfigMap with a `volumeClaimTemplate`
on the cluster's own StorageClass (discovered at run time, the same way CNV's
scratch space is) plus a `retentionSize` cap, then waits until the running pod's
volume is genuinely a PVC rather than trusting the recap.

**Runs first on purpose.** On a fresh environment the TSDB is minutes old, so
the switch is instant and nothing of value is lost — and every stage after it
installs onto a node that is not already carrying 10 GB it does not need to. On
an environment that has been up for a week it costs the existing history, so run
it away from a demo. Skippable with `-e configure_monitoring=false`. Reversible
with `-e monitoring_state=absent`.

**3. Install OpenShift Virtualization** (`install_cnv.yml`)

1. Creates the `openshift-cnv` namespace and its OperatorGroup.
2. Subscribes to `kubevirt-hyperconverged` on the `stable` channel from the
   `redhat-operators` catalog.
3. Waits for the operator ClusterServiceVersion to reach `Succeeded`.
4. Creates the `HyperConverged` CR, pointing CDI scratch space at the
   cluster's default StorageClass (discovered at run time).
5. Waits for `HyperConverged` to report `Available`, then for the `rhel9`
   boot-source DataSource to be `Ready`.

**4. Link the RHEL 9 CIS L1 golden image** (`link_rhel9_image.yml`)

Creates a DataImportCron for rhel9-cis-l1 alongside the stock rhel9. Skippable
with `-e link_rhel9_image=false`.

**5. Link the Windows golden image** (`link_windows_image.yml`)

Creates a DataImportCron for win2k22 and imports via an explicit DataVolume.
Needs the quay credentials (private repository). Skippable with
`-e link_windows_image=false`.

**6. Ensure shared cluster objects** (`ensure_shared_objects.yml`)

VM namespace, Terraform state namespace, and the sd1.* instance type catalog
(#351, #530). Without this, nightly teardown schedules fail on a new cluster.

**7. Apply the AAP configuration** (`config.yml`)

Organization, project, credentials, both inventories and their sync, the job
templates and their surveys, the nightly teardown schedules, and the execution
environment — mirrored from quay into *this environment's* Private Automation
Hub, so the demo does not depend on quay.io at run time.

**8. Deploy the AAP MCP server** (`mcp_server.yml`)

So a new environment arrives with the MCP server already on rather than needing
a second visit. Write posture comes from the environment's own group_vars.

**9. Install Automation Orchestrator** (`install_ao.yml`)

Installs AO and the PostgreSQL it cannot run without, via CloudNativePG. Default
on, skipped with `-e install_ao=false`.

**10. Configure Automation Orchestrator** (`configure_ao.yml`)

Connects AO to AAP — OIDC SSO and the AAP integration so AO can see job
templates. Gated on the same `install_ao` flag.

**11. Deploy the self-service portal** (`portal.yml`)

Helm chart, gateway OAuth app, org sync. Default on, skipped with
`-e install_portal=false`. Needs AAP configured first (stage 6), does not depend
on AO.

**12. Generate the environment URL reference** (`generate_env_urls.yml`)

Regenerates the env-urls file with credentials included (setup.yml is always a
laptop command with the vault available).

**13. Probe the environment** (`probe_env.yml`)

Measures CPU, memory, and storage now that everything is installed. Recommends
`available_memory_gb` under full load (AO, portal, MCP server all running).
Strictly read-only (#100).

**14. Prove it** (`prepare_env.yml`)

Checks the boot source is genuinely backed by a ready snapshot, that storage
clones with `csi-clone` rather than copying, and that ingress admits Routes —
then builds one real VM, times it, and destroys it.

## How long

**Roughly 40-50 minutes**: about 5-10 for the node tuning reboot, about 2 for the monitoring storage switch,
about 4 for CNV, 1-2 for the RHEL 9 golden image
import, about 7-10 for the Windows golden image import, a few for shared
objects, several for the AAP objects and the first Hub image mirror, about 1
for the MCP server, about 5 for AO and its database, about 2 to configure AO,
about 5-10 for the portal, about 1 for env URLs, about 1 for the probe, and
about 1 to verify. That is on top of RHDP provisioning the environment itself,
so **budget ~50-60 minutes from ordering an environment to demoing on it**.

A timing summary is printed at the end of the run showing per-stage elapsed
times and a total.

## Each stage is still runnable on its own

`setup.yml` is a convenience, not a bottleneck:

- `configure_monitoring.yml` — only the monitoring storage needs fixing
- `install_cnv.yml` — only a cluster needs CNV
- `link_rhel9_image.yml` — only the RHEL 9 golden image needs linking
- `link_windows_image.yml` — only the Windows golden image needs linking
- `ensure_shared_objects.yml` — only the shared objects need creating
- `config.yml` — only the AAP objects changed
- `mcp_server.yml` — only the MCP server needs redeploying
- `install_ao.yml` — only AO needs installing
- `configure_ao.yml` — only AO needs reconfiguring
- `portal.yml` — only the portal needs redeploying
- `generate_env_urls.yml` — only the URL reference needs refreshing
- `probe_env.yml` — re-measure `available_memory_gb` after workload changes
- `prepare_env.yml` — re-check an environment that has been sitting idle
  (this one has its own skill, `sales-demos-verify-env`)

## What it does not do

It does **not** enable hugepages, KSM, or workload partitioning.

This used to say "each of those writes a MachineConfig and reboots the node, and
AAP runs on the only node, so a reboot would take the demo down mid-install".
Stage 1 now writes a MachineConfig and reboots deliberately (#796), so the reason
has changed rather than disappeared: a reboot is acceptable as the **first** step
on a bare environment, and unacceptable once AAP, the portal and the demo VMs are
up. Anything that reboots belongs in stage 1 or nowhere.

It does **not** disable apiserver audit logging. That would reclaim ~3.36 GB, and
it was declined in favour of keeping the audit trail (#796).

It does **not** create Automation Hub credentials in AAP, and that is
deliberate. AAP would use them to install `collections/requirements.yml` at
project sync, and the execution environment already carries every pinned
collection (#31). Verified on the live sandbox: no organization has a Galaxy
credential, the sync's collection play reports `ok=3, changed=0`, and job
templates run green anyway. Adding one would only make every sync re-install
what is already baked in.

## Preflight Check

```bash
./utilities/preflight.sh "${ENV:-sandbox}" --k8s
```

If any check fails, stop and tell the user exactly which one and the fix shown
beside it. Do not attempt the run with a failing prerequisite.

## Confirm the cluster actually needs this

CNV may already be installed. Check before running — the playbook is
idempotent, but 30-35 minutes of waiting is not worth spending on a no-op.

**Each value comes from where it actually lives, and they are two different
places.** `openshift_api_url` is plaintext in `inventory/group_vars/<env>/`, so
an ad-hoc `ansible` call resolves it and the `--limit` proves the environment
selection at the same time. `openshift_api_token` is **not** reachable that way:
it comes from `env_secrets` in `playbooks/group_vars/all/secrets.yml`, and
Ansible loads a `group_vars/` directory adjacent to the **inventory** or to a
**playbook** — an ad-hoc command has no playbook, so that file is never loaded
and the lookup fails with `'env_secrets' is undefined` (#86). Read it through
the vault instead, the same way `README.md` does.

```bash
ENV=${ENV:-sandbox}
VAULT_ID="sales.demos@$HOME/secrets/.vault_pass_sales_demos"

# Plaintext, and next to the inventory: ad-hoc ansible resolves it.
OCP_URL=$(ansible -i inventory --limit "$ENV" aap -m debug --vault-id "$VAULT_ID" \
  -a 'msg={{ openshift_api_url }}' 2>/dev/null \
  | sed -n 's/.*"msg": "\(.*\)"/\1/p')

# Vaulted, and next to the PLAYBOOKS: read it through the vault.
OCP_TOKEN=$(ansible-vault view playbooks/group_vars/all/secrets.yml \
  --vault-id "$VAULT_ID" 2>/dev/null \
  | ENV="$ENV" python3 -c \
    'import sys,yaml,os; print(yaml.safe_load(sys.stdin)["env_secrets"][os.environ["ENV"]]["openshift_api_token"])')

export OCP_URL OCP_TOKEN

# CHECK THE SHAPE, NOT JUST THAT SOMETHING CAME BACK. `-m debug` prints its
# errors into the same "msg" field this scrapes, so a failed lookup yields the
# error TEXT — non-empty, and a plain `test -n` called that success while the
# token was the string "The task includes an option with an undefined
# variable..". That is what made #86 fail forty seconds later as a confusing
# 401 instead of failing here.
case "$OCP_URL" in https://*) ;; *) echo "could not resolve $ENV API URL — check --limit"; esac
case "$OCP_TOKEN" in
  sha256~*) echo "resolved $ENV credentials (OAuth token)" ;;
  eyJ*.*.*)  echo "resolved $ENV credentials (ServiceAccount token)" ;;
  *) echo "could not resolve $ENV token — check the vault password and that env_secrets.$ENV exists" ;;
esac
```

```bash
python3 - <<'PY'
import os, ssl, json, urllib.request
ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
req = urllib.request.Request(os.environ["OCP_URL"].rstrip("/") + "/apis",
                             headers={"Authorization": "Bearer " + os.environ["OCP_TOKEN"]})
groups = [g["name"] for g in json.load(urllib.request.urlopen(req, context=ctx, timeout=20))["groups"]]
print("CNV already installed" if "kubevirt.io" in groups else "CNV NOT installed — run the playbook")
PY
```

## Collect inputs

| Variable | Default | Meaning |
|---|---|---|
| `ENV` (inventory limit) | `sandbox` | Which environment to target — `sandbox`, `demo`, or `edge` |
| `install_ao` | `true` | Set to `false` to skip both AO stages (9 and 10) |
| `install_portal` | `true` | Set to `false` to skip the portal deploy (stage 11) |
| `link_rhel9_image` | `true` | Set to `false` to skip the RHEL 9 golden image import (stage 4) |
| `link_windows_image` | `true` | Set to `false` to skip the Windows golden image import (stage 5) |
| `configure_monitoring` | `true` | Set to `false` to leave the cluster Prometheus on its stock node-local emptyDir (stage 2) |
| `configure_node` | `true` | Set to `false` to skip the kubelet disk tuning (stage 1) — **and its node reboot** |

Credentials are included in env-urls by default (#565). setup.yml is always a
laptop command with the vault available, so no extra-var is needed.

Everything else is resolved for you: hostname and API URL from that
environment's committed `connection.yml`, credentials from the environment's
slice of the vault-encrypted `playbooks/group_vars/all/secrets.yml`, StorageClass and
channel discovered on the cluster. Do not prompt for a token and never pass one
on the command line; that would put it in shell history.

## Run

```bash
mkdir -p ~/ansible-logs
export ANSIBLE_LOG_PATH=~/ansible-logs/sales-demos-setup-sandbox-$(date +%F-%H%M).log

./utilities/run-ansible.sh playbooks/setup.yml -i inventory --limit sandbox -e target_env=sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

**Always set `ANSIBLE_LOG_PATH`** — this run takes 30-35 minutes and the log is
the only evidence left if it fails. Logs live outside the repo, in
`~/ansible-logs/`. Tell the user the path so they can find it later.

**Never pipe the run through `tee`.** In a pipeline the exit status comes from
`tee`, not `ansible-playbook`, so a failed run reports success — this caused a
real misread during Phase 0.

**`--limit` is mandatory.** The play targets `hosts: aap`, so without a limit it
matches every environment at once; it asserts on that and fails closed rather
than configuring sandbox and demo in the same run. Passing `target_env` as well
makes the play verify the inventory resolved to the environment you meant, and
fail loudly if not — cheap insurance against applying to the wrong cluster.

Tell the user this takes 30-35 minutes and stream the output. The play is
idempotent — a re-run against an installed cluster is safe.

Optional overrides, if the user has a reason:

```bash
# Skip the portal and AO (fastest path — just CNV + AAP config + verify)
./utilities/run-ansible.sh playbooks/setup.yml -i inventory --limit sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos \
  -e target_env=sandbox -e install_ao=false -e install_portal=false

# Skip the node tuning reboot (use on any environment you cannot take down now)
./utilities/run-ansible.sh playbooks/setup.yml -i inventory --limit sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos \
  -e target_env=sandbox -e configure_node=false

# Pin scratch space to a specific StorageClass instead of the cluster default
./utilities/run-ansible.sh playbooks/setup.yml -i inventory --limit sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos \
  -e target_env=sandbox -e cnv_storage_class=<storageclass-name>

# Skip the boot-source wait (returns as soon as the operator is Available)
./utilities/run-ansible.sh playbooks/setup.yml -i inventory --limit sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos \
  -e target_env=sandbox -e cnv_wait_for_datasource=false
```

## Verify it in the EE before merging a change

See `/sales-demos-verify-ee` for why and how. The one command:

```bash
utilities/run-in-ee.sh --with-hub-token playbooks/setup.yml \
  -i inventory --limit sandbox -e target_env=sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

## Verify on the cluster

**A green playbook run is not proof.** Do not report success on the recap alone
— ask the cluster. During Phase 0 the CI lint gate passed twice while the
playbook was broken in two different ways; only running it and then checking
the cluster caught either one.

Ask the cluster over MCP — no credentials to export, no urllib:

```
# 1. CNV API groups present
mcp__openshift-<env>__resources_list  apiregistration.k8s.io/v1 APIService
# Look for kubevirt.io, cdi.kubevirt.io, hco.kubevirt.io, instancetype.kubevirt.io

# 2. Instance types match the t-shirt sizing
mcp__openshift-<env>__resources_list  instancetype.kubevirt.io/v1beta1 VirtualMachineClusterInstancetype
# Expect u1.small (1 cpu, 2Gi), u1.medium (1 cpu, 4Gi), u1.large (2 cpu, 8Gi)

# 3. KVM device available on at least one node
mcp__openshift-<env>__nodes_top
# Check allocatable devices.kubevirt.io/kvm in node details
```

If the MCP server is not registered, run `/sales-demos-mcp` first.

The instance-type shapes are checked because the t-shirt sizing tiers in
the [OCP Virt plan](https://ericcames.github.io/sales.demos-docs/plan/ocpvirt-demo-plan/) depends on them. If they ever differ, Phase 1
sizing is wrong and the plan doc needs updating — say so rather than working
around it.

## When it finishes

The playbook prints a **timing summary** at the end showing per-stage elapsed
times and a total. Report that summary, the verification result above, then tell
the user the cluster is ready for provisioning —
[`/sales-demos-provision`](https://github.com/ericcames/sales.demos/blob/main/.claude/skills/sales-demos-provision/SKILL.md)
builds t-shirt-sized VMs, or run the `Cluster Day 0` workflow from AAP.

## If it fails

| Symptom | Cause | Fix |
|---|---|---|
| `401` / `Unauthorized` on the first task | RHDP bearer token expired — they are short-lived | Get a fresh token from the OpenShift console (*Copy login command*), then `ansible-vault edit playbooks/group_vars/all/secrets.yml --vault-id sales.demos@~/secrets/.vault_pass_sales_demos` and update `env_secrets.<env>.openshift_api_token` |
| `Attempting to decrypt but no vault secrets found` | `--vault-id` missing from the command | Add `--vault-id sales.demos@~/secrets/.vault_pass_sales_demos` |
| `Decryption failed` | Wrong or missing vault password file | Confirm `~/secrets/.vault_pass_sales_demos` exists and is the password the file was encrypted with |
| ClusterServiceVersion never reaches `Succeeded` | Catalog source not ready, or no `kubevirt-hyperconverged` in `redhat-operators` | `oc get packagemanifest kubevirt-hyperconverged -n openshift-marketplace` |
| DataSource `rhel9` never Ready | CDI still importing, or no default StorageClass | Re-run; or pass `-e cnv_wait_for_datasource=false` and check `oc get datavolume -n openshift-virtualization-os-images` |
| `no default StorageClass` assertion | Cluster has none annotated default | Pass `-e cnv_storage_class=<name>` |
| Portal Helm deploy hangs | Operator or pull-secret issue | Pass `-e install_portal=false` to skip; run `portal.yml` separately later |
| AO install hangs | Operator marketplace slow | Pass `-e install_ao=false` to skip; run `install_ao.yml` separately later |
| EE sync timeout | Fresh quay registry on a new cluster | Already mitigated: #547 increased polling to 120 retries x 2s = 4 minutes |

Never paste a live cluster hostname or token into a commit message, issue, or
PR. This repo is public — see `CLAUDE.md`.
