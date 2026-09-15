---
name: sales-demos-orchestrator-workflow
description: "Load the Automation Orchestrator demo workflows from config-as-code — inventory/group_vars/aap/ao_workflows.yml — into an environment's AO, resolving job template, credential, integration and approver names to that environment's IDs, or remove them. Runs playbooks/ao_workflows.yml. TRIGGER when: the user wants the AO demo workflow recreated on a new or rebuilt environment, asks to load, import, restore or refresh AO workflows, wants a fallback copy before presenting the AO demo, asks where the rehearsed workflow is saved, or asks about issue #474. SKIP: if AO is not installed or not configured — that is sales-demos-orchestrator then sales-demos-orchestrator-config — or if the user wants to build a workflow live on the AO canvas, which is the demo itself (see the sales.demos-docs Automation Orchestrator guide)."
---

# sales-demos-orchestrator-workflow

Creates or updates every workflow in
[`inventory/group_vars/aap/ao_workflows.yml`](../../../inventory/group_vars/aap/ao_workflows.yml)
in this environment's Automation Orchestrator. Takes **under a minute**.

This skill contains **no logic**. All the work is in
[`playbooks/ao_workflows.yml`](../../../playbooks/ao_workflows.yml). See
`CLAUDE.md` → *Skills and playbooks*.

## Why the workflow is stored by name, not exported

AO's export embeds values that only exist in the environment it came from — AO
integration and credential UUIDs, AAP's numeric job template IDs, and the
approver's federated username. Imported anywhere else, every one is wrong. The
committed file names things instead, and the playbook looks each one up:

| In the file | Resolved from |
|---|---|
| `job_template` | AAP job template ID, through `GET /api/v1/proxies/aap/job_templates` |
| `credential` | AO credential ID, `GET /api/v1/credentials` |
| `integration` | AO integration ID, `GET /api/v1/integrations` |
| `project` | AO project ID, `GET /api/v1/projects` |
| `approvers_sso` | The federated AO user each AAP username became on first SSO login, `GET /api/v1/users` |

**Node IDs are chosen in the file** (`activity_scan`, …) and expressions
reference them. AO references steps by ID, never by display name.

## What it does

1. Asserts the target environment and the connection variables.
2. Reads the AO Route and logs in to AO as the local `admin`.
3. Looks up projects, integrations, credentials, AAP job templates and SSO users,
   and **fails with the missing name** if anything in the file does not resolve.
4. Renders each workflow definition and checks it with
   `POST /api/v1/workflows/validate`.
5. Creates the workflow if it is missing, or updates it if its steps, edges or
   triggers differ from the file. **An unchanged workflow is not saved**, so
   re-running does not pile up versions.
6. Publishes it only if the file says `publish: true`.
7. Reads the workflow back and asserts its step names and condition match the
   file.

`-e ao_workflow_state=absent` removes the workflows in the file instead.

## Ownership: who can run it, who can edit it

