---
name: ocpvirt-setup
description: "Phase 0 of the sales.demos OpenShift Virtualization demo — install OpenShift Virtualization (CNV) on a fresh RHDP cluster and leave it able to create VMs. Checks prerequisites, confirms the cluster is reachable, then runs playbooks/setup.yml. TRIGGER when: the user asks to set up or prepare a new RHDP environment for the ocpvirt demo, says OpenShift Virtualization or KubeVirt is missing, hits a missing kubevirt.io API, or asks to install CNV. SKIP: if CNV is already installed and the user wants to create VMs — that is Phase 1, terraform/ocpvirt."
---

# ocpvirt-setup

Phase 0 of the OpenShift Virtualization demo. Takes a bare RHDP "Ansible
Product Demo" cluster and installs OpenShift Virtualization on it.

This skill contains **no logic**. All the work is in
[`playbooks/setup.yml`](../../../playbooks/setup.yml), which imports
`playbooks/install_cnv.yml`. The same playbook runs from an AAP job template
with survey answers mapped to the same variable names. See `CLAUDE.md` →
*Skills and playbooks*.

## What it does

1. Creates the `openshift-cnv` namespace and its OperatorGroup.
2. Subscribes to `kubevirt-hyperconverged` on the `stable` channel from the
   `redhat-operators` catalog.
3. Waits for the operator ClusterServiceVersion to reach `Succeeded`.
4. Creates the `HyperConverged` CR, pointing CDI scratch space at the
   cluster's default StorageClass (discovered at run time).
5. Waits for `HyperConverged` to report `Available`, then for the `rhel9`
   boot-source DataSource to be `Ready`.

Expect 10–20 minutes. CNV pulls several large images.

It does **not** enable hugepages, KSM, or workload partitioning. Each of those
writes a MachineConfig and reboots the node — and on this catalog item AAP runs
on the only node, so a reboot would take the demo down mid-install.

## Preflight Check

Run these before doing anything else. Every one must pass.

```bash
# 1. secrets.yml exists for the target environment (default: sandbox)
ENV=${ENV:-sandbox}
test -s "inventory/group_vars/$ENV/secrets.yml" \
  && echo "✅ secrets.yml ($ENV)" \
  || echo "❌ secrets.yml missing — cp inventory/group_vars/sandbox/secrets.yml.example inventory/group_vars/$ENV/secrets.yml"

# 2. It has real values, not the shipped placeholders
grep -qE 'openshift_api_token:.*(CHANGEME|sha256~CHANGEME)' "inventory/group_vars/$ENV/secrets.yml" \
  && echo "❌ openshift_api_token is still CHANGEME" \
  || echo "✅ openshift_api_token filled in"

# 3. It is gitignored — this repo is public
git check-ignore -q "inventory/group_vars/$ENV/secrets.yml" \
  && echo "✅ secrets.yml is gitignored" \
  || echo "❌ secrets.yml is NOT gitignored — stop, do not commit"

# 4. kubernetes.core and its python client are installed
ansible-galaxy collection list kubernetes.core 2>/dev/null | grep -q kubernetes.core \
  && echo "✅ kubernetes.core" \
  || echo "❌ kubernetes.core — ansible-galaxy collection install -r collections/requirements.yml"
python3 -c "import kubernetes" 2>/dev/null \
  && echo "✅ python kubernetes client" \
  || echo "❌ python kubernetes client — pip install kubernetes"

# 5. No project-local ansible.cfg shadowing ~/.ansible.cfg
test -f ansible.cfg \
  && echo "❌ project-local ansible.cfg present — it shadows ~/.ansible.cfg and breaks certified installs" \
  || echo "✅ no project-local ansible.cfg"
```

If any check fails, stop and tell the user exactly which one and the fix shown
beside it. Do not attempt the run with a failing prerequisite.

## Confirm the cluster actually needs this

CNV may already be installed. Check before running — the playbook is
idempotent, but 20 minutes of waiting is not worth spending on a no-op.

```bash
python3 - <<'PY'
import os, ssl, json, urllib.request, yaml
env = os.environ.get("ENV", "sandbox")
s = yaml.safe_load(open(f"inventory/group_vars/{env}/secrets.yml"))
ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
req = urllib.request.Request(s["openshift_api_url"].rstrip("/") + "/apis",
                             headers={"Authorization": "Bearer " + s["openshift_api_token"]})
groups = [g["name"] for g in json.load(urllib.request.urlopen(req, context=ctx, timeout=20))["groups"]]
print("CNV already installed" if "kubevirt.io" in groups else "CNV NOT installed — run the playbook")
PY
```

## Collect inputs

