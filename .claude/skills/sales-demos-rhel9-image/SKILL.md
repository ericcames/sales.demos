---
name: sales-demos-rhel9-image
description: "Point this environment's OpenShift Virtualization at the published CIS L1 hardened RHEL 9 golden containerdisk. Creates a DataImportCron that populates the rhel9-cis-l1 DataSource alongside the stock rhel9, so Terraform clones the hardened image by default. No pull secret needed — the quay repo is public. Fully reversible. Runs playbooks/link_rhel9_image.yml. TRIGGER when: the user asks to enable or update the hardened RHEL 9 image, wants to repoint to a new RHEL 9 golden image tag, says VMs are booting the stock RHEL 9 cloud image instead of the hardened one, asks about the rhel9-cis-l1 DataSource, or asks about issue #202. SKIP: if the user wants the WINDOWS golden image — that is sales-demos-windows-image — or wants to BUILD the golden image, which is ericcames/image.builder.pipeline."
---

# sales-demos-rhel9-image

Links an environment to the published RHEL 9 CIS L1 hardened golden image.
Takes about **2 minutes** for the cron to import and the DataSource to report
Ready.

This skill contains **no logic**. All the work is in
[`playbooks/link_rhel9_image.yml`](../../../playbooks/link_rhel9_image.yml).

## What it does

1. Reads the HyperConverged CR and asserts CNV is installed.
2. Adds a `rhel9-cis-l1-image-cron` DataImportCron template to the
   HyperConverged CR, pointing at the containerdisk in `quay_rhel9_image`.
3. Waits for the `rhel9-cis-l1` DataSource to report `Ready=True`.
4. Verifies the backing volume (VolumeSnapshot or PVC) is usable.
5. Reports the result.

## This is the consumer half. It does not build anything.

| | Owns |
|---|---|
| **This skill** | Pointing a cluster at the published image |
| The producer (`ericcames/image.builder.pipeline`) | Building and publishing the containerdisk |

The contract between them is one string: `quay_rhel9_image` in
`inventory/group_vars/<env>/connection.yml`. The playbook asserts it is
non-empty and rejects placeholder values.

## No pull secret needed

The quay repository is **public** (#208), so CDI pulls the image without
credentials. This is the key difference from the Windows twin
(`sales-demos-windows-image`), which needs a pull secret because Windows media
cannot be redistributed publicly.

## Why a separate DataSource

The stock `rhel9` DataSource is managed by CNV's built-in DataImportCron, which
pulls the vanilla RHEL 9 cloud image from Red Hat's registry. Overwriting it
would break anyone who expects the stock image. `rhel9-cis-l1` is ours to
manage — it coexists alongside `rhel9`, and Terraform defaults
`linux_datasource_name` to it.

## Preflight Check

```bash
./utilities/preflight.sh "${ENV:-sandbox}" --k8s

grep -h '^quay_rhel9_image' inventory/group_vars/*/connection.yml
```

If any check fails, stop and tell the user exactly which one and the fix shown
beside it. Do not attempt the run with a failing prerequisite.

## Collect inputs

| Variable | Default | Meaning |
|---|---|---|
| `ENV` (inventory limit) | `sandbox` | Which environment to target — `sandbox`, `demo`, or `edge` |

To repoint to a new image tag, update `quay_rhel9_image` in
`inventory/group_vars/<env>/connection.yml` first. Tags are immutable —
**repoint, never overwrite**.

## Run

```bash
ansible-playbook playbooks/link_rhel9_image.yml -i inventory --limit sandbox \
  -e target_env=sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

And the reversal:

```bash
ansible-playbook playbooks/link_rhel9_image.yml -i inventory --limit sandbox \
  -e target_env=sandbox -e rhel9_image_link_state=absent \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

`absent` removes the cron template from the HyperConverged CR; CDI garbage
collection removes the `rhel9-cis-l1` DataSource. The stock `rhel9` is
unaffected.

**Never pipe the run through `tee`.** In a pipeline the exit status comes from
`tee`, not `ansible-playbook`, so a failed run reports success.

## Verify it in the EE before merging a change

See `/sales-demos-verify-ee` for why and how. The one command:

```bash
utilities/run-in-ee.sh playbooks/link_rhel9_image.yml \
  -i inventory --limit sandbox -e target_env=sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

## Verify against the cluster, not the recap

**A green playbook run is not proof.** And `Ready=True` alone is not the check —
a DataSource stays Ready for ever once populated, whatever `quay_rhel9_image` is
later set to (#358). Ask what is actually served:

```
mcp__openshift-<env>__resources_get  cdi.kubevirt.io/v1beta1 DataSource rhel9-cis-l1
  namespace: openshift-virtualization-os-images
```

Confirm `Ready=True`, then check the identity — the source registry URL must
match `quay_rhel9_image` from this environment's `connection.yml`:

```
mcp__openshift-<env>__resources_list  cdi.kubevirt.io/v1beta1 DataImportCron
  namespace: openshift-virtualization-os-images
```

Look for `rhel9-cis-l1-image-cron` and verify its
`spec.template.spec.source.registry.url` equals
`docker://<quay_rhel9_image>`.

Also confirm the HyperConverged CR carries the template:

```
mcp__openshift-<env>__resources_get  hco.kubevirt.io/v1beta1 HyperConverged kubevirt-hyperconverged
  namespace: openshift-cnv
```

Check `spec.dataImportCronTemplates` for the `rhel9-cis-l1-image-cron` entry.

## Where this sits

1. `sales-demos-setup` — runs `setup.yml`, which installs CNV **and links the
   RHEL 9 golden image** as part of the setup.
2. `sales-demos-windows-image` — fills the Windows boot source (separate, needs a
   pull secret).
3. **This skill** — runs `link_rhel9_image.yml` standalone, for repointing to a
   new tag or linking on an environment that missed the setup run.
4. `sales-demos-provision` — builds demo VMs, cloning from `rhel9-cis-l1` by
   default.

## When it finishes

Report the playbook summary **and** the MCP verification above — specifically
confirm the DataSource identity matches `quay_rhel9_image`.

## If it fails

| Symptom | Cause | Fix |
|---|---|---|
| `No HyperConverged CR` | CNV is not installed | Run `sales-demos-setup` first |
| `quay_rhel9_image must name a real published containerdisk` | Image reference empty or placeholder in `connection.yml` | Set it to a real tag, e.g. `quay.io/zigfreed/rhel9-cis-l1-golden:20260905-0411` |
| DataSource never reaches Ready | CDI importer failed to pull | Check the importer pod in `openshift-virtualization-os-images` for pull errors |
| Ready, but the backing volume never becomes usable | Snapshot still materializing | Wait — this is the slow-build case `sales-demos-verify-env` exists to catch |
| `401` / `Unauthorized` | RHDP bearer token expired | Refresh `openshift_api_token` in the vault, re-run `make-kubeconfig.sh` |
| `Attempting to decrypt but no vault secrets found` | `--vault-id` missing from the command | Add `--vault-id sales.demos@~/secrets/.vault_pass_sales_demos` |

Never paste a live cluster hostname or token into a commit message, issue, or
PR. This repo is public — see `CLAUDE.md`.
