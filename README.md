# sales.demos

Sales demo automation, built as code. Each demo can be run two ways — as a
Claude Code skill from your laptop, or as a job template inside Ansible
Automation Platform — driving the same playbooks either way.

> **Status:** early. Only the OpenShift Virtualization demo
> (`demos/ocpvirt/`) is in scope right now. The layout admits more demos later;
> nothing has been migrated yet and that decision is deliberately open.

## The demo: OpenShift Virtualization on the RHDP "Ansible Product Demo"

Terraform provisions Windows and Linux VMs onto OpenShift Virtualization with
small / medium / large t-shirt sizing, AAP registers them as managed hosts, and
the existing daily-demo content layers on top unchanged.

The full research findings, design decisions, and phase-by-phase plan are in
[`docs/plan/ocpvirt-demo-plan.md`](docs/plan/ocpvirt-demo-plan.md). Read that
first — it records *why* things are the way they are, not just what to do.

## Layout

Two independent axes, kept separate so adding demos later does not multiply out:

```
.claude/skills/<name>/SKILL.md   in-repo skills, discovered when the repo is open
demos/ocpvirt/                   demo content — job templates, surveys
inventory/group_vars/
  aap/                             shared, demo-agnostic config
  sandbox/  demo/                  per-environment connection + secrets
terraform/ocpvirt/               keyed by PLATFORM, not demo — demos reuse platforms
playbooks/                       the work: one playbook per phase
```

A **demo** is selected by extra-var or CI matrix. An **environment** is selected
by inventory group.

## Environments

- **`sandbox`** — the RHDP env you are actively building against and breaking.
- **`demo`** — the RHDP env you show customers.

There is deliberately **no `golden` environment**. "This config is proven good"
is a state of the config, not a connection target — git already models that with
`main` plus a release tag.

### Telling them apart at the sign-in page

Both environments look identical at the AAP login page, and the moment you are
most likely to act on the wrong one is the moment before you have touched
anything. Each gets a badged sign-in logo:

![sandbox](docs/images/logo-sandbox.png)

![demo](docs/images/logo-demo.png)

Green for the environment you break, red for the one you show customers —
the same severity convention as `aap_config`. Regenerate with:

```bash
python3 utilities/make-env-logo.py --env sandbox
```

This sets the gateway's `custom_logo`, which changes the **sign-in page only**.
The post-login masthead is a bundled UI asset, not a setting — verified on AAP
2.6, where none of the 44 gateway settings mark the environment after login.

## Secrets: one vaulted file, both environments

`inventory/group_vars/aap/secrets.yml` is **vault-encrypted and committed**. It
sits in the `aap` group directory, so it loads for `sandbox` and `demo` alike —
one file, no per-environment copy to keep in step.

On a fresh clone you do not create it. You already have it; you need the vault
password, which lives outside this repo at `~/secrets/.vault_pass_sales_demos`
(`chmod 600`, in a `chmod 700` directory) alongside the other `.vault_pass_*`
files. **Back that password up** — losing it makes the committed file
unrecoverable.

```bash
ansible-vault edit inventory/group_vars/aap/secrets.yml \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

**It holds credentials only.** Values that differ per environment are keyed
under `env_secrets` by environment name; each `connection.yml` selects its own
slice with `env_secrets[aap_env_name]`, which is also what stops one
environment from picking up another's credentials.

Everything that is *not* a credential — `aap_hostname`, `openshift_api_url`,
usernames, namespaces — lives in the committed plaintext
`inventory/group_vars/<env>/connection.yml`. So a new RHDP environment means
editing that environment's `connection.yml` plus two keys in the vault.

`secrets.yml.example` is the only `.example` file in the repo, and shows the
shape of the real one.

**The Automation Hub token is deliberately not in the vault.** `~/.ansible.cfg`
already holds it and is the authoritative copy — it is what
`ansible-galaxy collection install` uses for Red Hat certified content — so
`group_vars/aap/main.yml` reads it from there with an `ini` lookup instead of
keeping a second copy that would go stale on the next rotation. Same approach
as `aap.as.code` and `aap-skills`.

### Public repo

RHDP URLs are **not** treated as sensitive here. `*.dyn.redhatworkshops.io`
addresses are ephemeral demo-platform hostnames, not customer-identifying, and
keeping them readable in `connection.yml` is what lets the vaulted file hold
credentials only.

Everything else still applies: no customer names, passwords, tokens, or API keys
in any tracked file, commit message, issue, or PR. Before pushing:

```bash
git ls-files -z | xargs -0 grep -nEi \
  'sha256~|BEGIN [A-Z ]*PRIVATE KEY|AKIA[0-9A-Z]{16}'
