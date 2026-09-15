---
name: sales-demos-orchestrator-config
description: "Configure Automation Orchestrator post-install — connect it to AAP via OIDC (SSO login) and an AAP integration (so AO can see job templates, workflows, inventories), and allow AAP through AO's SSRF check on every component that reaches it. Runs playbooks/configure_ao.yml. TRIGGER when: the user asks to configure AO, connect AO to AAP, set up SSO for AO, set up OIDC on AO, asks why AO has no integrations, says AO login only shows local accounts, asks why AO cannot see AAP job templates, says an AO workflow's AAP step fails with 'base_url is not permitted by SSRF policy', or says an AAP step's Organization dropdown shows 'AAP Authentication Failed'. SKIP: if AO is not installed (that is sales-demos-orchestrator), or if the user wants to create or edit workflows in AO (that is the AO UI/API directly)."
---

# sales-demos-orchestrator-config

Connects a running Automation Orchestrator to this environment's AAP instance.
Takes about **2 minutes**, plus about a minute more the first time, while the
AO components restart.

This skill contains **no logic**. All the work is in
[`playbooks/configure_ao.yml`](../../../playbooks/configure_ao.yml). See
`CLAUDE.md` → *Skills and playbooks*.

**`install_ao.yml` must have run first** — AO needs to be up and serving its
Route before this can configure it.

## What it does

