---
name: sales-demos-orchestrator-rehearse
description: "Rehearse the Automation Orchestrator demo before presenting it — preflight every fault the first rehearsal hit (ao-worker SSRF allowlist, the workflow credential, the loaded workflow, the Windows guest, a stale windemo host), break compliance on the guest, optionally run the workflow to its approval gate, and report a finished run's per-step timings and approval record. Runs playbooks/ao_rehearse.yml. TRIGGER when: the user is about to present or rehearse the AO demo, asks whether the AO demo will work, wants the guest put into the failing state for it, wants AO run timings or an approval record for the docs, or asks about issue #623. SKIP: if the AO workflow has not been loaded — that is sales-demos-orchestrator-workflow — or AO is not configured, which is sales-demos-orchestrator-config; or if the user wants to build the workflow live on the canvas, which is the demo itself."
---

# sales-demos-orchestrator-rehearse

Gets the Automation Orchestrator demo ready and proves it will run. Takes about
**20 seconds** for the preflight and break, plus about **40 seconds** to reach
the approval with `ao_rehearse_run=true`.

This skill contains **no logic**. All the work is in
[`playbooks/ao_rehearse.yml`](../../../playbooks/ao_rehearse.yml). See
`CLAUDE.md` → *Skills and playbooks*.

## Why this exists

Before the first rehearsal (2026-09-15) every check passed — SSO worked, the
integration showed Enabled, AO listed 36 templates — while three faults were
live. Each surfaced only on the canvas. The preflight asks the component that
failed each time, not the one that looked fine:

| Check | How | Issue |
|---|---|---|
| `ao-worker` allows AAP through AO's SSRF check | `printenv` **inside the pod** | #621 |
| The workflow's AAP credential works for the user running this | AO's organizations proxy **with** that `credential_id` — the check the MCP never made | #622 |
| The workflow exists | by name — `Windows Day 2 - Compliance Remediation (as code)` | #474 |
| The Windows guest is up | the `VirtualMachine`'s status | |
| `windemo` holds exactly one host | AAP's API — a stale host makes every Windows job fail | #616 |

## Three modes

| Mode | Input | Does |
|---|---|---|
| Prepare (default) | — | Preflight, then `Windows Day 2 - Break Compliance` so the scan fails |
| Run to the gate | `-e ao_rehearse_run=true` | Also starts the workflow and **stops at its approval** |
| Report | `-e ao_rehearse_report_execution=<id>` | Per-step timings, AAP job IDs, scan result, and the approval decision |

**It never approves.** A person approving in AO is the part being rehearsed.

## Preflight Check

```bash
ENV=${ENV:-sandbox}

test -s "$HOME/secrets/.vault_pass_sales_demos" \
  && echo "✅ vault password file" \
  || echo "❌ ~/secrets/.vault_pass_sales_demos missing — see /sales-demos-first-time"

head -c 15 playbooks/group_vars/all/secrets.yml 2>/dev/null | grep -q '^\$ANSIBLE_VAULT' \
  && echo "✅ secrets.yml is vault-encrypted" \
  || echo "❌ secrets.yml missing or NOT encrypted — see /sales-demos-first-time"

for c in kubernetes.core ansible.controller; do
  ansible-galaxy collection list "$c" 2>/dev/null | grep -q "$c" \
    && echo "✅ $c" \
    || echo "❌ $c — ansible-galaxy collection install -r collections/requirements.yml"
done

test -f ansible.cfg \
  && echo "❌ project-local ansible.cfg present — it shadows ~/.ansible.cfg" \
  || echo "✅ no project-local ansible.cfg"
```

The rest of the preflight is the playbook's job — it asks the cluster, AO and
AAP directly and fails with the fix.

## Collect inputs

| Variable | Default | Meaning |
|---|---|---|
| `ENV` (inventory limit) | `sandbox` | `sandbox`, `demo`, or `edge` |
| `ao_rehearse_run` | `false` | Start the workflow and stop at its approval |
| `ao_rehearse_break` | `true` | Break compliance first — without it a compliant guest ends the run at the condition |
| `ao_rehearse_report_execution` | — | An execution ID to report on instead |
| `ao_rehearse_workflow` | `Windows Day 2 - Compliance Remediation (as code)` | Pass another name to rehearse a workflow built on the canvas |

**On `demo`, launching needs Eric.** The `aap-demo` side is read-only for this
agent — hand him the command.

## Run

```bash
mkdir -p ~/ansible-logs
export ANSIBLE_LOG_PATH=~/ansible-logs/ao-rehearse-sandbox-$(date +%F-%H%M).log

# prepare: preflight + break
./utilities/run-ansible.sh playbooks/ao_rehearse.yml -i inventory --limit sandbox -e target_env=sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos

# run to the approval
./utilities/run-ansible.sh playbooks/ao_rehearse.yml -i inventory --limit sandbox -e target_env=sandbox \
  -e ao_rehearse_run=true --vault-id sales.demos@~/secrets/.vault_pass_sales_demos

# after approving in AO: the report
./utilities/run-ansible.sh playbooks/ao_rehearse.yml -i inventory --limit sandbox -e target_env=sandbox \
  -e ao_rehearse_report_execution=<id> --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

Never pipe through `tee` — the exit status would be `tee`'s.

From AAP: **AAP Ecosystem - Rehearse Automation Orchestrator Demo** (prepare
mode; add `ao_rehearse_run` in extra vars to run to the gate).

## Verify

**Ask the targets, not the recap:**

1. `aap-<env>` `jobs_list` — the newest `Windows Day 2 - Break Compliance` job
   succeeded.
2. With `ao_rehearse_run=true`: `ao-<env>` `approvals_list` shows one `pending`
   approval for the new execution, with the scan's numbers in its prompt;
   `execution_activities` shows `scan` completed and `compliance_check`
   `evaluated_result: true`.
3. After approving: `approvals_list` shows the decision, `decided_by` and your
   notes, and `aap-<env>` `jobs_list` shows the re-scan with `compliant: true`.

## If it fails

The playbook's failure messages name the fix. The usual ones:

| Failure | Fix |
|---|---|
| ao-worker does not allow AAP | `/sales-demos-orchestrator-config` (#621) |
| No single workflow named … | `/sales-demos-orchestrator-workflow` (#474), or pass `ao_rehearse_workflow` |
| AO refused the workflow's AAP credential | The credential belongs to another AO user (#622) — load the workflow as code, or run as its creator |
| VM is not Running | Build it with the Windows Day 1 - 0 Workflow |
| windemo holds N hosts | Delete the dead host in AAP (#616) |
| Run completed without reaching an approval | The guest was already compliant — don't pass `ao_rehearse_break=false` |
