# sales.demos — repo conventions

Read the plan doc for the use case you are touching before starting work. Each
holds the environment research, the design decisions, and the phase plan,
including *why* each choice was made.

| Use case | Plan |
|---|---|
| OpenShift Virtualization | [`docs/plan/ocpvirt-demo-plan.md`](docs/plan/ocpvirt-demo-plan.md) |
| Private Automation Hub as code | [`docs/plan/pah-plan.md`](docs/plan/pah-plan.md) |

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

`playbooks/group_vars/all/secrets.yml` is the only secrets file. It is
**vault-encrypted and committed**, and lives in the `all` group directory so it
loads for every host — both environments, *and the demo VMs*.

It was `group_vars/aap/` until #5, which is scoped to hosts in the `aap` group.
That was invisible until a playbook targeted something else: `run_demo.yml` runs
against `linuxweb`, so the guests never received the registration credentials and
failed an assert that looked like a missing Vault credential. `all` is the only
scope that covers every play without a second secrets file.

**It sits beside the PLAYBOOKS, not the inventory, and that is not cosmetic.**
Ansible loads `group_vars/` adjacent to the playbook as well as adjacent to the
inventory, so it resolves identically either way. What differs is AAP: a job
template's inventory is synced from `inventory/hosts.yml` by an SCM inventory
source, and that sync runs `ansible-inventory`, which parses every `group_vars`
file next to the inventory. Three things follow, all verified against a live
AAP 2.6 (#4):

- With the vaulted file under `inventory/group_vars/`, the sync dies with
  `ERROR! Attempting to decrypt but no vault secrets found`.
- It cannot be given the password: AAP rejects Vault credentials on SCM
  inventory sources outright — *"Credentials of type insights and vault are
  disallowed for scm inventory sources."*
- Smuggling the password in via a custom credential type **would** work and is
  the wrong thing to do: the sync would then write `env_secrets` and the SSH
  private key into AAP's inventory variables in plaintext, visible in the UI.

Keeping secrets out of the inventory tree is what lets the sync parse
`connection.yml` freely while the credentials stay encrypted and arrive at run
time through the job template's Vault credential. Do not move it back.

```bash
ansible-vault edit playbooks/group_vars/all/secrets.yml \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

- **Credentials only.** Per-environment credentials are keyed under
  `env_secrets` by environment name; `connection.yml` selects its slice with
  `env_secrets[aap_env_name]`.
- **The Red Hat offline token is NOT in the vault**, and that was decided twice.
  `~/.ansible.cfg` `[galaxy_server.rh_certified]` is the one authoritative copy
  (#22), and PAH's certified and validated remotes read it from there (#68). A
  vaulted fallback for execution environments was built, verified working, and
  removed: it bought one job template at the cost of a second copy of a rotating
  credential. The consequence is that PAH work is laptop-only, like `config.yml`.
  Do not add it back without a reason that outweighs the rotation cost.
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
  invokes the playbook. Follow the shape of the skills already here — see
  `.claude/skills/ocpvirt-setup/SKILL.md`: frontmatter `name` + `description`
  with explicit **TRIGGER** and **SKIP** clauses, then a Preflight Check section
  of shell one-liners, and a verification step that asks the target rather than
  trusting the Ansible recap.
- Survey variable names, skill prompt names, and playbook `extra_vars` must
  match exactly. The variable names *are* the contract.

Skills live in `.claude/skills/` and are discovered natively — no marketplace,
no `plugin.json`.

**This repo is self-contained.** Never send a user to a skill from another repo
or plugin, and never build a workflow here that depends on one. If something is
missing, add it here. Other plugins may be installed on the same machine for
other demos; they stay untouched, and nothing here relies on them. The
`sales-demos-` prefix on repo-wide skills keeps them unambiguous when other
skills are loaded alongside.

### Nothing deploys from CI

GitHub Actions is a pull-request gate only: lint, secret hygiene, skill
portability. Do not add a deploy workflow — that was decided and closed in #7.

Anything touching an environment runs via `ansible-playbook`, either wrapped by
a skill or as an AAP job template. This is what keeps every environment-specific
value in the vault-encrypted `secrets.yml` instead of a second copy in GitHub
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
