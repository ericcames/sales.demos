---
name: sales-demos-compliance
description: "Deploy Compliance as Code — the AAC assessment layer: one OPA pod in policy-as-code serving the pinned ynotbhatc/rego_policy_libraries release as a bundle behind opa-security, opa-compliance and opa-ot, proven to answer a framework report on empty input; plus, opt-in, the AO routing OPA (opa-routing) and the AAC evidence database (`aac` in policy-db). Runs playbooks/install_aac_opa.yml after install_opa.yml, and optionally playbooks/install_opa_routing.yml and playbooks/install_aac_db.yml. TRIGGER when: the user wants to assess a host against CIS, STIG, NIST or another framework with policy (not OpenSCAP), set up or remove the AAC assessment servers, asks about opa_security_url / opa_compliance_url / opa_ot_url / aac_opa_routing_url, wants the routing OPA that decides AO workflow routes (golden image, Tanium drift), wants the `aac` evidence database or its tables, asks about aac_db_password or aac_db_seed_url, Compliance as Code, AAC, or issue #841 / #867 / #868 / #869. SKIP: if the user wants AAP to block a job launch — that is sales-demos-policy (Policy as Code) — or the OpenSCAP scan of a VM — that is Linux Day 1 - 4 Compliance Scan."
---

# sales-demos-compliance

Deploy the **assessment** half of the library Policy as Code already runs.
`sales-demos-policy` makes AAP ask OPA *"may this job run?"*; this skill
makes the same library answer *"how compliant is this host against framework
X?"*. One pinned release (`policy_library_version`), two questions. About 3
minutes, most of it the library's own tests running in an initContainer.

