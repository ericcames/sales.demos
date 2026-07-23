# Contributing

Contributions to `aap_config` are welcome — playbooks, inventory/CaC content,
GitHub Actions, runbooks, AI-assist prompts, and docs. This repo is a
**config-as-code starter kit** that teaches sysadmins to export AAP 2.7 objects
from a production instance into Git and load them into on-prem dev/qa/prod via
GitHub Actions. **Read [`AGENTS.md`](AGENTS.md) first** — it is the canonical
guidance (purpose, layout, the Ansible standards, how to run everything). Then
skim [`README.md`](README.md) and [`ROADMAP.md`](ROADMAP.md).

## Content & secret policy

**Never commit:**

- AAP tokens, passwords, OAuth tokens, or vault passwords
- Customer or company names, or any hostname that identifies a customer's estate
  — use generic placeholders (e.g. `controller-<id>.apps.<cluster>.rhdp.net`)
  in `.example` files and docs
- Real values in exported credential files — they must stay `{{ vaulted_* }}`

All secrets — connection credentials AND CaC object values — go in
vault-encrypted `inventory/group_vars/<env>/secrets.yml`. Non-secret connection
settings (hostname, cert validation) go in the committed `connection.yml` in the
same directory. Audit every diff before pushing. The pre-commit hook and CI run
`utilities/check-vault-encrypted.sh` + `utilities/scan-exports.sh`.

**Ephemeral lab URLs are fine to commit.** RHDP `*.redhatworkshops.io` hostnames
and their cluster IDs identify a short-lived demo environment, not a customer, so
they live in the real `connection.yml` as above. The rule is about *customer*
identity, not about URLs in general.

## The Ansible standard that trips people up

Object variables load **implicitly from `inventory/group_vars/`** by group
membership — **do not** add `vars_files:` or `include_vars:` to load them from a
files folder. Environment is selected with `--limit <env>`. Shared objects live in
`group_vars/aap/`; per-env deltas + secrets in `group_vars/<env>/`; they merge via
the `*_all` / `*_<env>` suffix convention and `dispatch_include_wildcard_vars`.
See AGENTS.md → "Ansible standards".

## Workflow

1. Branch off `main` (`main` is protected — all changes land via PR).
2. Make one focused change. Keep YAML and Ansible clean:
   - `yamllint .` against [`.yamllint`](.yamllint)
   - `ansible-lint` against [`.ansible-lint`](.ansible-lint)

   Both run in CI on every PR. If you call a new certified module that isn't
   installed in CI, add it to `mock_modules` in `.ansible-lint`.
3. Update [`CHANGELOG.md`](CHANGELOG.md) under `[Unreleased]`
   (Added / Changed / Fixed / Removed).
4. Update [`ROADMAP.md`](ROADMAP.md) phase status if the plan changes, and
   [`AGENTS.md`](AGENTS.md) if the layout or a convention changes.
5. Open a PR using the template; fill in Summary, Test plan, and Risk/rollback.

## Pull requests

- One concern per PR — group by shared root cause, not item count. The test:
  would you revert these changes together?
- Descriptive title, e.g. `Add gateway_organizations to config/all`.
- Behavior changes and anything risky stay isolated.
- Additive only — don't remove old capabilities until replacements are proven.