The playbook logs in as the local AO `admin`, so the loaded workflow and the
**AAP Admin** credential it uses belong to `admin` (#622). Measured on sandbox:

- **Anyone can run it.** A workflow run does not check credential ownership
  against the user who starts it.
- **An SSO user editing it in the builder** is refused AAP Admin when browsing
  an AAP step's templates, shown as `AAP Authentication Failed`. To change a
  step, switch it to a credential you created.

That is why building live stays the demo and this is the fallback.

## Preflight Check

Run these before doing anything else. Every one must pass.

```bash
ENV=${ENV:-sandbox}

# 1. The vault password file exists.
test -s "$HOME/secrets/.vault_pass_sales_demos" \
  && echo "✅ vault password file" \
  || echo "❌ ~/secrets/.vault_pass_sales_demos missing — see /sales-demos-first-time"

# 2. secrets.yml exists locally and is vault-encrypted.
head -c 15 playbooks/group_vars/all/secrets.yml 2>/dev/null | grep -q '^\$ANSIBLE_VAULT' \
  && echo "✅ secrets.yml is vault-encrypted" \
  || echo "❌ secrets.yml missing or NOT encrypted — see /sales-demos-first-time"

# 3. kubernetes.core is installed
ansible-galaxy collection list kubernetes.core 2>/dev/null | grep -q kubernetes.core \
  && echo "✅ kubernetes.core" \
  || echo "❌ kubernetes.core — ansible-galaxy collection install -r collections/requirements.yml"

# 4. No project-local ansible.cfg shadowing ~/.ansible.cfg
test -f ansible.cfg \
  && echo "❌ project-local ansible.cfg present — it shadows ~/.ansible.cfg" \
  || echo "✅ no project-local ansible.cfg"

# 5. AO is installed and configured: Route serving, allowlist ConfigMap present (#621)
AO_HOST=$(oc get route ao -n automation-orchestrator -o jsonpath='{.spec.host}' 2>/dev/null)
if [ -n "$AO_HOST" ]; then
  curl -sk -o /dev/null -w '%{http_code}' "https://${AO_HOST}" | grep -q 200 \
    && echo "✅ AO Route reachable at https://${AO_HOST}" \
    || echo "❌ AO Route exists but not serving — is AO installed?"
else
  echo "❌ No AO Route — run /sales-demos-orchestrator first"
fi
oc get configmap ao-admin-settings -n automation-orchestrator >/dev/null 2>&1 \
  && echo "✅ ao-admin-settings ConfigMap present" \
  || echo "❌ ao-admin-settings missing — run /sales-demos-orchestrator-config first, or every AAP step will fail at run time (#621)"
```

Also check with MCP, not config files: `ao-<env>` `credentials_list` shows
**AAP Admin**, and `integrations_list` shows the AAP integration. Both come from
`/sales-demos-orchestrator-config`.

If any check fails, stop and tell the user exactly which one and the fix shown
beside it.

## Collect inputs

| Variable | Default | Meaning |
|---|---|---|
| `ENV` (inventory limit) | `sandbox` | `sandbox`, `demo`, or `edge` |
| `ao_workflow_state` | `present` | `absent` removes the workflows in the file |

## Run

```bash
mkdir -p ~/ansible-logs
export ANSIBLE_LOG_PATH=~/ansible-logs/ao-workflows-sandbox-$(date +%F-%H%M).log

./utilities/run-ansible.sh playbooks/ao_workflows.yml -i inventory --limit sandbox -e target_env=sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

**Always set `ANSIBLE_LOG_PATH`**, and never pipe the run through `tee` — the
exit status would be `tee`'s.

From AAP, launch **AAP Ecosystem - Load Automation Orchestrator Workflows**.

## Verify

**Ask AO, not the recap:**

1. `ao-<env>` `workflows_list` — `Windows Day 2 - Compliance Remediation (as code)`
   exists. The `(as code)` suffix keeps it apart from a copy built live on the
   canvas, which the loader never touches.
2. `ao-<env>` `workflow_get` — the stored definition has nodes `scan`,
   `compliance_check`, `security_approval`, `fix`, `rescan`; the condition is
   `${activity_scan.artifacts.windows_compliance.fail} > 0`; and each AAP step's
   `job_template_id` matches this environment's AAP (`aap-<env>`
   `job_templates_list`).
3. **The real proof is a run.** With the guest non-compliant
   (`Windows Day 2 - Break Compliance`), run the workflow in AO: it should reach
   `security_approval`. `/sales-demos-orchestrator-rehearse` (#623) automates
   that.

## If it fails

| Symptom | Cause | Fix |
|---|---|---|
| "… not found in AO" for a credential or integration | `/sales-demos-orchestrator-config` has not run here | Run it, then re-run this |
| "… not found in AAP" for a job template | AAP config-as-code not applied, or the template was renamed | Run `/sales-demos-config`, or fix the name in `ao_workflows.yml` |
| Validation findings printed and the run stops | A reference in the file does not match a node ID, or a field AO requires is missing | Fix `ao_workflows.yml` — the findings name the node |
| Warning that no SSO approver was found | Nobody has logged in to AO through AAP SSO yet | Log in once through SSO and re-run, or accept "any authorized user" |
| An AAP step fails at run time with "base_url is not permitted by SSRF policy" | `ao-worker` lacks the allowlist (#621) | `/sales-demos-orchestrator-config` |

## Removing

```bash
./utilities/run-ansible.sh playbooks/ao_workflows.yml -i inventory --limit sandbox -e target_env=sandbox \
  -e ao_workflow_state=absent --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

Only the workflows named in the file are removed. Workflows built by hand on the
canvas are never touched.

**Removing a workflow deletes its run history, including approval records.**
Measured on sandbox, 2026-09-15: after removal, its executions returned 404 and
its approvals were gone from `approvals_list`. If a run's approval is evidence —
a rehearsal, an audit demo — capture it (screenshot, or `approvals_list`) first.
To refresh the definition, just re-run with the default `present`: that saves a
new version and keeps history.