This skill contains **no logic**. The work is in
[`playbooks/install_aac_opa.yml`](../../../playbooks/install_aac_opa.yml);
every input is in [`inventory/group_vars/aap/aac.yml`](../../../inventory/group_vars/aap/aac.yml),
which also records why one pod serves three Service names and why it is not
the enforcement pod. See `CLAUDE.md` → *Skills and playbooks*. Plan and
decisions: [#841](https://github.com/ericcames/sales.demos/issues/841).

Two more Compliance as Code pieces live here too, each opt-in and independent
of the other — run them only when the AAC playbooks or AO workflows that use
them are in play:

| Piece | Playbook | AAP job template |
|---|---|---|
| Assessment OPA (below) | `install_aac_opa.yml` | `AAP Ecosystem - Install Compliance Assessment Servers` |
| [Routing OPA](#routing-opa-867) | [`install_opa_routing.yml`](../../../playbooks/install_opa_routing.yml) | `AAP Ecosystem - Install Compliance Routing Server` |
| [Evidence database](#evidence-database-869) | [`install_aac_db.yml`](../../../playbooks/install_aac_db.yml) | `AAP Ecosystem - Install Compliance Evidence Database` |

## What it does

1. Checks the release tarball is reachable, then rolls one Deployment,
   `opa-assessment`, in `policy-as-code`: an initContainer fetches the pinned
   release, a second runs the library's own tests (a failing release never
   serves; the old pod keeps answering), a third builds the 1.2 MB bundle,
   and the server runs it.
2. Creates three ClusterIP Services on 8181 — `opa-security`,
   `opa-compliance`, `opa-ot` — all selecting that pod. These are the names
   `opa_security_url` / `opa_compliance_url` / `opa_ot_url` resolve, which is
   the only way an AAC playbook ever addresses OPA.
3. Asks each Service, through the API service proxy, for a framework's
   `main/compliance_report` on **empty input**, and asserts a populated,
   non-compliant report. `{}` here is the silent failure an assessment would
   later store as an empty result, so it fails the install instead.

Enforcement is untouched: not `OPA_HOST`, not any `opa_query_path`, not the
`opa` pod.

## Preflight Check

```bash
ENV=${ENV:-sandbox}
./utilities/preflight.sh "$ENV" --k8s

# The pinned release is reachable as a tarball (the pod fetches the same URL)
REPO=$(sed -n 's/^policy_library_repo: *//p' inventory/group_vars/aap/opa_policy.yml)
TAG=$(sed -n 's/^policy_library_version: *//p' inventory/group_vars/aap/opa_policy.yml)
curl -fsIL "https://github.com/$REPO/archive/refs/tags/$TAG.tar.gz" >/dev/null \
  && echo "✅ $REPO $TAG tarball reachable" \
  || echo "❌ cannot fetch $REPO $TAG — check policy_library_version in opa_policy.yml"
```

Then confirm the cluster answers — call, do not read config:
`mcp__openshift-<env>__namespaces_list` with
`fieldSelector=metadata.name=policy-as-code` (the namespace is created by
`install_opa.yml`; run `/sales-demos-policy` first if it is absent).

If a check fails, stop and tell the user which one and the fix.

## Collect inputs

| Variable | Default | Meaning |
|---|---|---|
| `ENV` (inventory limit) | `sandbox` | `sandbox`, `demo` or `edge` |
| `aac_opa_state` | `present` | `absent` removes the Deployment and the three Services |

## Run

```bash
./utilities/run-playbook.sh playbooks/install_aac_opa.yml -i inventory --limit "$ENV" -e target_env="$ENV"
```

From AAP instead: `AAP Ecosystem - Install Compliance Assessment Servers`.

## Verify it in the EE before merging a change

```bash
utilities/run-in-ee.sh playbooks/install_aac_opa.yml \
  -i inventory --limit "$ENV" -e target_env="$ENV" \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

## Verify — ask the targets, not the recap

1. **The pod serves a bundle.** `mcp__openshift-<env>__pods_list_in_namespace`
   for `policy-as-code`: one `opa-assessment-*` pod Running, three init
   containers completed. `pods_log` on it shows `Bundle loaded and activated`.
2. **Three Services, one selector.** `mcp__openshift-<env>__resources_list`
   for `Service` in `policy-as-code`: `opa-security`, `opa-compliance`,
   `opa-ot`, each with `app.kubernetes.io/name=opa-assessment`.
3. **A framework answers, and says no.** Through the proxy, `POST
   …/services/http:opa-security:8181/proxy/v1/data/cis_rhel9/main/compliance_report`
   with `{"input": {}}` → `compliant: false`, `failed_controls == total_controls`
   (224). A `{}` answer means the key has no `.main` entrypoint at this release.
4. **Enforcement still blocks.** Launch `Policy as Code - Canary` → **Error**
   with the canary message. If it runs, something other than this playbook
   changed, because this one never touches AAP.

## Undo

`-e aac_opa_state=absent`. The namespace, the enforcement `opa` pod, AAP's
settings and every template are left exactly as they were.

## Routing OPA (#867)

Every AAC Automation Orchestrator workflow has the same spine: an agentic node
*recommends* a route, an HTTP step asks this server for the *decision*, and a
switch acts on the policy's verdict. The agent proposes, the policy disposes.
These are AAC's own routing policies (`aac.golden.routing`,
`aac.tanium.drift_routing`, …), fetched from the public pack
`aac_pack_repo` at `aac_pack_version` (both in
[`aac.yml`](../../../inventory/group_vars/aap/aac.yml)), not from
`rego_policy_libraries`.

What [`install_opa_routing.yml`](../../../playbooks/install_opa_routing.yml)
does:

1. Fetches the listed policy files at the pinned tag into a ConfigMap, then
   rolls Deployment `opa-routing` in `policy-as-code`: an `opa-test`
   initContainer runs the pack's tests before the server starts. Decision logs
   are **on** on purpose — the pod log is the demo's receipt of agent versus
   policy.
2. Creates Service `opa-routing` on 8181 — what `aac_opa_routing_url` resolves.
3. If AO is installed, adds `opa-routing.policy-as-code.svc` to the AO CR's
   `workflowHttpRequestAllowedHosts` and waits for `ao-worker` to roll out
   (#890). If AO is absent it says so and skips this step.
4. Asks the policies, through the API service proxy, and asserts the policy
   overrides the agent on critical drift and fails closed to a human.

### Preflight

```bash
ENV=${ENV:-sandbox}
./utilities/preflight.sh "$ENV" --k8s

# The pinned pack is reachable (the playbook fetches the same raw URLs)
PACK=$(sed -n 's/^aac_pack_repo: *//p' inventory/group_vars/aap/aac.yml)
PTAG=$(sed -n 's/^aac_pack_version: *//p' inventory/group_vars/aap/aac.yml)
curl -fsIL "https://raw.githubusercontent.com/$PACK/$PTAG/opa-routing/policies/routing.rego" >/dev/null \
  && echo "✅ $PACK $PTAG routing policies reachable" \
  || echo "❌ cannot fetch $PACK $PTAG — check aac_pack_version in aac.yml"
```

Then `mcp__openshift-<env>__namespaces_list` with
`fieldSelector=metadata.name=policy-as-code` (absent → `/sales-demos-policy`
first).

### Run

| Variable | Default | Meaning |
|---|---|---|
| `opa_routing_state` | `present` | `absent` removes the Deployment, Service and ConfigMap, and takes the host back out of AO's allowlist |

```bash
./utilities/run-playbook.sh playbooks/install_opa_routing.yml -i inventory --limit "$ENV" -e target_env="$ENV"
```

From AAP instead: `AAP Ecosystem - Install Compliance Routing Server`. In the
EE: the same arguments through `utilities/run-in-ee.sh`, as above.

### Verify — ask the target

1. **The pod passed its tests and serves.**
   `mcp__openshift-<env>__pods_list_in_namespace` for `policy-as-code`: one
   `opa-routing-*` pod Running, the `opa-test` init container completed.
2. **The Service exists.** `mcp__openshift-<env>__resources_list` for
   `Service` in `policy-as-code`: `opa-routing`, selector
   `app.kubernetes.io/name=opa-routing`.
3. **The policy fails closed.** Through the proxy, `POST
   …/services/http:opa-routing:8181/proxy/v1/data/aac/tanium/drift_routing/decision`
   with `{"input": {}}` → `route: approve_remediate`.
4. **AO may call it** (only if AO is installed).
   `mcp__openshift-<env>__resources_get` for `AutomationOrchestrator` `ao` in
   `automation-orchestrator`: `spec.workflowHttpRequestAllowedHosts` contains
   `opa-routing.policy-as-code.svc` — and **not** the `.svc.cluster.local`
   form, which AO refuses whether listed or not.

## Evidence database (#869)

AAC's playbooks store their results in a PostgreSQL database with the
product's own schema. [`install_aac_db.yml`](../../../playbooks/install_aac_db.yml)
adds it as a **second database**, `aac` owned by role `aac`, inside the
existing `policy-db` CloudNativePG cluster — zero new pods. It cannot share
the platform's `compliance` database: both schemas define `host_facts`.

1. Asserts `policy-db` exists and is ready; it adds a database, it never
   creates a cluster.
2. Creates or updates role `aac` with `env_secrets[<env>].aac_db_password`,
   and the database.
3. Fetches the schema task from the pinned AAC pack, applies the same DDL
   through `psql` on the primary, and asserts every table in `aac_db_tables`
   exists and is owned by `aac`. Every statement is idempotent.
4. Optionally restores a gzipped plain-SQL dump from `aac_db_seed_url` — only
   into `aac`, only when `compliance_results` is empty.

Job templates reach it through the `Compliance as Code - Evidence Database`
credential, which reads the same vault key.

### Preflight

```bash
ENV=${ENV:-sandbox}
./utilities/preflight.sh "$ENV" --k8s

# The vault holds the role's password — presence only, never the value
python3 - "$ENV" <<'PY'
import subprocess, sys, yaml
env = sys.argv[1]
out = subprocess.run(["ansible-vault", "view", "playbooks/group_vars/all/secrets.yml",
                      "--vault-id", "sales.demos@~/secrets/.vault_pass_sales_demos"],
                     capture_output=True, text=True, check=True, stdin=subprocess.DEVNULL).stdout
v = (yaml.safe_load(out).get("env_secrets", {}).get(env) or {}).get("aac_db_password")
print(f"✅ env_secrets.{env}.aac_db_password set" if v and v != "CHANGEME-CHANGEME"
      else f"❌ env_secrets.{env}.aac_db_password missing — see secrets.yml.example")
PY
```

Then `mcp__openshift-<env>__resources_list` for
`postgresql.cnpg.io/v1` `Cluster` in `policy-as-code`: `policy-db` with
`readyInstances >= 1`. Absent → `install_policy_db.yml` via
`/sales-demos-policy` first.

### Run

| Variable | Default | Meaning |
|---|---|---|
| `aac_db_state` | `present` | `absent` drops database `aac`, then role `aac` |
| `aac_db_seed_url` | `""` | optional gzipped `pg_dump` to restore into an empty `aac` |
| `aac_db_seed_token` | `""` | optional bearer token for that URL |

```bash
./utilities/run-playbook.sh playbooks/install_aac_db.yml -i inventory --limit "$ENV" -e target_env="$ENV"
```

From AAP instead: `AAP Ecosystem - Install Compliance Evidence Database`. In
the EE: the same arguments through `utilities/run-in-ee.sh`, as above.

### Verify — ask the target

1. **The tables exist and `aac` owns them.** Find the primary with
   `mcp__openshift-<env>__pods_list_in_namespace` for `policy-as-code`
   (label `cnpg.io/instanceRole=primary`), then
   `mcp__openshift-<env>__pods_exec` in container `postgres`:
   `psql -U postgres -d aac -tA -c "SELECT tablename || ':' || tableowner FROM pg_tables WHERE schemaname = 'public' ORDER BY 1"`.
   Every name in `aac_db_tables` appears, each `:aac`.
2. **The platform's database is untouched.** The same query with
   `-d compliance` still lists `host_facts` and `assessments`.

`openshift-demo` is read-only and has no `pods_exec`; on `demo`, read the
playbook's *Assert every table exists* task in the job output instead.

## Undo (routing and database)

- `-e opa_routing_state=absent` — the assessment pod, the enforcement `opa`
  pod and everyone else's AO allowlist entries are left alone.
- `-e aac_db_state=absent` — `policy-db`, the `compliance` database and its
  evidence are untouched.
