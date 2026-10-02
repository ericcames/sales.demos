---
name: sales-demos-policy
description: "Deploy AAP Policy as Code backed by OPA: one OPA server on the cluster loaded with the pinned ynotbhatc/rego_policy_libraries release, AAP pointed at it, and the policy attached to the `Policy as Code - Hello` demo template. Runs playbooks/install_opa.yml after config.yml, then proves it from AAP — a blocked launch and an allowed one. TRIGGER when: the user wants to demo or set up Policy as Code, policy enforcement, OPA or Open Policy Agent with AAP, wants a job blocked by policy, asks about rego_policy_libraries, opa_query_path or OPA_HOST, or asks about issue #841. SKIP: if the user wants CIS/STIG compliance scanning of VMs — that is sales-demos-ocpvirt-demo (OpenSCAP) — or Kubernetes admission policy (Gatekeeper), which this repo does not deploy."
---

# sales-demos-policy

Deploy AAP's **Policy as Code** feature end to end: AAP asks an OPA server
*"may this job run?"* before launching a guarded job, and blocks it with a
readable reason when the answer is no. Takes about 2 minutes.

This skill contains **no logic**. The work is in
[`playbooks/install_opa.yml`](../../../playbooks/install_opa.yml); every input
is in [`inventory/group_vars/aap/opa_policy.yml`](../../../inventory/group_vars/aap/opa_policy.yml),
which also records how AAP calls OPA. See `CLAUDE.md` → *Skills and playbooks*.

## What it does

1. `config.yml` (existing) sets `OPA_HOST`/`OPA_PORT` and creates the
   `Policy as Code - Hello` template.
2. `install_opa.yml` fetches the policies from
   [`ynotbhatc/rego_policy_libraries`](https://github.com/ynotbhatc/rego_policy_libraries)
   at the pinned tag, runs their own tests in an initContainer, starts one OPA
   pod behind a ClusterIP Service, and asks it two questions through the API
   service proxy.
3. It asserts AAP is pointed at the server, then attaches each entry in
   `opa_policy_associations` through the controller API — no collection
   module accepts `opa_query_path` yet: `extra_vars_control` on
   `Policy as Code - Hello`, `deny_all` on `Policy as Code - Canary`.

`config.yml` also creates the demo identity, `policy-demo` in `app-team`
(`policy_demo_rbac.yml`), with Execute on those two templates only.

**Policies are attached to demo templates only, never an organization.** The
library denies superuser launches by default, and this platform runs as admin.

## Preflight Check

```bash
ENV=${ENV:-sandbox}
./utilities/preflight.sh "$ENV" --k8s

# The library tag is reachable from here (AAP's EE needs the same access)
TAG=$(sed -n 's/^policy_library_version: *//p' inventory/group_vars/aap/opa_policy.yml)
curl -fsI "https://raw.githubusercontent.com/ynotbhatc/rego_policy_libraries/$TAG/enforcement/aap/extra_vars_control.rego" >/dev/null \
  && echo "✅ rego_policy_libraries $TAG reachable" \
  || echo "❌ cannot fetch rego_policy_libraries $TAG — check the tag in opa_policy.yml"
```

Then confirm the cluster and AAP answer — call, do not read config:

- `mcp__openshift-<env>__namespaces_list` with `fieldSelector=metadata.name=default`
- `mcp__aap-<env>__me_list`

If any check fails, stop and tell the user which one and the fix. Do not run
with a failing prerequisite.

## Collect inputs

| Variable | Default | Meaning |
|---|---|---|
| `ENV` (inventory limit) | `sandbox` | `sandbox`, `demo` or `edge` |

## Run

`config.yml` first — it owns `OPA_HOST` and the demo template, and
`install_opa.yml` asserts both instead of creating them:

```bash
./utilities/run-playbook.sh playbooks/config.yml -i inventory --limit "$ENV" -e target_env="$ENV"
./utilities/run-playbook.sh playbooks/install_opa.yml -i inventory --limit "$ENV" -e target_env="$ENV"
```

The wrapper names the log in `~/ansible-logs/`, passes the vault id and
reports the real exit status. Never pipe a run through `tee`.

From AAP instead: launch `AAP Ecosystem - Install Policy Server` after
`config.yml` has run.

## Verify it in the EE before merging a change

See `/sales-demos-verify-ee`. The one command:

```bash
utilities/run-in-ee.sh playbooks/install_opa.yml \
  -i inventory --limit "$ENV" -e target_env="$ENV" \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

## Verify — ask the targets, not the recap

1. **OPA is running.** `mcp__openshift-<env>__pods_list_in_namespace` for
   `policy-as-code` — one `opa-*` pod, Running, init container completed.
2. **AAP is pointed at it.** `mcp__aap-<env>__settings_retrieve` with
   `category_slug=policyascode` — `OPA_HOST` is
   `opa.policy-as-code.svc.cluster.local`, port `8181`.
3. **The policy blocks, through AAP.** Launch `Policy as Code - Hello` twice
   (API, because `job_templates_launch_create` drops extra_vars):
   - with `{"greeting": "hello"}` → job **successful**
   - with `{"greeting": "hello", "db_password": "x"}` → job **failed** before
     running, with *"looks like a secret — pass it through a credential or
     Ansible Vault"* in its explanation
4. **The canary is blocked.** Launch `Policy as Code - Canary` with no extra
   vars → job **failed** before running, with *"All automation is blocked:
   this is the Policy as Code wiring canary"*. It is attached to `deny_all`
   and must never run. **If it runs, AAP is not reaching OPA**, and every
   other "allowed" result above proves nothing: the policies default a
   missing field to allowed, so broken wiring looks like a permissive policy.
5. **As a non-admin.** Launch `Hello` with basic auth as `policy-demo`
   (password `env_secrets[<env>].policy_demo_password`) → successful, and its
   decision-log input shows `"is_superuser": false` and
   `"teams": [{"id": …, "name": "app-team"}]`.
6. **OPA saw them all.** `mcp__openshift-<env>__pods_log` on the OPA pod — two
   `decision_id` entries per launch, carrying the full input AAP sent. Filter
   the log on `"msg":"Decision Log"` — health probes fill the rest.

If launch 3b or the canary *succeeds*, enforcement is off: check step 2 and
the template's `opa_query_path`.

## Undo

Clear `opa_query_path` on the template (PATCH it to `""`) and the template
runs unguarded; delete the `policy-as-code` namespace to remove the server.
With no path attached anywhere, `OPA_HOST` being set does nothing.
