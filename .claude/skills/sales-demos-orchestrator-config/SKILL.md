---
name: sales-demos-orchestrator-config
description: "Configure Automation Orchestrator post-install — connect it to AAP via OIDC (SSO login) and an AAP integration (so AO can see job templates, workflows, inventories). Runs playbooks/configure_ao.yml. TRIGGER when: the user asks to configure AO, connect AO to AAP, set up SSO for AO, set up OIDC on AO, asks why AO has no integrations, says AO login only shows local accounts, or asks why AO cannot see AAP job templates. SKIP: if AO is not installed (that is sales-demos-orchestrator), or if the user wants to create or edit workflows in AO (that is the AO UI/API directly)."
---

# sales-demos-orchestrator-config

Connects a running Automation Orchestrator to this environment's AAP instance.
Takes about **2 minutes**.

This skill contains **no logic**. All the work is in
[`playbooks/configure_ao.yml`](../../../playbooks/configure_ao.yml). See
`CLAUDE.md` → *Skills and playbooks*.

**`install_ao.yml` must have run first** — AO needs to be up and serving its
Route before this can configure it.

## What it does

1. Reads the AO **Route** from the cluster to get the live URL.
2. Patches the `ao-backend` Deployment with `APP_INTEGRATION_URL_ALLOWED_HOSTS`
   so AO's SSRF protection allows reaching AAP (which resolves to a private IP
   inside the cluster).
3. Sets up AAP as an **OIDC identity provider** via `setup_aap_oidc` — users
   can then log into AO with their AAP credentials.
4. Creates an **AAP credential** and **AAP integration** — AO can now see
   job templates, workflow job templates, inventories and EEs from AAP.
5. **Validates** by querying AO's proxy endpoint to confirm job templates are
   visible.

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

The playbook's other inputs (namespace, deployment names) are vars with working
defaults. Override them only for a reason.

## Run

```bash
mkdir -p ~/ansible-logs
export ANSIBLE_LOG_PATH=~/ansible-logs/configure-ao-sandbox-$(date +%F-%H%M).log

ansible-playbook playbooks/configure_ao.yml -i inventory --limit sandbox -e target_env=sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

**Always set `ANSIBLE_LOG_PATH`** — the log is the only evidence left if it
fails. Logs live outside the repo, in `~/ansible-logs/`. Tell the user the path.

**Never pipe the run through `tee`.** In a pipeline the exit status comes from
`tee`, not `ansible-playbook`, so a failed run reports success.

Tell the user this takes about 2 minutes and stream the output.

## Verify on the cluster

**A green playbook run is not proof.** Confirm independently with the
`openshift-sandbox` (or `openshift-demo`) MCP tools:

1. `pods_list_in_namespace` for `automation-orchestrator` — `ao-backend` pods
   should be `Running` and have the `APP_INTEGRATION_URL_ALLOWED_HOSTS` env var.
2. Open AO in a browser → Settings → Identity Providers → AAP OIDC should exist.
3. Settings → Integrations → AAP integration should show connected.
4. In AO, create a workflow → "Add AAP step" should show JTs from AAP.

## When it finishes

Report the playbook summary **and** the verification above, then give the user
the AO URL.

## If it fails

| Symptom | Cause | Fix |
|---|---|---|
| `401` on AO login | AO admin password does not match AAP admin password | Was the environment built before #143? Retrieve with `oc get secret ao-initial-admin-password -n automation-orchestrator -o jsonpath='{.data.password}' \| base64 -d` |
| `502` on `setup_aap_oidc` | OAuth2 app "Syntara" already exists on AAP | Identity provider already configured — the playbook checks first but if run was interrupted between the AAP-side OAuth2 creation and the AO-side save, delete the "Syntara" app from AAP |
| `422` on integration create with SSRF error | `APP_INTEGRATION_URL_ALLOWED_HOSTS` not applied yet | Re-run — the playbook patches and waits for rollout before creating the integration |
| `422` on credential create | Credential type or project not found | Check AO API is healthy; the playbook looks up the "Ansible Automation Platform" credential type and "default" project by name |
| Timeout waiting for `ao-backend` rollout | Deployment stuck | Check `oc get pods -n automation-orchestrator` for crash-looping backend pods |
| `401` on the verify step | JWT expired (15-minute lifetime) | Re-run — the playbook logs in once at the start |

## Removing the configuration

Delete the integration, credential, and identity provider through the AO API or
UI. The SSRF allowlist env var on ao-backend is harmless to leave in place.

To remove the OAuth2 application from AAP, delete the "Syntara" application via
the AAP API or UI under Administration → Applications.

Never paste a live cluster hostname or token into a commit message, issue, or
PR. This repo is public — see `CLAUDE.md`.
