# Contributing

## Never commit

- AAP tokens, passwords, OAuth tokens, bearer tokens, or vault passwords
- Customer or company names, or any hostname that identifies a customer's estate
- Real values in any tracked file, commit message, PR title or body, issue, or
  CHANGELOG entry

Use generic placeholders in committed docs and examples:
`api.cluster-<id>.dyn.redhatworkshops.io`.

## Where values live

`playbooks/group_vars/all/secrets.yml` is **vault-encrypted and committed**, and
is the only secrets mechanism in this repo. It sits in the `all` group directory
so it loads for every environment — one file, both `sandbox` and `demo`.

```bash
ansible-vault edit playbooks/group_vars/all/secrets.yml \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

**It holds credentials only.** Per-environment credentials are keyed under
`env_secrets` by environment name. Everything that is not a credential —
`aap_hostname`, `openshift_api_url`, usernames, namespaces — lives in the
committed plaintext `inventory/group_vars/<env>/connection.yml`.

A new RHDP environment therefore means editing that environment's
`connection.yml` plus two keys in the vault.

The vault password lives outside this repo at
`~/secrets/.vault_pass_sales_demos` (`chmod 600`, `chmod 700` directory),
alongside the other `.vault_pass_*` files. It is the one secret that cannot be
vaulted, and losing it makes the committed file unrecoverable.

> **RHDP URLs are not sensitive here**, matching
> [`aap_config`](https://github.com/ericcames/aap_config). A
> `*.dyn.redhatworkshops.io` hostname is publicly resolvable, is not a
> credential, and points at a cluster that expires in days. Keeping them
> readable in `connection.yml` is what lets the vaulted file hold credentials
> only.
>
> Tokens are a separate matter. A live bearer token in a public repo is scraped
> within minutes. That one is absolute — which is why the CI guard fails on a
> tracked `secrets.yml` that is not vault-encrypted.

`secrets.yml.example` is the **only** `.example` file in the repo. Do not create
`connection.yml.example` or any other `.example` twin, and do not add a second
sourceable secrets file — `docs/dev-environment.sh` is retired here.

## Audit before every push

This repo is public.

```bash
git ls-files -z | xargs -0 grep -nEi \
  'sha256~|BEGIN [A-Z ]*PRIVATE KEY|AKIA[0-9A-Z]{16}'
```

Only placeholder lines, prose, and the audit pattern itself may match. Keep the
pattern generic — never hardcode a real value into the check.

`utilities/check-no-secrets.sh` runs this in CI along with the check that
matters most under the vault model: **a tracked `secrets.yml` must begin with
`$ANSIBLE_VAULT`.** Since `secrets.yml` is no longer gitignored, that check is
the only thing standing between a plaintext credential file and a public push.
Do not weaken it, and do not "fix" a failure by re-adding an ignore rule — that
would hide the file rather than verify it.

## Ansible standards

- Variables load **implicitly from `inventory/group_vars/`** by group membership.
  Do not add `vars_files:` or `include_vars:` to load them from a files folder.
  Select an environment with `--limit <env>`.
- Shared, demo-agnostic config lives in `group_vars/aap/`; per-environment
  values in `group_vars/<env>/`.
- **AAP 2.6** — pin to it. This catalog item ships 2.6 on the OpenShift operator.
- **`ansible.platform` over `ansible.controller`** — controller is legacy.
- **Always clean up tokens** — any playbook that creates one must delete it in an
  `always:` block.
- **Never add a project-local `ansible.cfg`** — Ansible picks one cfg file and
  does not merge. A local one shadows `~/.ansible.cfg`, which holds the working
  Automation Hub token, and breaks certified content installs. Use CLI flags or
  environment variables instead.

## Skills and playbooks

Every phase runs both as a Claude Code skill and as an AAP job template. The
skill never reimplements logic — both drive the same playbook.

- `playbooks/<phase>.yml` does the work: idempotent, no interactive prompts,
  every input via `extra_vars`, required vars asserted at the top so both entry
  points fail identically.
- `.claude/skills/<name>/SKILL.md` does preflight checks, collects inputs, and
  invokes the playbook.
- Survey variable names, skill prompts, and playbook `extra_vars` must match
  exactly. **The variable names are the contract.**

## Workflow

1. **Open an issue before writing code.** Label it — run
   `gh label list --repo ericcames/sales.demos` and apply every label that fits.
2. Branch off `main`.
3. Make one focused change. One concern per PR — group by shared root cause, not
   item count. The test: would you revert these together? Then ship them
   together. Behavior changes and anything risky stay isolated regardless.
4. Update [`CHANGELOG.md`](CHANGELOG.md) under `[Unreleased]`.
5. Update [`ROADMAP.md`](ROADMAP.md) if the plan changes, and
   [`CLAUDE.md`](CLAUDE.md) if a convention changes.
6. Run the leak audit above.
7. Open a PR with a summary, a test plan, and a rollback note.

**Additive only** — do not remove a working capability until its replacement is
proven.