Only one input, and it has a default. Ask the user only if it is ambiguous:

| Variable | Default | Meaning |
|---|---|---|
| `ENV` (inventory limit) | `sandbox` | Which environment's `secrets.yml` to use — `sandbox` or `demo` |

Everything else — API URL, token, StorageClass, channel — comes from
`secrets.yml` or is discovered on the cluster. Do not prompt for a token and do
not pass one on the command line; that would put it in shell history.

## Run

```bash
ansible-playbook playbooks/setup.yml -i inventory --limit sandbox
```

Tell the user this takes 10–20 minutes and stream the output. The play is
idempotent — a re-run against an installed cluster is safe.

Optional overrides, if the user has a reason:

```bash
# Pin scratch space to a specific StorageClass instead of the cluster default
ansible-playbook playbooks/setup.yml -i inventory --limit sandbox \
  -e cnv_storage_class=<storageclass-name>

# Skip the boot-source wait (returns as soon as the operator is Available)
ansible-playbook playbooks/setup.yml -i inventory --limit sandbox \
  -e cnv_wait_for_datasource=false
```

## Verify on the cluster

**A green playbook run is not proof.** Do not report success on the recap alone
— ask the cluster. During Phase 0 the CI lint gate passed twice while the
playbook was broken in two different ways; only running it and then checking
the cluster caught either one.

```bash
ENV=${ENV:-sandbox} python3 - <<'PY'
import os, ssl, json, urllib.request, yaml
env = os.environ.get("ENV", "sandbox")
s = yaml.safe_load(open(f"inventory/group_vars/{env}/secrets.yml"))
base = s["openshift_api_url"].rstrip("/")
ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE

def get(path):
    req = urllib.request.Request(base + path,
                                 headers={"Authorization": "Bearer " + s["openshift_api_token"]})
    return json.load(urllib.request.urlopen(req, context=ctx, timeout=25))

ok = True

groups = {g["name"] for g in get("/apis")["groups"]}
for g in ("kubevirt.io", "cdi.kubevirt.io", "hco.kubevirt.io", "instancetype.kubevirt.io"):
    print(("PASS " if g in groups else "FAIL ") + "API group " + g)
    ok &= g in groups

want = {"u1.small": (1, "2Gi"), "u1.medium": (1, "4Gi"), "u1.large": (2, "8Gi")}
its = {i["metadata"]["name"]: (i["spec"]["cpu"]["guest"], i["spec"]["memory"]["guest"])
       for i in get("/apis/instancetype.kubevirt.io/v1beta1/virtualmachineclusterinstancetypes").get("items", [])}
for name, shape in want.items():
    got = its.get(name)
    print(("PASS " if got == shape else "FAIL ") + f"instance type {name} {got}")
    ok &= got == shape

kvm = [n["status"]["allocatable"].get("devices.kubevirt.io/kvm") for n in get("/api/v1/nodes")["items"]]
print(("PASS " if any(kvm) else "FAIL ") + f"devices.kubevirt.io/kvm on node: {kvm}")
ok &= any(kvm)

print("\nCLUSTER VERIFIED" if ok else "\nVERIFICATION FAILED - do not report success")
raise SystemExit(0 if ok else 1)
PY
```

The instance-type shapes are checked because the t-shirt sizing tiers in
`docs/plan/ocpvirt-demo-plan.md` depend on them. If they ever differ, Phase 1
sizing is wrong and the plan doc needs updating — say so rather than working
around it.

## When it finishes

Report the summary the playbook prints **and** the verification result above,
then tell the user the cluster is ready for **Phase 1** — the Terraform module
for t-shirt-sized VMs
([issue #2](https://github.com/ericcames/sales.demos/issues/2)).

## If it fails

| Symptom | Cause | Fix |
|---|---|---|
| `401` / `Unauthorized` on the first task | RHDP bearer token expired — they are short-lived | Get a fresh token from the OpenShift console (*Copy login command*) and update `openshift_api_token` in `secrets.yml` |
| ClusterServiceVersion never reaches `Succeeded` | Catalog source not ready, or no `kubevirt-hyperconverged` in `redhat-operators` | `oc get packagemanifest kubevirt-hyperconverged -n openshift-marketplace` |
| DataSource `rhel9` never Ready | CDI still importing, or no default StorageClass | Re-run; or pass `-e cnv_wait_for_datasource=false` and check `oc get datavolume -n openshift-virtualization-os-images` |
| `no default StorageClass` assertion | Cluster has none annotated default | Pass `-e cnv_storage_class=<name>` |

Never paste a live cluster hostname or token into a commit message, issue, or
PR. This repo is public — see `CLAUDE.md`.
