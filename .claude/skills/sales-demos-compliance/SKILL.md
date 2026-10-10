---
name: sales-demos-compliance
description: "Deploy Compliance as Code — the AAC assessment layer: one OPA pod in policy-as-code serving the pinned ynotbhatc/rego_policy_libraries release as a bundle behind opa-security, opa-compliance and opa-ot, proven to answer a framework report on empty input. Runs playbooks/install_aac_opa.yml after install_opa.yml. TRIGGER when: the user wants to assess a host against CIS, STIG, NIST or another framework with policy (not OpenSCAP), set up or remove the AAC assessment servers, asks about opa_security_url / opa_compliance_url / opa_ot_url, Compliance as Code, AAC, or issue #841 / #868. SKIP: if the user wants AAP to block a job launch — that is sales-demos-policy (Policy as Code) — or the OpenSCAP scan of a VM — that is Linux Day 1 - 4 Compliance Scan."
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
