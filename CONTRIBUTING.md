# Contributing

## Never commit

- AAP tokens, passwords, OAuth tokens, bearer tokens, or vault passwords
- Customer or company names, or any hostname that identifies a customer's estate
- Real values in any tracked file, commit message, PR title or body, or issue

Use generic placeholders in committed docs and examples:
`api.cluster-<id>.dyn.redhatworkshops.io`.

## Where values live

`playbooks/group_vars/all/secrets.yml` is **vault-encrypted and local only — it
is not tracked** — and is the only secrets mechanism in this repo. It sits in the
`all` group directory so it loads for every host — `sandbox`, `demo`, `edge`,
`gpu`, and the demo VMs.

On a fresh clone it does not exist. Build it from `secrets.yml.example`, which
is the contract and is kept honest by CI (#128):

```bash
cp playbooks/group_vars/all/secrets.yml.example \
   playbooks/group_vars/all/secrets.yml
# fill in real values, then:
ansible-vault encrypt playbooks/group_vars/all/secrets.yml \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

```bash
ansible-vault edit playbooks/group_vars/all/secrets.yml \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

**It holds credentials only.** Per-environment credentials are keyed under
`env_secrets` by environment name. Everything that is not a credential —
`aap_hostname`, `openshift_api_url`, usernames, namespaces — lives in the
committed plaintext `inventory/group_vars/<env>/connection.yml`. The one
exception is `gpu`, which has no AAP and no per-environment passwords, so its
credentials are the top-level keys `gpu_admin_password` and
`gpu_openshift_api_token` — see [CLAUDE.md § GPU/AI
inference](CLAUDE.md#gpuai-inference).

**A new RHDP environment means `local.yml` plus two keys in the vault — not
`connection.yml`.** Copy `inventory/group_vars/<env>/local.yml.example` to
`local.yml` (gitignored) and fill in your cluster's values. Ansible loads a
`group_vars/<env>/` directory in sorted order, so `local.yml` overrides
`connection.yml` with no code change, and you can `git pull` without conflicting
with anyone else's cluster. The name matters: `connection.local.yml` sorts
*before* `connection.yml` and silently loses.

Do not edit `connection.yml` during a bootstrap or repoint — a stale one is the
expected state during active development. Committing it is a separate,
deliberate step once the environment is stable:
`utilities/update-connection.sh <env>` (#513). See [conventions
rationale](https://ericcames.github.io/sales.demos-docs/reference/conventions-rationale/#the-localyml-overlay-and-what-it-replaced)
for how `local.yml` reaches AAP through `config.yml`.

The vault password lives outside this repo at
`~/secrets/.vault_pass_sales_demos` (`chmod 600`, `chmod 700` directory),
alongside the other `.vault_pass_*` files. It is the one secret that cannot be
vaulted. Losing it makes your secrets file unrecoverable, and since #130 that
file is no longer in git either — **back up both**.

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

**Do not create `connection.yml.example` or any new `.example` file without the
same justification the existing ones have**, and do not add a second sourceable
secrets file — `docs/dev-environment.sh` is retired here.

Three `.example` files exist — `secrets.yml.example` (the gitignored
vault-encrypted secrets file), `terraform.tfvars.example` (the gitignored
Terraform vars), and `local.yml.example` (one per environment — the gitignored
laptop overlay, #499). All three follow the same rule: a gitignored file whose
shape nothing else documents. Adding another needs that same justification.

`connection.yml.example` in particular remains wrong because `connection.yml` is
committed and IS the reference — an example twin would be redundant.

## Audit before every push

This repo is public.

```bash
git ls-files -z | xargs -0 grep -nEi \
  'sha256~|BEGIN [A-Z ]*PRIVATE KEY|AKIA[0-9A-Z]{16}'
```

Only placeholder lines, prose, and the audit pattern itself may match. Keep the
pattern generic — never hardcode a real value into the check.

`utilities/check-no-secrets.sh` runs this in CI along with the checks that
matter most: **nothing named `secrets.yml` may be tracked**, and **the
`.gitignore` rule that keeps it untracked must actually match**, tested with
`git check-ignore`. A tracked one, if it somehow exists, must still begin with
`$ANSIBLE_VAULT`.

Do not weaken any of the three. In particular, do not "fix" a failure by
deleting the ignore rule — the rule is not trusted here, it is *verified*, and
removing it fails the build. That verification is the point: simply gitignoring
the file and keeping the old check would have been **silent**, because every
pattern in that script reads from `git ls-files`, and an untracked file is
invisible to all of them.

## Ansible standards

- Variables load **implicitly from `inventory/group_vars/`** by group membership.
  Do not add `vars_files:` or `include_vars:` to load them from a files folder.
  Select an environment with `--limit <env>`.
- Shared, demo-agnostic config lives in `group_vars/aap/`; per-environment
  values in `group_vars/<env>/`.
- **AAP 2.7** — pin to it. The catalog item moved and #92's environment arrived
  on 2.7; the gateway reports `2.7` and the controller behind it `4.8.6`. This
  line said 2.6 until #122. Quote which version you mean: `4.8.x` is the
  controller, `2.7` is the platform, and reading the first as the second is how
  the stale 2.6 pin survived unnoticed.
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

**Run ad-hoc playbooks through `utilities/run-playbook.sh`.** It names the log,
writes it to `~/ansible-logs/` — never into this repo — passes the vault id, and
reports the real exit status:

```bash
./utilities/run-playbook.sh playbooks/config.yml --limit sandbox -e target_env=sandbox
```

Never pipe a run through `tee`: in a pipeline the exit status comes from `tee`,
so a failed run reports success.

**Verify a playbook change in the EE before it merges** (#120). `ansible-playbook`
runs against your laptop's collections and python; a job template runs against
what the execution environment baked in. CI cannot tell them apart — the lint
gate executes nothing — so a laptop run alone verifies the wrong dependency set.

```bash
utilities/run-in-ee.sh playbooks/<phase>.yml -i inventory --limit sandbox \
  -e target_env=sandbox --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

Everything after the playbook is identical to the `ansible-playbook` command.
Add `--with-hub-token` for `config.yml`, `validate.yml`, `setup.yml`,
`sync_hub.yml`, `curate_hub.yml`. `/sales-demos-verify-ee` walks it.

**Run CI's ansible-lint locally only with a throwaway `ANSIBLE_HOME`** (#601).
CI pins the version in `.github/workflows/lint.yml`. Because `.ansible-lint` sets
`offline: true`, ansible-lint 26.x writes its `mock_modules` stubs into
`ANSIBLE_HOME`, and on a laptop that is `~/.ansible`, on top of your real
collections. A bare run once replaced 24 modules, and `config.yml` failed with
`Supported parameters include: .` (an empty list).

```bash
pip install ansible-lint==26.8.0   # in a venv; match lint.yml
ANSIBLE_HOME="$(mktemp -d)" ansible-lint
```

Verified: every file under `~/.ansible/collections` hashed identically before
and after, and the stubs landed in the temporary directory. If a run has already
corrupted your collections, the
[`/sales-demos-collections-sync`](https://github.com/ericcames/sales.demos/blob/main/.claude/skills/sales-demos-collections-sync/SKILL.md)
audit reports `MODIFIED` and shows how to repair them.

## Workflow

1. **Open an issue before writing code.** Label it — run
   `gh label list --repo ericcames/sales.demos` and apply every label that fits.
2. **Work in an isolated worktree, never in the main checkout.** More than one
   Claude Code session can share a checkout, and the branch can change under
   you, so the main checkout stays on `main` and is read-only. Name the branch
   `<type>-<issue>-<slug>` — `fix-86-preflight-vault-lookup`:

   ```bash
   git worktree add ../sales.demos-<slug> -b <type>-<issue>-<slug> origin/main
   # ... work, commit, push, PR ...
   git worktree remove ../sales.demos-<slug>
   ```

   A new worktree does not get your gitignored files (`secrets.yml`,
   `local.yml`). See [conventions
   rationale](https://ericcames.github.io/sales.demos-docs/reference/conventions-rationale/#the-worktree-mandate)
   for the incident behind this.
3. Make one focused change. One concern per PR — group by shared root cause, not
   item count. The test: would you revert these together? Then ship them
   together. Behavior changes and anything risky stay isolated regardless.
4. Update [`ROADMAP.md`](ROADMAP.md) if the plan changes, and
   [`CLAUDE.md`](CLAUDE.md) if a convention changes.
5. Run the phase against `sandbox` with `utilities/run-playbook.sh` — and run
   it in the EE too, per *Skills and playbooks* above. A green CI run proves neither.
6. Run the leak audit above.
7. Open a PR with a summary, a test plan, and a rollback note.

**There is no changelog to update.** The per-PR obligation was retired in #432.
What changed lives in `git log` and the closed issue; the accumulated history is
archived at <https://ericcames.github.io/sales.demos-docs/reference/history/>.

**Additive only** — do not remove a working capability until its replacement is
proven.
