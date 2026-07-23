# Security Policy

## Scope

This repository holds **sales demo automation** — playbooks, Terraform, AAP
configuration-as-code, skills, and docs. It contains **no live credentials,
tokens, or environment-specific values**.

This repository is **public**.

## What should never be committed

- AAP tokens, passwords, OAuth tokens, OpenShift bearer tokens, or vault passwords
- Customer or company names, RHDP deployment URLs, or cluster/instance IDs —
  committed files use generic placeholders (`api.cluster-<id>.dyn.redhatworkshops.io`)
- Terraform state or `*.tfvars` — both are gitignored and can contain secrets in
  plaintext
- Kubeconfigs

Every environment-specific value belongs in
`inventory/group_vars/<env>/secrets.yml`, which is gitignored. See
[CONTRIBUTING.md](../CONTRIBUTING.md).

## Automated enforcement

`utilities/check-no-secrets.sh` runs on every pull request and push to `main`
via [`.github/workflows/lint.yml`](workflows/lint.yml). It matches the *shape*
of real credentials, so documentation discussing tokens and `.example`
placeholders pass, while genuine values fail the build.

It is a safety net, not a substitute for reading your own diff.

## Reporting

If you find a credential or customer identifier committed here, please open an
issue **without quoting the value** and it will be rotated and purged from
history.
