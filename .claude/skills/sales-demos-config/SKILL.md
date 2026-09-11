---
name: sales-demos-config
description: "Apply AAP config-as-code to an environment — credential types, credentials, job templates, schedules, execution environments, gateway settings, and hub remotes. Syncs the SCM project first so newly added playbooks are visible to template creation. Runs playbooks/config.yml. TRIGGER when: the user asks to push, apply, or refresh AAP configuration, says a job template is missing or wrong, wants to update gateway settings or branding, asks about config-as-code, asks why a newly added playbook is 'not found for project', or has merged a change and needs AAP to pick it up (Step 2 of /sales-demos-dev-workflow). SKIP: if the user wants to validate without changing anything — run validate.yml --check first (this skill covers that) — or wants to set up OpenShift Virtualization, which is ocpvirt-setup."
---

# sales-demos-config

Apply AAP configuration as code to an RHDP environment. Takes about
**2 minutes** on a warm environment.

This skill contains **no logic**. All the work is in
[`playbooks/config.yml`](../../../playbooks/config.yml). See `CLAUDE.md` →
*Skills and playbooks*.

## What it does

1. Asserts the environment is unambiguous (`--limit` must match `target_env`).
2. Asserts `aap_hostname`, `aap_username`, `aap_password` are set.
3. **Syncs the SCM project** to the latest `main` (#148) — so newly added
   playbooks are visible to template creation.
4. Applies all objects via `infra.aap_configuration.dispatch`: credential types,
   credentials, projects, inventories, job templates, workflow job templates,
   schedules, execution environments, gateway settings (branding, banner),
   hub remotes and repositories.
5. Reports what was applied.

**Expect `changed` on every run.** AAP returns `SUBSCRIPTIONS_CLIENT_SECRET` as
`$encrypted$` and never in the clear, so the controller_settings role rewrites
it each time. That is the platform refusing to hand back a secret, not drift.

## How vars arrive

There is no `vars_files` or `include_vars`. `--limit sandbox` loads
`group_vars/aap/*` (shared) merged with `group_vars/sandbox/*` (per-env deltas),
combined by `dispatch_include_wildcard_vars` in `group_vars/aap/aap_settings.yml`.

## Preflight Check

```bash
./utilities/preflight.sh "${ENV:-sandbox}"
```

If any check fails, stop and tell the user exactly which one and the fix shown
beside it. Do not attempt the run with a failing prerequisite.

## Validate first — always

**`validate.yml --check` is the cheapest way to find a bad variable or a
malformed object.** It is the same play in check mode, and `--check` is
required — without it the collection's check-mode branches all take their
non-check path (#173).

```bash
mkdir -p ~/ansible-logs
LOGFILE=~/ansible-logs/validate-${ENV:-sandbox}-$(date +%F-%H%M).log

ANSIBLE_LOG_PATH="$LOGFILE" python3 -c "
import subprocess, sys
r = subprocess.run(
    ['ansible-playbook', 'playbooks/validate.yml', '--check',
     '-i', 'inventory', '--limit', '${ENV:-sandbox}',
     '-e', 'target_env=${ENV:-sandbox}',
     '--vault-id', 'sales.demos@$HOME/secrets/.vault_pass_sales_demos'],
    cwd='$(pwd)')
sys.exit(r.returncode)
"
echo "Validate log: $LOGFILE"
```

**Why `python3 -c` instead of `ansible-playbook` directly?** Ansible's blocking
IO detection fails under Claude Code's Bash tool (which sets non-blocking IO on
stdout/stderr). `subprocess.run()` gives the child its own blocking file handles.

**Skip the validate step only when you already know what failed** — a credential
type that AAP refuses to modify (see below), or a re-run after fixing a single
variable. Otherwise run it.

## Collect inputs

| Variable | Default | Meaning |
|---|---|---|
| `ENV` (inventory limit) | `sandbox` | Which environment to target — `sandbox` or `demo` |

## Run

```bash
mkdir -p ~/ansible-logs
LOGFILE=~/ansible-logs/config-${ENV:-sandbox}-$(date +%F-%H%M).log

ANSIBLE_LOG_PATH="$LOGFILE" python3 -c "
import subprocess, sys
r = subprocess.run(
    ['ansible-playbook', 'playbooks/config.yml',
     '-i', 'inventory', '--limit', '${ENV:-sandbox}',
     '-e', 'target_env=${ENV:-sandbox}',
     '--vault-id', 'sales.demos@$HOME/secrets/.vault_pass_sales_demos'],
    cwd='$(pwd)')
sys.exit(r.returncode)
"
echo "Log: $LOGFILE"
```

**Always set `ANSIBLE_LOG_PATH`** — the log is the only evidence left if it
fails. Logs live outside the repo, in `~/ansible-logs/`. Tell the user the path.

**Never pipe the run through `tee`.** In a pipeline the exit status comes from
`tee`, not `ansible-playbook`, so a failed run reports success.

Tell the user this takes about 2 minutes and stream the output.

## Verify it in the EE before merging a change

See `/sales-demos-verify-ee` for why and how. The one command:

```bash
utilities/run-in-ee.sh --with-hub-token playbooks/config.yml \
  -i inventory --limit sandbox -e target_env=sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

**`--with-hub-token` is required** — `config.yml` evaluates
`automation_hub_token` via the hub remote templates. Without it, `run-in-ee.sh`
fails with `Invalid filename: 'None'`.

## Verify against AAP, not the recap

**A green playbook run is not proof.** Check that the objects actually landed
using the `aap-<env>` MCP tools:

```
mcp__aap-<env>__job_templates_list
mcp__aap-<env>__workflow_job_templates_list
mcp__aap-<env>__credentials_list
mcp__aap-<env>__credential_types_list
mcp__aap-<env>__execution_environments_list
mcp__aap-<env>__organizations_list
mcp__aap-<env>__projects_list
```

Spot-check the key items:

1. **Job templates** — every playbook in the repo should have a template.
   Confirm with `job_templates_list` and look for the playbook names.
2. **Credentials** — the "Sales Demos - Env Secrets" custom credential type
   should exist with its injectors, and credentials using it should be attached.
3. **Execution environments** — `sales_demos_ee` should show the current tag.
4. **Gateway settings** — log out of the AAP UI and confirm the environment
   logo and pre-login banner appear.

## When it finishes

Report the playbook summary **and** the MCP verification, then tell the user
config is applied.

## If it fails

| Symptom | Cause | Fix |
|---|---|---|
| `censored: 'the output has been hidden...'` | `no_log` hiding the real error | Re-run with `-e aap_configuration_secure_logging=false` to see the message |
| `{'playbook': ['Playbook not found for project.']}` | The SCM project is stale | The playbook syncs it (#148), but if the sync itself failed, check the project in the AAP UI |
| `Modifications to inputs are not allowed for credential types that are in use` | AAP refuses to modify a credential type's `inputs` when credentials exist | Delete the credential, then the credential type, via the API or AAP UI, then re-run — dispatch recreates both |
| A partial failure left some objects applied and others not | `infra.aap_configuration` applies objects in order; a failure mid-run is a partial apply | Re-run — dispatch is idempotent. The already-applied objects report `ok` |
| `check mode and async cannot be used on same task` | Running `validate.yml` without `--check` on ansible-core 2.16 | Add `--check` — it is required (#173) |
| `Default choice must be answered from the choices listed` | AAP server-side survey validation rejected a default value | The `no_log` censoring hides this — re-run with `-e aap_configuration_secure_logging=false`, then fix the survey_spec |
| `Attempting to decrypt but no vault secrets found` | `--vault-id` missing from the command | Add `--vault-id sales.demos@~/secrets/.vault_pass_sales_demos` |
| `KeyError: 'id'` in `ah_ee_repository.py` | validate.yml on a never-configured environment — the registry hasn't been created yet (#106) | Run `config.yml` first, then `validate.yml --check` passes cleanly |
| `401` / `Unauthorized` on the first task | RHDP bearer token expired, or wrong password in the vault | Refresh `openshift_api_token` / `aap_password` in the vault |

### Deleting a credential type that AAP refuses to modify

AAP will not let you change a credential type's `inputs` (field definitions,
required fields) while any credential uses that type. `injectors` (extra_vars
mapping) can be changed freely.

```bash
HOST=$(grep -oP '(?<=^aap_hostname: ")[^"]+' inventory/group_vars/${ENV:-sandbox}/connection.yml)
PW=$(ansible-vault view playbooks/group_vars/all/secrets.yml \
       --vault-id sales.demos@~/secrets/.vault_pass_sales_demos \
     | python3 -c 'import sys,yaml; print(yaml.safe_load(sys.stdin)["env_secrets"]["'${ENV:-sandbox}'"]["aap_password"])')

CRED_TYPE="Sales Demos - Env Secrets"

CRED_IDS=$(curl -sk -u "admin:$PW" \
  "https://$HOST/api/controller/v2/credentials/?credential_type__name=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$CRED_TYPE'))")" \
  | python3 -c 'import sys,json; [print(c["id"]) for c in json.load(sys.stdin)["results"]]')

for id in $CRED_IDS; do
  curl -sk -u "admin:$PW" -X DELETE "https://$HOST/api/controller/v2/credentials/$id/"
  echo "Deleted credential $id"
done

TYPE_ID=$(curl -sk -u "admin:$PW" \
  "https://$HOST/api/controller/v2/credential_types/?name=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$CRED_TYPE'))")" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["results"][0]["id"])')

curl -sk -u "admin:$PW" -X DELETE "https://$HOST/api/controller/v2/credential_types/$TYPE_ID/"
echo "Deleted credential type $TYPE_ID"
```

Then re-run `config.yml` — dispatch recreates both from the YAML definitions.

Never paste a live cluster hostname, password, or token into a commit message,
issue, or PR. This repo is public — see `CLAUDE.md`.
