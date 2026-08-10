# Security Policy

## Scope

This repository holds **sales demo automation** — playbooks, Terraform, AAP
configuration-as-code, skills, and docs. It contains **no live credentials in
plaintext**. It does contain credentials, deliberately: one vault-encrypted,
committed secrets file (see below).

This repository is **public**.

## What should never be committed

- AAP tokens, passwords, OAuth tokens, OpenShift bearer tokens, or vault passwords
  **in plaintext** — they belong in the vault-encrypted secrets file below
- **Customer or company names** — never, in any form, in any file, commit
  message, PR title or body, issue, or CHANGELOG
- Terraform state or `*.tfvars` — both are gitignored and can contain secrets in
  plaintext
- Kubeconfigs
- SSH private keys, outside the vault-encrypted secrets file

## RHDP URLs are the documented exception

`*.dyn.redhatworkshops.io` hostnames and cluster IDs **are committed in
plaintext, on purpose**, in each environment's `connection.yml`. They are
ephemeral demo-platform addresses, not customer-identifying.

**Do not "fix" them into placeholders.** Both environments resolve through those
values; replacing them breaks the repo, and `check-no-secrets.sh` deliberately
does not flag them, so nothing mechanical would catch the mistake — CI would
stay green while nothing worked.

Customer data remains forbidden. The exception is narrow: RHDP addresses only.

## Where things live

| | Where | State |
|---|---|---|
| Credentials | `playbooks/group_vars/all/secrets.yml` | **vault-encrypted and committed** |
| Everything else per-environment — hostnames, API URLs, usernames, namespaces | `inventory/group_vars/<env>/connection.yml` | committed plaintext |
| The vault password | `~/secrets/.vault_pass_sales_demos` | outside the repo, `600` |

The secrets file is **tracked rather than gitignored** on purpose: gitignoring
would hide it instead of verifying it. `check-no-secrets.sh` enforces that a
tracked `secrets.yml` begins with `$ANSIBLE_VAULT`, which is the check standing
between a plaintext credential file and a public push. See
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
