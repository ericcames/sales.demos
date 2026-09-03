# Security Policy

## Scope

This repository holds **sales demo automation** — playbooks, Terraform, AAP
configuration-as-code, skills, and docs. It contains **no live credentials in
plaintext**, and since #130 it does not contain credentials at all: the one
secrets file is vault-encrypted and local only (see below).

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
| Credentials | `playbooks/group_vars/all/secrets.yml` | **vault-encrypted, local only, never tracked** |
| Everything else per-environment — hostnames, API URLs, usernames, namespaces | `inventory/group_vars/<env>/connection.yml` | committed plaintext |
| The vault password | `~/secrets/.vault_pass_sales_demos` | outside the repo, `600` |

The secrets file is **gitignored, and that ignore rule is itself verified**.
`utilities/check-no-secrets.sh` fails the build if anything named `secrets.yml`
is tracked, if the `.gitignore` rule stops matching (`git check-ignore`), or if
a tracked one is not `$ANSIBLE_VAULT`-encrypted.

The distinction matters. Gitignoring the file and keeping the previous check
would have been silent: every pattern in that script reads from `git ls-files`,
so an untracked plaintext credential file is invisible to all of them and CI
would report "passed". The rule is not trusted; it is checked.

**Credentials committed before #130 remain in git history.** They were
vault-encrypted, and the environments they addressed are ephemeral and expire,
but treat anything that was in that file as disclosed.

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
