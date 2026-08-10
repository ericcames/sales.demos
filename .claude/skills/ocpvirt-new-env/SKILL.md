---
name: ocpvirt-new-env
description: "Verify a fresh RHDP environment is genuinely demo-ready before anyone watches — boot sources actually imported, storage on the fast clone path, ingress admitting Routes — then build one real VM, time it, and destroy it. Runs playbooks/prepare_env.yml. TRIGGER when: the user has a new or rebuilt RHDP environment, asks whether an environment is ready or warm, says VM creation is slow, or is about to demo on a cluster nobody has built a VM on yet. SKIP: if OpenShift Virtualization is not installed at all — that is Phase 0, ocpvirt-setup — or if the user wants to provision demo VMs to keep, which is ocpvirt-provision."
---

# ocpvirt-new-env

Answers one question: **would a live VM build in front of a customer be fast?**

Measured on the sandbox: **5m47s on a cold cluster, ~30s on a warm one.** That
gap is not Terraform's doing — the module is already on the fast path. The slow
case is building against a cluster whose boot source has not finished importing,
so the fix belongs in environment spin-up, not the VM definition.

Run this after `ocpvirt-setup` on a new environment, and before promising anyone
a live build.

## Why each check exists

Every one corresponds to a way an environment looks fine and is still slow:

| Check | The failure it catches |
|---|---|
| `rhel9` DataSource `Ready=True` | Boot source never imported |
| **The VolumeSnapshot behind it is `readyToUse`** | DataSource reports Ready while the snapshot is still materialising — the actual slow-build state |
| StorageProfile `cloneStrategy: csi-clone` | `copy` or host-assisted means every create pays a full disk copy, and no amount of warming helps |
| IngressController Available | Routes for demo web access (#29) are never admitted |
| **A real VM built and timed** | Everything above passing while the cluster still cannot make a VM |

That third row is the big lever. On RHDP the default StorageClass should be the
ceph-rbd one; **noobaa reports `copy`** and will make every build slow.

## Preflight Check

```bash
# 1. Which environment, and is it the one you mean?
grep -h '^aap_env_name\|^openshift_api_url' \
  inventory/group_vars/sandbox/connection.yml inventory/group_vars/demo/connection.yml

# 2. The vault password, or nothing decrypts
test -r ~/secrets/.vault_pass_sales_demos \
  && echo "✅ vault password present" || echo "❌ ~/secrets/.vault_pass_sales_demos missing"

# 3. Is the environment even up? (RHDP environments expire)
curl -sk -o /dev/null -w "API: %{http_code}\n" \
  "$(grep '^openshift_api_url' inventory/group_vars/sandbox/connection.yml | cut -d'"' -f2)/version"

# 4. CNV present? If this is empty, run ocpvirt-setup first — that is Phase 0.
echo "(the playbook asserts this and tells you, so this is only a shortcut)"
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

```bash
oc get datasource rhel9 -n openshift-virtualization-os-images
oc get volumesnapshot -n openshift-virtualization-os-images
oc get storageprofile <default-storageclass> -o jsonpath='{.status.cloneStrategy}{"\n"}'
oc get ns sales-demos-smoke   # should NOT exist — it is cleaned up
```

## A fresh environment, start to finish

1. Paste the new URLs into that environment's `connection.yml` (RHDP URLs are
   committed in the clear on purpose) and put the token and password in the
   vault under `env_secrets.<env>`.
2. `ocpvirt-setup` — installs OpenShift Virtualization.
3. **This skill** — confirms the boot source really imported and times a build.
4. `playbooks/config.yml` — applies the AAP objects for that environment.
5. `ocpvirt-provision` — build the demo VMs.
