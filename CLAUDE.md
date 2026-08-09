# sales.demos — repo conventions

Read [`docs/plan/ocpvirt-demo-plan.md`](docs/plan/ocpvirt-demo-plan.md) before
starting work. It holds the environment research, the design decisions, and the
phase plan, including *why* each choice was made.

## This repo is public

No customer information, ever. No customer name, password, or API token in any
tracked file, commit message, PR title or body, issue, or CHANGELOG.

**RHDP URLs are the documented exception.** `*.dyn.redhatworkshops.io`
hostnames and cluster IDs are ephemeral demo-platform addresses, not
customer-identifying, and are committed in plaintext in `connection.yml` on
purpose. Do not flag them, and do not "fix" them into placeholders.

Audit every diff before pushing:

```bash
git ls-files -z | xargs -0 grep -nEi \
  'sha256~|BEGIN [A-Z ]*PRIVATE KEY|AKIA[0-9A-Z]{16}'
```

Only placeholder lines and the audit pattern itself may match.

## Secrets: exactly one mechanism

`inventory/group_vars/aap/secrets.yml` is the only secrets file. It is
**vault-encrypted and committed**, and lives in the `aap` group directory so it
loads for every environment — one file, both `sandbox` and `demo`.

```bash
ansible-vault edit inventory/group_vars/aap/secrets.yml \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

- **Credentials only.** Per-environment credentials are keyed under
  `env_secrets` by environment name; `connection.yml` selects its slice with
  `env_secrets[aap_env_name]`.
- `connection.yml` is committed plaintext and holds everything that is not a
  credential: `aap_hostname`, `openshift_api_url`, usernames, namespaces. It
  *does* vary per environment — that is the point.
- A new RHDP environment means editing that environment's `connection.yml` plus
  two keys in the vault.
- The vault password is at `~/secrets/.vault_pass_sales_demos` (`600`, in a
  `700` directory), outside this repo, following the same convention as
  `aap_config`'s `.vault_pass_<env>` files.
- `secrets.yml.example` is the **only** `.example` file in the repo. Do not
  create `connection.yml.example` or any other `.example` twin.
- Do **not** introduce a second sourceable secrets file. `docs/dev-environment.sh`
  is retired and must not come back.
- **Never weaken the vault check** in `utilities/check-no-secrets.sh`. Because
  `secrets.yml` is tracked rather than gitignored, that check — a tracked
  `secrets.yml` must begin with `$ANSIBLE_VAULT` — is the only thing preventing
  a plaintext credential file from being pushed publicly. Do not replace it with
  a `.gitignore` rule; that hides the file instead of verifying it.

## Environments

`sandbox` (building against) and `demo` (showing customers). Two only. There is
no `golden` environment — proven-good config is `main` plus a release tag, not a
connection target.

## Skills and playbooks

Every phase is runnable as a skill and as an AAP job template. The skill never
reimplements logic.

- `playbooks/<phase>.yml` does all the work. Idempotent, no interactive prompts,
  every input via `extra_vars`, required vars asserted at the top so both entry
  points fail identically.
- `.claude/skills/<name>/SKILL.md` does preflight checks, collects inputs, and
  invokes the playbook. Follow the shape used in the `aap-skills` repo:
  frontmatter `name` + `description` with explicit **TRIGGER** and **SKIP**
  clauses, then a Preflight Check section of shell one-liners.
- Survey variable names, skill prompt names, and playbook `extra_vars` must
  match exactly. The variable names *are* the contract.

Skills live in `.claude/skills/` and are discovered natively — no marketplace,
no `plugin.json`. The `aap-skills` plugin stays installed and untouched for
other demos.

### Nothing deploys from CI

GitHub Actions is a pull-request gate only: lint, secret hygiene, skill
portability. Do not add a deploy workflow — that was decided and closed in #7.

Anything touching an environment runs via `ansible-playbook`, either wrapped by
a skill or as an AAP job template. This is what keeps every environment-specific
value in the gitignored `secrets.yml` instead of a second copy in GitHub
Environment secrets.

## Ansible

- **AAP 2.6** — this catalog item ships 2.6 on the OpenShift operator. Pin to it.
  `aap_config` targets 2.7; do not copy its connection settings verbatim.
- **`ansible.platform` over `ansible.controller`** — controller is legacy.
- **Always clean up tokens** — any playbook creating a token must delete it in an
  `always:` block so stale tokens do not accumulate.
- **Never ship a project-local `ansible.cfg`** — Ansible picks one cfg file and
  does not merge. A local one shadows `~/.ansible.cfg`, which holds the working
  Automation Hub token, and breaks `ansible-galaxy collection install` for Red
  Hat certified content. Set inventory and options via CLI flags or env vars.
- Pin collections in `requirements.yml`.

## Terraform

- Official `hashicorp/kubernetes` provider with `kubernetes_manifest`. Do not add
  a community KubeVirt provider.
- `terraform/` is keyed by **platform**, not by demo — demos reuse platforms.
- State and `*.tfvars` are gitignored and must stay that way.

## Workflow

- **Document before fixing** — open a GitHub issue before making code changes.
- **Always label new issues** — run `gh label list --repo ericcames/sales.demos`
  and apply every label that genuinely fits.
- **One concern per PR** — group by shared root cause. Would you revert these
  together? Then ship them together.
- **Additive only** — do not remove working capability until the replacement is
  proven.
- **Maintain `CHANGELOG.md`.**