1. Reads the AO **Route** from the cluster to get the live URL.
2. Writes the **SSRF allowlist** into the ConfigMap `ao-admin-settings`:
   `APP_INTEGRATION_URL_ALLOWED_HOSTS` (the AAP hostname) and
   `APP_OIDC_ALLOW_PRIVATE_NETWORKS`. AAP resolves to a private IP inside the
   cluster, which AO's SSRF protection blocks by default.
   - **Every AO Deployment already loads that ConfigMap** through an optional
     `envFrom`. That matters because browsing AAP runs in `ao-backend`, but
     **running** an AAP step in a workflow runs in `ao-worker` (#621).
   - **If the ConfigMap changed,** it restarts the `ao-backend`, `ao-worker`
     and `ao-background-worker` pods and waits for them to be ready.
   - **If an older run patched the variables directly onto a Deployment,** it
     removes them, so the ConfigMap is the one source.
   - **Then it runs `printenv` inside an `ao-worker` pod** and fails if the AAP
     hostname is not there.
3. Sets up AAP as an **OIDC identity provider** via `setup_aap_oidc` — users
   can then log into AO with their AAP credentials.
4. Creates the AO credential **AAP Admin** (matched by that name) and the **AAP
   integration** — AO can now see job templates, workflow job templates,
   inventories and EEs from AAP.
5. **Validates** by querying AO's proxy endpoint to confirm job templates are
   visible.

## People who build workflows need their own AAP credential

**AO lets only the user who created a credential browse AAP with it** (#622).
This playbook logs in as the local AO `admin`, so **AAP Admin** belongs to
`admin`. Measured on sandbox:

| What | Does it check who owns the credential? |
|---|---|
| Browsing AAP in the workflow builder (an AAP step's Organization and Job template dropdowns) | **Yes.** Anyone else gets `AAP Authentication Failed` |
| Running a workflow | **No.** A step used a credential the user who started the run does not own |

So **AAP Admin** does its job for the integration and for workflows loaded as
code, which anyone can run. But **anyone who builds or edits AAP steps while
logged in through AAP SSO needs a credential they created**: in the step, click
**Change** under the credential and create a Basic Auth credential with the AAP
admin username and password. Once per person, per environment.

A playbook cannot create that credential for them — an SSO login is a browser
OIDC flow, not something Ansible can do — and the error text does not say
"ownership", which is why this section exists.

## Preflight Check

Run these before doing anything else. Every one must pass.

```bash
ENV=${ENV:-sandbox}
VAULT_ID="sales.demos@$HOME/secrets/.vault_pass_sales_demos"

# 1. The vault password file exists.
test -s "$HOME/secrets/.vault_pass_sales_demos" \
  && echo "✅ vault password file" \
  || echo "❌ ~/secrets/.vault_pass_sales_demos missing — without it secrets.yml cannot be decrypted"

# 2. secrets.yml exists locally and is vault-encrypted, not plaintext.
head -c 15 playbooks/group_vars/all/secrets.yml 2>/dev/null | grep -q '^\$ANSIBLE_VAULT' \
  && echo "✅ secrets.yml is vault-encrypted" \
  || echo "❌ secrets.yml missing or NOT encrypted — see /sales-demos-first-time"

# 3. This environment's credentials are real, not placeholders.
ansible-vault view playbooks/group_vars/all/secrets.yml --vault-id "$VAULT_ID" 2>/dev/null \
  | ENV="$ENV" python3 -c "
import sys, yaml, os
env = os.environ.get('ENV', 'sandbox')
d = yaml.safe_load(sys.stdin) or {}
e = (d.get('env_secrets') or {}).get(env, {})
bad = [k for k, v in e.items() if 'CHANGEME' in str(v)]
print(('❌ ' + env + ' still has placeholders: ' + ', '.join(bad)) if bad
      else ('✅ ' + env + ' credentials filled in'))
"

# 4. kubernetes.core is installed
ansible-galaxy collection list kubernetes.core 2>/dev/null | grep -q kubernetes.core \
  && echo "✅ kubernetes.core" \
  || echo "❌ kubernetes.core — ansible-galaxy collection install -r collections/requirements.yml"

# 5. No project-local ansible.cfg shadowing ~/.ansible.cfg
test -f ansible.cfg \
  && echo "❌ project-local ansible.cfg present — it shadows ~/.ansible.cfg and breaks certified installs" \
  || echo "✅ no project-local ansible.cfg"

# 6. AO Route is reachable
AO_HOST=$(oc get route ao -n automation-orchestrator -o jsonpath='{.spec.host}' 2>/dev/null)
if [ -n "$AO_HOST" ]; then
  curl -sk -o /dev/null -w '%{http_code}' "https://${AO_HOST}" | grep -q 200 \
    && echo "✅ AO Route reachable at https://${AO_HOST}" \
    || echo "❌ AO Route exists but not serving — is AO installed?"
else
  echo "❌ No AO Route found — run /sales-demos-orchestrator first"
fi
```

If any check fails, stop and tell the user exactly which one and the fix shown
beside it. Do not attempt the run with a failing prerequisite.

## Collect inputs

| Variable | Default | Meaning |
|---|---|---|
| `ENV` (inventory limit) | `sandbox` | Which environment to target — `sandbox`, `demo`, or `edge` |

The playbook's other inputs (namespace, ConfigMap and component names) are vars
with working defaults. Override them only for a reason.

## Run

```bash
mkdir -p ~/ansible-logs
export ANSIBLE_LOG_PATH=~/ansible-logs/configure-ao-sandbox-$(date +%F-%H%M).log

./utilities/run-ansible.sh playbooks/configure_ao.yml -i inventory --limit sandbox -e target_env=sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

**Always set `ANSIBLE_LOG_PATH`** — the log is the only evidence left if it
fails. Logs live outside the repo, in `~/ansible-logs/`. Tell the user the path.

**Never pipe the run through `tee`.** In a pipeline the exit status comes from
`tee`, not `ansible-playbook`, so a failed run reports success.

Tell the user this takes about 2 minutes and stream the output.

## Verify on the cluster

**A green playbook run is not proof.** Confirm independently with the
`openshift-<env>` and `ao-<env>` MCP tools:

1. `resources_get` ConfigMap `ao-admin-settings` in `automation-orchestrator` —
   `APP_INTEGRATION_URL_ALLOWED_HOSTS` holds this environment's AAP hostname.
2. `pods_exec` into an `ao-worker` pod with `printenv
   APP_INTEGRATION_URL_ALLOWED_HOSTS` — the same hostname. **This is the check
   that matters.** Before #621 the backend had the setting, the worker did not,
   and nothing else showed the difference.
3. `ao-<env>` `identity_providers_list` — the AAP OIDC provider exists.
4. `ao-<env>` `integrations_list` and `proxies_aap_job_templates` — the AAP
   integration exists and templates are listed.
5. `ao-<env>` `credentials_list` — **AAP Admin** exists and
   `integration_count` is 1.
6. **The real proof is a workflow run.** An AO workflow with one AAP job
   template step (a read-only one, such as `Cluster Day 0 - Probe Capacity`)
   launches an AAP job instead of failing in under a second.

## When it finishes

Report the playbook summary **and** the verification above, then give the user
the AO URL. **Tell them about the credential section above** if they are going
to build workflows in the UI.

## If it fails

| Symptom | Cause | Fix |
|---|---|---|
| `401` on AO login | AO admin password does not match AAP admin password | Was the environment built before #143? Retrieve with `oc get secret ao-initial-admin-password -n automation-orchestrator -o jsonpath='{.data.password}' \| base64 -d` |
| `502` on `setup_aap_oidc` | OAuth2 app "Syntara" already exists on AAP | Identity provider already configured — the playbook checks first but if run was interrupted between the AAP-side OAuth2 creation and the AO-side save, delete the "Syntara" app from AAP |
| `422` on integration create with SSRF error | The backend pods have not restarted onto the ConfigMap yet | Re-run — the playbook restarts the components and waits before creating the integration |
| "ao-worker pod ... does not have ... in APP_INTEGRATION_URL_ALLOWED_HOSTS" | The worker Deployment no longer loads `ao-admin-settings`, or its pods never restarted | Check the Deployment's `envFrom` still names the ConfigMap; re-run to restart the pods |
| A workflow's AAP step fails at once: "base_url is not permitted by SSRF policy" | `ao-worker` lacks the allowlist (#621) | Re-run this skill — it writes the ConfigMap, restarts `ao-worker`, and verifies inside the pod |
| An AAP step's Organization dropdown: "AAP Authentication Failed" (`AAP_AUTHENTICATION_ERROR`), while AAP itself is healthy | The step's credential was created by a different AO user — AO checks ownership and reports it as an authentication failure (#622). `ao-backend`'s log says `User … is not authorized to use credential …` | Create your own AAP credential in the step (**Change** → new Basic Auth credential). Re-running this skill does not help |
| `422` on credential create | Credential type or project not found | Check AO API is healthy; the playbook looks up the "Ansible Automation Platform" credential type and "default" project by name |
| Timeout waiting for the AO components | A Deployment stuck after the restart | Check `oc get pods -n automation-orchestrator` for crash-looping pods |
| `401` on the verify step | JWT expired (15-minute lifetime) | Re-run — the playbook logs in once at the start |

## Removing the configuration

Delete the integration, credential, and identity provider through the AO API or
UI. To remove the SSRF allowlist, delete the `ao-admin-settings` ConfigMap and
restart the AO pods — AO then cannot reach AAP at all, so only do this when
removing the integration too.

To remove the OAuth2 application from AAP, delete the "Syntara" application via
the AAP API or UI under Administration → Applications.

Never paste a live cluster hostname or token into a commit message, issue, or
PR. This repo is public — see `CLAUDE.md`.
