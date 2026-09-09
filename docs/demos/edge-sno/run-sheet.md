# Run sheet — Edge / Single Node OpenShift (Phase 3)

**This page covers Phase 3 — configuring the platform.** For the full
three-phase run sheet (build ISO, boot, configure), see the
[published guide](https://ericcames.github.io/sales.demos-docs/demos/edge-sno/run-sheet/).

Phase 3 starts after the cluster is up (`oc get nodes` shows one node Ready)
and a kubeconfig exists.

---

## Prerequisites

- [ ] Cluster is up: `oc get nodes` shows one node, `Ready`
- [ ] All four Day 0 operators show CSVs `Succeeded`:
      ```bash
      oc get csv -A
      ```
- [ ] `sales.demos` cloned and collections installed:
      ```bash
      ansible-galaxy collection install -r requirements.yml
      ```
- [ ] Vault password file at `~/secrets/.vault_pass_sales_demos`
- [ ] Secrets file created from the example:
      ```bash
      cp playbooks/group_vars/all/secrets.yml.example \
         playbooks/group_vars/all/secrets.yml
      ansible-vault encrypt playbooks/group_vars/all/secrets.yml \
        --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
      ```
- [ ] Kubeconfig generated:
      ```bash
      bash utilities/make-kubeconfig.sh edge
      ```

---

## Step 1 — Run `setup_edge.yml`

> **Note:** `install_aap.yml` is tracked in
> [#395](https://github.com/ericcames/sales.demos/issues/395). Until it ships,
> deploy AAP manually — see the
> [architecture doc](https://ericcames.github.io/sales.demos-docs/demos/edge-sno/architecture/#manual-aap-deployment)
> for the CR spec.

```bash
ansible-playbook playbooks/setup_edge.yml \
  -i inventory --limit edge \
  -e target_env=edge \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos \
  2>&1 | tee /tmp/setup-edge-$(date +%Y%m%d-%H%M).log
```

| Stage | Playbook | Time |
|---|---|---|
| 1 | `install_lvms.yml` — LVMS operator + LVMCluster CR | ~2 min |
| 2 | `install_aap.yml` — deploy AAP from operator | ~20 min |
| 3 | `install_cnv.yml` — OpenShift Virtualization | ~4 min |
| 4 | `install_compliance.yml` — Compliance Operator | ~2 min |
| 5 | `prepare_env.yml` — prove it by building a real VM | ~1 min |

---

## Step 2 — Update the vault with the AAP admin password

`install_aap.yml` prints the operator-generated admin password. Add it to
the vault:

```bash
ansible-vault edit playbooks/group_vars/all/secrets.yml \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

Set `env_secrets.edge.aap_password` to the printed value.

---

## Step 3 — Apply the AAP configuration

```bash
ansible-playbook playbooks/config.yml \
  -i inventory --limit edge \
  -e target_env=edge \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos \
  2>&1 | tee /tmp/config-edge-$(date +%Y%m%d-%H%M).log
```

This creates the organizations, credentials, projects, job templates,
inventories, and schedules — the same CaC that runs on RHDP.

---

## Step 4 — Deploy Grafana Alloy (optional)

```bash
ansible-playbook playbooks/deploy_alloy.yml \
  -i inventory --limit edge \
  -e target_env=edge \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

Requires `grafana_cloud_*` credentials in the vault.

---

## Step 5 — Provision demo VMs

Launch **Sales Demos - Build Demo VM** from AAP, or:

```bash
ansible-playbook playbooks/provision_vm.yml \
  -i inventory --limit edge \
  -e target_env=edge \
  -e os_type=linux -e vm_size_tier=large-2cpu-6gb \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

---

## Verification checklist

- [ ] `oc get nodes` shows one node, `Ready`
- [ ] `oc get csv -A` shows AAP, CNV, LVMS, Compliance operators `Succeeded`
- [ ] AAP gateway is reachable at `https://aap-aap.apps.<cluster>.<domain>`
- [ ] `Sales Demos - Build Demo VM` job template exists in AAP
- [ ] A test VM provisions and the demo page returns 200

---

## Recovery moves

| Symptom | Move |
|---|---|
| `install_lvms.yml` — PVCs stuck Pending | The LVMS partition (partition 5) was not created. Rebuild the ISO with `--disk` pointing at the correct device |
| AAP components not reaching Ready | Check events: `oc get events -n aap --sort-by=.lastTimestamp`. Storage issues are the usual cause on SNO — verify `lvms-vg1` StorageClass exists |
| `config.yml` fails with 503 | AAP is still settling after deployment. Wait 5-10 minutes and retry |

---

## Teardown

To destroy demo VMs while preserving the platform:

```bash
ansible-playbook playbooks/teardown.yml \
  -i inventory --limit edge \
  -e target_env=edge \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

Removes the VMs and deregisters them from AAP. OpenShift Virtualization, AAP,
LVMS, boot sources, and the Terraform state namespace are preserved.

---

## Presenting the demo

Once the environment is configured, present from the
[OCP Virt run sheet](../openshift-virtualization/run-sheet.md). The edge talk
track ([`talk-track.md`](talk-track.md)) adds three beats about bare metal
before you pivot to the standard OCP Virt demo.
