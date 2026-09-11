---
name: ocpvirt-new-env
description: "Verify a fresh RHDP environment is genuinely demo-ready before anyone watches — boot sources actually imported, storage on the fast clone path, ingress admitting Routes — then build one real VM, time it, and destroy it. Runs playbooks/prepare_env.yml. TRIGGER when: the user has a new or rebuilt RHDP environment, asks whether an environment is ready or warm, says VM creation is slow, or is about to demo on a cluster nobody has built a VM on yet. SKIP: if OpenShift Virtualization is not installed at all — that is Phase 0, ocpvirt-setup — or if the user wants to provision demo VMs to keep, which is ocpvirt-provision."
---

# ocpvirt-new-env

## There is an AAP path now too (#330)

`Cluster Day 0 - 2 Verify Environment` runs this same playbook from AAP, and is
the last node of the `Cluster Day 0` workflow. The skill remains the quicker
loop when iterating locally.

Answers one question: **would a live VM build in front of a customer be fast?**

Run this after `ocpvirt-setup` on a new environment, and before promising anyone
a live build.

## How long a fresh environment actually takes

Measured end to end on a brand-new RHDP environment (#30, #39):

| Step | Fresh environment | Warm environment |
|---|---|---|
| `ocpvirt-setup` — install CNV | **~4 min** | already done |
| **This skill** — verify and time a build | **~2 min** | ~2 min |
| — of which the VM build itself | **44s** | 45s |

**Budget roughly 20 minutes from a bare RHDP environment to a demo you would
run in front of someone**, most of which is provisioning the environment itself
before any of this starts.

**A fresh cluster is usually already warm.** All six boot-source VolumeSnapshots
were `readyToUse` before CNV finished installing — the import runs alongside the
install, so `ocpvirt-setup` returning generally means you are ready. The often
repeated "5m47s cold versus ~30s warm" figure is a real measurement of a VM
build, but it did **not** reproduce on a genuinely fresh environment; it almost
certainly came from building immediately after install and catching the import
mid-flight.

Which is the point: this skill exists to **prove** readiness in about a minute
rather than assume it, and to name the specific reason when an environment is
not ready.

## Why each check exists

Every one corresponds to a way an environment looks fine and is still slow:

| Check | The failure it catches |
|---|---|
| `rhel9` DataSource `Ready=True` | Boot source never imported |
| **The VolumeSnapshot behind it is `readyToUse`** | DataSource reports Ready while the snapshot is still materializing — the actual slow-build state |
| StorageProfile `cloneStrategy: csi-clone` | `copy` or host-assisted means every create pays a full disk copy, and no amount of warming helps |
| IngressController Available | Routes for demo web access (#29) are never admitted |
| **A real VM built and timed** | Everything above passing while the cluster still cannot make a VM |

That third row is the big lever. On RHDP the default StorageClass should be the
ceph-rbd one; **noobaa reports `copy`** and will make every build slow.

## Preflight Check

```bash
./utilities/preflight.sh "${ENV:-sandbox}"
```

## Run

```bash
ansible-playbook playbooks/prepare_env.yml -i inventory --limit sandbox \
  -e target_env=sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

It creates a VM in its own `sales-demos-smoke` namespace, waits for `Running`,
reports the time, and deletes the namespace in an `always:` block — so a failed
or slow run does not leave a VM eating the memory budget the real demo needs.

## Verify it in the EE before merging a change

See `/sales-demos-verify-ee` for why and how. The one command:

```bash
utilities/run-in-ee.sh playbooks/prepare_env.yml \
  -i inventory --limit sandbox -e target_env=sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

## Reading the result

- **`WARM — this environment is demo-ready`** (≤120s) — go.
- **`SLOW`** — every readiness check passed but the build was still slow, which
  almost always means the boot source is still settling. **Wait a few minutes
  and re-run.** Do not raise the threshold to make it pass; that only moves the
  surprise to the demo.
- **Fails on `cloneStrategy`** — the default StorageClass is wrong for this
  cluster. This one will not fix itself with time.
- **Fails on CNV** — Phase 0 has not run. Use `ocpvirt-setup`.

Raise the bar only deliberately:

```bash
  -e prep_warm_threshold_seconds=180
```

## Verify against the cluster, not the recap

```
mcp__openshift-<env>__resources_get  cdi.kubevirt.io/v1beta1 DataSource rhel9
  namespace: openshift-virtualization-os-images

mcp__openshift-<env>__resources_list  snapshot.storage.k8s.io/v1 VolumeSnapshot
  namespace: openshift-virtualization-os-images

mcp__openshift-<env>__resources_get  storage.k8s.io/v1 StorageProfile <default-storageclass>
# Check status.cloneStrategy — must be csi-clone, not copy

mcp__openshift-<env>__resources_list  v1 Namespace
  fieldSelector: metadata.name=sales-demos-smoke
# Should return empty — the smoke namespace is cleaned up
```

## A fresh environment, start to finish

1. Paste the new URLs into that environment's `connection.yml` (RHDP URLs are
   committed in the clear on purpose) and put the token and password in the
   vault under `env_secrets.<env>`.
2. `ocpvirt-setup` — runs `setup.yml`, which installs CNV, links the RHEL 9
   golden image, applies the AAP config, deploys the MCP server, installs AO,
   and **runs this skill's playbook** (`prepare_env.yml`) as its final stage.
   After this, the environment is demo-ready for Linux.
3. `playbooks/link_windows_image.yml` — if the environment needs Windows demos.
4. `ocpvirt-provision` — build the demo VMs.
