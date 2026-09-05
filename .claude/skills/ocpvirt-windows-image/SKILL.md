---
name: ocpvirt-windows-image
description: "Point this environment's OpenShift Virtualization at the published Windows golden containerdisk, so os_type=windows actually boots instead of hanging on an empty boot source. Adds a DataImportCron to the HyperConverged CR and a pull secret for the private quay repository, then asks the cluster whether the DataSource really came up. Fully reversible. Runs playbooks/link_windows_image.yml. TRIGGER when: the user asks to enable or fix Windows VMs, says a Windows VM will not boot or sits forever in Provisioning, asks why win2k22 is not Ready, wants the Windows boot source populated, asks about issue #3, or wants to undo that link. SKIP: if the user wants to BUILD or publish the golden image itself — that is ericcames/image.builder.pipeline#24, a separate producer — or wants to provision demo VMs generally, which is ocpvirt-provision."
---

# ocpvirt-windows-image

Answers one question: **why does `os_type=windows` create a VM that never boots?**

Because CNV ships `win2k22` as an empty placeholder. Red Hat cannot redistribute
Windows media, so every `win*` DataSource on a fresh cluster reports
`Ready=False`, `"PVC not found"`. Terraform clones that DataSource, so the VM is
created and then waits forever on a DataVolume that never imports.

This skill fills it, the same way CNV fills `rhel9`.

## This is the consumer half. It does not build anything.

| | Owns | Issue |
|---|---|---|
| **This skill** | Pointing a cluster at a published image | #3 |
| The producer | Building and publishing the containerdisk | ericcames/image.builder.pipeline#24 |

The contract between them is one string: `quay_windows_image` in
`inventory/group_vars/<env>/connection.yml`. **Until ericcames/image.builder.pipeline#24 publishes a real image
that value is a `quay.io/<user>/windows2k22-golden:<date>` placeholder and the
playbook refuses to run** — deliberately, because a DataImportCron pointed at a
nonexistent repository fails in an importer pod, not at link time.

## Why a DataImportCron and not a PVC

#3 originally said "snapshot the disk to a DataSource". That is not how boot
sources are kept on a cluster, and the cluster is the proof. Measured on sandbox,
CNV 4.20.24 — `HyperConverged.status.dataImportCronTemplates` carries six
entries, fedora / centos-stream 9,10 / rhel 8,9,10, each with
`managedDataSource`, `garbageCollect: Outdated` and a registry source.

A hand-created PVC is a one-shot artifact with no refresh path. A cron makes a
fresh RHDP environment a *config* step instead of a data-movement one.

**Taking over the SSP placeholder is the designed handoff, not a fight:**

| | `win2k22` (placeholder) | `rhel9` (managed) |
|---|---|---|
| `managed-by` | `ssp-operator` | `cdi-controller` |
| `dataImportCron` label | absent | `rhel9-image-cron` |
| `spec.source` | `pvc {name: win2k22}` | `snapshot {name: rhel9-…}` |
| Ready | `False` — "PVC not found" | `True` |

SSP creates the placeholder; the cron takes ownership, relabels it, and rewrites
`spec.source` from `pvc` to `snapshot`.

The six built-in templates are **not** at risk: `spec.dataImportCronTemplates` is
empty on a stock cluster — they live in HCO itself and appear only in `status`,
flagged `commonTemplate: true`. Custom entries coexist.

## Preflight Check

```bash
# 1. Which environment, and is it the one you mean?
grep -h '^aap_env_name\|^openshift_api_url' \
  inventory/group_vars/sandbox/connection.yml inventory/group_vars/demo/connection.yml

# 2. The vault password, or nothing decrypts
test -r ~/secrets/.vault_pass_sales_demos \
  && echo "✅ vault password present" || echo "❌ ~/secrets/.vault_pass_sales_demos missing"

# 3. Is there an image to point at yet? A '<user>' here means ericcames/image.builder.pipeline#24 has not landed.
grep -h '^quay_windows_image' inventory/group_vars/*/connection.yml

# 4. Is the environment up? (RHDP environments expire)
curl -sk -o /dev/null -w "API: %{http_code}\n" \
  "$(grep '^openshift_api_url' inventory/group_vars/sandbox/connection.yml | cut -d'"' -f2)/version"
```

`quay_username` and `quay_password` come from the vaulted
`playbooks/group_vars/all/secrets.yml`; the playbook asserts both and rejects
`CHANGEME`.

## Run

```bash
ansible-playbook playbooks/link_windows_image.yml -i inventory --limit sandbox \
  -e target_env=sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

And the reversal, which ships in the same change because this touches a
cluster-wide boot source:

```bash
ansible-playbook playbooks/link_windows_image.yml -i inventory --limit sandbox \
  -e target_env=sandbox -e windows_image_link_state=absent \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

`absent` removes the cron template and the pull secret; `win2k22` returns to its
empty SSP placeholder state.

## Verify it in the EE before merging a change

The command above runs on your laptop, against `~/.ansible/collections` and your
system python. An AAP job template runs the same playbook inside
`sales-demos-ee`. **Those are two dependency sets and CI can see neither** — the
lint gate executes nothing. Run it in the image as well:

```bash
utilities/run-in-ee.sh playbooks/link_windows_image.yml \
  -i inventory --limit sandbox -e target_env=sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

Everything after the playbook is unchanged — the wrapper adds the image and two
read-only mounts and nothing else. Full detail: `/sales-demos-verify-ee`.

## Reading the result

| Symptom | Cause | What to turn |
|---|---|---|
| Fails at the `quay_windows_image` assert | No image published yet, value still `<user>`/`<date>` | ericcames/image.builder.pipeline#24. Nothing to do here. |
| DataSource never reaches Ready | The importer cannot pull | Check the importer pod in `openshift-virtualization-os-images`; a private-repo auth failure surfaces there, not in the DataSource. |
| Ready, but the backing volume never becomes usable | Snapshot still materializing | Wait. Cloning from a snapshot that is not `readyToUse` is the slow-build case `ocpvirt-new-env` exists to catch. |
| VM still will not boot after a green run | Something other than the boot source | `ocpvirt-provision`, then the VM's own events. |

## Verify against the cluster, not the recap

```bash
oc get datasource win2k22 -n openshift-virtualization-os-images
oc get volumesnapshot -n openshift-virtualization-os-images
oc get hyperconverged kubevirt-hyperconverged -n openshift-cnv \
  -o jsonpath='{.spec.dataImportCronTemplates[*].metadata.name}{"\n"}'
oc get dataimportcron -n openshift-virtualization-os-images
```

`win2k22` should report `Ready=True`, and the cron template should be listed in
`spec` alongside nothing else unless someone added another.

## Where this sits

1. `ocpvirt-setup` — installs OpenShift Virtualization.
2. `ocpvirt-new-env` — confirms the Linux boot source imported and times a build.
3. **This skill** — fills the Windows boot source, once ericcames/image.builder.pipeline#24 has published one.
4. `ocpvirt-provision` — build the demo VMs, now including `os_type=windows`.
