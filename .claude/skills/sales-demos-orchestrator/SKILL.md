---
name: sales-demos-orchestrator
description: "Install Automation Orchestrator and the PostgreSQL it cannot run without, so an environment ends up with a working orchestrator UI rather than a catalog entry. Deploys CloudNativePG, builds the three databases Temporal actually needs, installs the AO operator, creates the instance, and proves the Route serves a page. Runs playbooks/install_ao.yml. TRIGGER when: the user asks to install, deploy or fix Automation Orchestrator or AO, asks why the orchestrator UI is missing or 503s, says ao-temporal-migration is crash-looping, or built an environment with install_ao=false and now wants it. SKIP: if the user wants the AAP self-service portal — that is sales-demos-portal — or wants to install OpenShift Virtualization, which is ocpvirt-setup."
---

# sales-demos-orchestrator

Installs Automation Orchestrator into an RHDP environment, database and all.
Takes about **5 minutes**.

This skill contains **no logic**. All the work is in
[`playbooks/install_ao.yml`](../../../playbooks/install_ao.yml). See
`CLAUDE.md` → *Skills and playbooks*.

**`setup.yml` already runs this on every build**, so reach for this skill when
you need it on its own: an environment built with `-e install_ao=false`, or an
AO stack that needs reconciling without re-running CNV and the whole AAP
configuration.

## What it does

1. Installs **CloudNativePG** (`certified-operators`, `stable-v1`) into
   `cnpg-system` with an AllNamespaces OperatorGroup.
2. Creates a single-instance PostgreSQL `Cluster` (`ao-db`, 10Gi) in
   `automation-orchestrator`, whose `initdb` makes the **backend** database.
3. Creates the other **two** databases as CNPG `Database` resources.
4. Reshapes CNPG's generated credentials into the two secrets the AO CRD wants.
5. Installs the **Automation Orchestrator operator** (`redhat-operators`,
   `stable`) and creates the `AutomationOrchestrator` CR with a Route.
6. Waits for `Ready=True`, then **asks the Route for a page** and requires a
   `200`.

## Three databases, not two — the thing that will waste your afternoon

The CRD requires exactly two secretRefs, `backendDatabase` and
`temporalDatabase`. Build two and `ao-temporal-migration` crash-loops forever:

```
pq: database "temporal_visibility" does not exist
```

Temporal keeps its visibility store in a **separate** database with a **fixed**
name — literally `temporal_visibility`, not a suffix of whatever you called the
temporal database. Nothing in the CRD, the sample CR, or the operator
description mentions it. The playbook creates all three. **Do not remove the
third because the CRD only asks for two.**

## Why it gets its own database

`aap-postgres-15` is owned by the `AnsibleAutomationPlatform` CR with
`blockOwnerDeletion` — the AAP operator reconciles it, so databases added by
hand live inside something another operator recreates at will. Temporal is
write-heavy, and putting that load on the database the whole demo platform runs
on trades a working AAP for a working AO.

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
#    It is gitignored (#130); a fresh clone will not have it.
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
```

If any check fails, stop and tell the user exactly which one and the fix shown
beside it. Do not attempt the run with a failing prerequisite.

## Confirm the operators are actually offered here

Both come from catalogs that may differ between environments. Check before
running rather than discovering it three minutes in:

```bash
ENV=${ENV:-sandbox}
test -f ".kube/${ENV}.kubeconfig" || bash utilities/make-kubeconfig.sh "$ENV"
export KUBECONFIG=".kube/${ENV}.kubeconfig"

for pkg in cloudnative-pg automation-orchestrator-operator; do
  src=$(oc get packagemanifest "$pkg" -n openshift-marketplace \
        -o jsonpath='{.status.catalogSource}' 2>/dev/null)
  [ -n "$src" ] && echo "✅ $pkg offered by $src" \
                || echo "❌ $pkg is NOT in this cluster's catalog"
done
```

## Collect inputs

| Variable | Default | Meaning |
|---|---|---|
| `ENV` (inventory limit) | `sandbox` | Which environment to target — `sandbox` or `demo` |

The playbook's other inputs (namespaces, channels, database names, the 10Gi
volume) are vars with working defaults. Override them only for a reason.

## Run

```bash
mkdir -p ~/ansible-logs
export ANSIBLE_LOG_PATH=~/ansible-logs/install-ao-sandbox-$(date +%F-%H%M).log

ansible-playbook playbooks/install_ao.yml -i inventory --limit sandbox -e target_env=sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

**Always set `ANSIBLE_LOG_PATH`** — the log is the only evidence left if it
fails. Logs live outside the repo, in `~/ansible-logs/`. Tell the user the path.

**Never pipe the run through `tee`.** In a pipeline the exit status comes from
`tee`, not `ansible-playbook`, so a failed run reports success.

Tell the user this takes about 5 minutes and stream the output.

## Verify on the cluster

**A green playbook run is not proof**, though this playbook already asks the
Route for a `200` before it reports success. Confirm independently with the
`openshift-sandbox` (or `openshift-demo`) MCP tools:

1. `pods_list_in_namespace` for `automation-orchestrator` — expect the database
   plus backend, UI, worker, background-worker, temporal and redis all
   `Running`, and the migration Jobs `Completed`.
2. `resources_get` the `AutomationOrchestrator` named `ao` and check
   `Ready=True` / `Degraded=False`.
3. `resources_list` Routes in `automation-orchestrator` and open the host.

Then open the URL. It should serve the Automation Orchestrator UI.

## When it finishes

Report the playbook summary **and** the verification above, then give the user
the URL.

## If it fails

| Symptom | Cause | Fix |
|---|---|---|
| `ao-temporal-migration` pods in `Error`, everything else waiting | The `temporal_visibility` database is missing | Re-run — the playbook creates all three. If it persists, check the `Database` resources report `status.applied: true` |
| `401` / `Unauthorized` on the first task | RHDP bearer token expired | Refresh `openshift_api_token` in the vault, re-run `make-kubeconfig.sh` |
| CSV wait times out | Wrong catalog for this cluster | CNPG is in `certified-operators`, AO in `redhat-operators`. Run the catalog check above |
| `no matches for kind "Cluster" in version postgresql.cnpg.io/v1` | CNPG CRDs not established yet, or you are looking at ODF's | ODF ships a vendored CNPG under `postgresql.cnpg.noobaa.io` — a different API group that will not serve these. Wait for the real CRDs |
| Route returns 503 | Router has no backend yet | Normal shortly after deploy; the playbook retries. If it persists, check the `ao-ui` pods |
| `Attempting to decrypt but no vault secrets found` | `--vault-id` missing from the command | Add `--vault-id sales.demos@~/secrets/.vault_pass_sales_demos` |

## Removing it

The whole stack, database included, is two deletes plus the operator:

```bash
oc delete automationorchestrator ao -n automation-orchestrator
oc delete namespace automation-orchestrator      # takes the database with it
```

The 10Gi PVC goes with the namespace. `teardown.yml` deliberately leaves all of
this alone — AO is setup-time infrastructure like CNV, not per-demo state.

Never paste a live cluster hostname or token into a commit message, issue, or
PR. This repo is public — see `CLAUDE.md`.
