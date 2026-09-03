---
name: sales-demos-probe-env
description: "Measure what a cluster actually has — allocatable, what is already requested, what is genuinely free — and emit a recommended available_memory_gb instead of trusting a hardcoded one. Strictly read-only, so it is safe mid-demo. Runs playbooks/probe_env.yml. TRIGGER when: the user asks how much room a cluster has, whether an add-on or another VM will fit, why Terraform refuses a tier, or has moved to a new or resized RHDP environment and the memory budget may be stale. SKIP: if the user is asking whether a VM build would be fast — that is ocpvirt-new-env — or if OpenShift Virtualization is not installed at all, which is ocpvirt-setup."
---

# sales-demos-probe-env

Answers one question: **what does this cluster actually have, and what will fit
on it?**

## Why this exists

`terraform/ocpvirt/variables.tf` carried `available_memory_gb = 14` as a
hardcoded guess. It was measured once, on a smaller cluster, and then outlived
it — sandbox now has roughly **five times** that free.

Nothing reported the drift, and nothing could have. The budget guard in
`locals.tf` fails *closed*: an under-provisioned figure does not error, it
quietly refuses tiers the cluster could run easily. A demo gets smaller and
nobody learns why.

The next RHDP environment will differ again. A hardcoded number is exactly what
produced the stale one, so this is re-runnable rather than a paragraph in an
issue (#100).

## It is strictly read-only

Every task is `k8s_info`. It creates nothing, deletes nothing, and a run reports
`changed=0`. **Safe to run in the middle of a live demo** when someone asks
whether the cluster can take another VM.

That is the whole reason it is a second playbook rather than a flag on
`prepare_env.yml`, which builds and destroys a real VM to do its job.

## Requests, not usage — the distinction that matters

The scheduler places pods and KubeVirt VMs against **requests**, never against
live consumption. A node can look 22% used in `oc adm top` and still refuse a VM
because requests are committed elsewhere.

Measured on sandbox 2026-09-03, the gap is not small:

| | Value |
|---|---|
| Allocatable | 124.68 GiB |
| Requested | 49.05 GiB |
| **Free by requests** | **75.63 GiB** ← what schedules |
| Free by live usage | 96.42 GiB ← informational only |

Both are printed side by side so nobody optimises against the wrong one.

Two accounting rules are applied, and either one wrong makes the answer
disagree with `oc describe node`:

- **A pod reserves `max(sum(containers), max(initContainers))`**, not the sum of
  everything — init containers run to completion before app containers start.
- **Only pods with `spec.nodeName` hold capacity.** An unscheduled `Pending`
  pod reserves nothing. On sandbox two `openshift-storage` ctrlplugin pods sit
  Pending unscheduled; counting them inflated the total by 1.56 GiB. They are
  reported on their own line instead.

## Preflight Check

```bash
# 1. Which environment, and is it the one you mean?
grep -h '^aap_env_name\|^openshift_api_url' \
  inventory/group_vars/sandbox/connection.yml inventory/group_vars/demo/connection.yml

# 2. The vault password, or nothing decrypts
test -r ~/secrets/.vault_pass_sales_demos \
  && echo "✅ vault password present" || echo "❌ ~/secrets/.vault_pass_sales_demos missing"

# 3. Is the environment even up? (RHDP environments expire silently)
curl -sk -o /dev/null -w "API: %{http_code}\n" \
  "$(grep '^openshift_api_url' inventory/group_vars/sandbox/connection.yml | cut -d'"' -f2)/version"
```

## Run

```bash
ansible-playbook playbooks/probe_env.yml -i inventory --limit sandbox \
  -e target_env=sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

Raise or lower the headroom it withholds from the recommendation:

```bash
  -e probe_safety_margin_gb=4
```

The margin exists because a budget that consumes every free byte schedules a VM
onto a node with no room to reschedule a control-plane pod.

## Reading the result

- **`RECOMMENDED available_memory_gb = <n>`** — compare against the default in
  `terraform/ocpvirt/variables.tf`. If it differs materially, that variable is
  stale. Changing it is a behaviour change (it changes which tiers `plan`
  accepts), so it ships as its own PR, not silently.
- **`FITS — with room to spare`** — the candidate add-ons in
  `inventory/group_vars/aap/probe_workloads.yml` all fit. **Those are estimates**;
  each carries a `source:` saying so. Replace them with measurements as add-ons
  get installed.
- **`CNV: NOT INSTALLED`** — Phase 0 has not run. Use `ocpvirt-setup`.
- **`Unscheduled: n pod(s)`** — informational. Persistent unscheduled pods on a
  single-node cluster usually want more nodes than exist and will stay Pending.

## Verify against the cluster, not the recap

The acceptance test is agreement with the node's own accounting. If the probe
disagrees with these, **the playbook is wrong, not the cluster**:

```bash
oc describe node <node> | grep -A8 'Allocated resources'   # must match REQUESTED
oc adm top node                                            # must match LIVE USE
oc get packagemanifest -n openshift-marketplace | grep -E 'mcp-gateway|orchestrator'
```

Verified 2026-09-03 on sandbox: probe reported `14.5 vCPU / 49.05 GiB`
requested against `oc describe node`'s `14500m / 50231Mi`. Exact match.