```

That should return nothing but placeholder lines and the audit pattern itself.
`utilities/check-no-secrets.sh` runs the same check in CI, plus the one that
matters most under this model: **a tracked `secrets.yml` must start with
`$ANSIBLE_VAULT`**, so a plaintext one can never be committed.

## Skills and playbooks: one contract, two entry points

Every phase runs as a Claude Code skill *and* as an AAP job template. The skill
**never reimplements logic** — both entry points drive the same playbook through
the same variable contract.

| Layer | Responsibility |
|---|---|
| `playbooks/<phase>.yml` | All the work. Idempotent, no prompts, every input via `extra_vars`. |
| `.claude/skills/<name>/SKILL.md` | Preflight checks, collect inputs, explain, invoke the playbook. Zero business logic. |
| `demos/ocpvirt/controller_job_templates.yml` | Same playbook, survey questions mapped to the same `extra_vars`. |

**The contract is the variable names.** A survey question, a skill prompt, and a
playbook `extra_var` share a name or the design has drifted.

Skills here live in `.claude/skills/` and are discovered natively when this repo
is open — no marketplace, no `plugin.json`. They load only while you are working
in this repo, which for repo-specific skills is the correct scope.

### Skills

| Skill | Playbook | Does | Status |
|---|---|---|---|
| `ocpvirt-setup` | `playbooks/setup.yml` | Bootstrap AAP and install OpenShift Virtualization | CNV install done; AAP bootstrap open ([#1](https://github.com/ericcames/sales.demos/issues/1)) |
| `ocpvirt-provision` | `playbooks/provision_vm.yml` | Run Terraform, register the new VMs in AAP | Not started |
| `ocpvirt-windows-image` | `playbooks/build_windows_golden.yml` | Build and publish the Windows golden image | Not started |
| `ocpvirt-demo` | `playbooks/run_demo.yml` | Launch the layered daily demo | Not started |
| `ocpvirt-teardown` | `playbooks/teardown.yml` | Destroy VMs; keep CNV and the golden image | Not started |

See the [roadmap](ROADMAP.md) and the open issues. CI enforces that every skill
added here appears in this table.

A green CI run does not mean a playbook works — the lint gate cannot execute
anything. Run each phase against `sandbox` and verify against the cluster before
its PR merges; `ocpvirt-setup` ends in exactly that cluster-side check.

#### Repo maintenance skills

One skill has no playbook, deliberately — it touches your laptop, never a demo
environment, so it must never run from AAP:

| Skill | Does |
|---|---|
| `collections-sync` | Pin, install, and verify `collections/requirements.yml` |

## Collections

Every collection is pinned to an exact version in
[`collections/requirements.yml`](collections/requirements.yml). Nothing floats —
a floating version means two laptops resolve different code and a demo that
worked yesterday breaks on the next install.

Pins record versions that were **actually run**, not the newest published. Bump
a pin deliberately, re-run the affected phase against `sandbox`, then commit.

```bash
ansible-galaxy collection install -r collections/requirements.yml
```

They install to Ansible's default path, `~/.ansible/collections`. **Collections
are never vendored into this repo** — both `collections/ansible_collections/`
and `.ansible/` (ansible-lint's generated module mocks) are gitignored build
artifacts.

Run the `collections-sync` skill to pin, install, and verify in one pass. The
verify step is the point: `ansible-galaxy` reports success without installing
anything when it believes a collection is already present, and it silently
refuses to downgrade, so its exit code does not tell you what you actually have.

## Running a phase

**Nothing deploys from CI.** GitHub Actions is a pull-request gate only — lint,
secret hygiene, and skill portability. Everything that touches an environment
runs through `ansible-playbook`.

Locally, against the sandbox environment:

```bash
ansible-galaxy collection install -r collections/requirements.yml

ansible-playbook playbooks/setup.yml \
  -i inventory --limit sandbox -e target_env=sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

**`--vault-id` is required** — credentials come from the vault-encrypted
`group_vars/aap/secrets.yml`. Without it the run fails with
*"Attempting to decrypt but no vault secrets found"*.

**`--limit` selects the environment and is mandatory.** Playbooks target
`hosts: aap`, so without a limit they match every environment at once — they
assert on that and fail closed rather than configuring `sandbox` and `demo` in
the same run. Adding `-e target_env=<env>` makes the play verify the inventory
resolved to the environment you meant.

Each environment has its own host in `inventory/hosts.yml` (`sandbox-local`,
`demo-local`). That matters: when both groups shared one host, `--limit` filtered
hosts but not `group_vars`, so both environments' variables merged and
`--limit demo` silently used sandbox's hostname and token
([#16](https://github.com/ericcames/sales.demos/issues/16)). Never point two
environment groups at the same host.

Or open this repo in Claude Code and invoke the matching skill, which runs the
same playbook after collecting inputs and checking prerequisites.

From AAP, the same playbook runs as a job template with survey answers mapped to
the same `extra_vars`. All three paths are the same code.

That is deliberate: keeping deploys out of CI means no runner ever needs the
vault password, and there is no second copy of it living in GitHub Environment
secrets. See [#7](https://github.com/ericcames/sales.demos/issues/7).

## Conventions

See [`CLAUDE.md`](CLAUDE.md). The short version: AAP 2.6, `ansible.platform`
over `ansible.controller`, tokens always deleted in an `always:` block, no
project-local `ansible.cfg`, issues before code.

## License

[Apache 2.0](LICENSE)
