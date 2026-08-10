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

`playbooks/group_vars/aap/secrets.yml` is **vault-encrypted and committed**. It
sits in the `aap` group directory, so it loads for `sandbox` and `demo` alike —
one file, no per-environment copy to keep in step.

On a fresh clone you do not create it. You already have it; you need the vault
password, which lives outside this repo at `~/secrets/.vault_pass_sales_demos`
(`chmod 600`, in a `chmod 700` directory) alongside the other `.vault_pass_*`
files. **Back that password up** — losing it makes the committed file
unrecoverable.

```bash
ansible-vault edit playbooks/group_vars/aap/secrets.yml \
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
| `ocpvirt-new-env` | `playbooks/prepare_env.yml` | Verify a fresh environment is warm, and time a real VM build | Done ([#30](https://github.com/ericcames/sales.demos/issues/30)) |
| `ocpvirt-provision` | `playbooks/provision_vm.yml` | Run Terraform, register the new VMs in AAP | Done ([#4](https://github.com/ericcames/sales.demos/issues/4)) |
| `ocpvirt-windows-image` | `playbooks/build_windows_golden.yml` | Build and publish the Windows golden image | Not started |
| `ocpvirt-demo` | `playbooks/run_demo.yml` | Launch the layered daily demo | Not started |
| `ocpvirt-teardown` | `playbooks/teardown.yml` | Destroy VMs; keep CNV and the golden image | Done ([#6](https://github.com/ericcames/sales.demos/issues/6)) |

See the [roadmap](ROADMAP.md) and the open issues. CI enforces that every skill
added here appears in this table.

A green CI run does not mean a playbook works — the lint gate cannot execute
anything. Run each phase against `sandbox` and verify against the cluster before
its PR merges; `ocpvirt-setup` ends in exactly that cluster-side check.

#### Repo maintenance skills

These have no playbook, deliberately — they touch your laptop or a registry,
never a demo environment, so they must never run from AAP:

| Skill | Does |
|---|---|
| `sales-demos-first-time` | One-time setup on a new machine — start here |
| `collections-sync` | Pin, install, and verify `collections/requirements.yml` |
| `sales-demos-ee-build` | Build, verify, and publish the execution environment |

New machine? Run `/sales-demos-first-time` first. It walks every prerequisite and
validates each one, including the vault password — without which nothing in this
repo decrypts.

**This repo is self-contained.** Every skill it needs is in `.claude/skills/`
and discovered natively. Nothing here depends on a plugin or another repo's
skills, and nothing should be added that does.

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

## Running from AAP

Every phase runs two ways — from a skill on your laptop and from an AAP job
template — driving the same `playbooks/<phase>.yml`. The AAP objects are
config-as-code in `inventory/group_vars/aap/`, applied by `playbooks/config.yml`
like everything else.

| Job template | Runs | Against |
|---|---|---|
| `Sales Demos - Provision VM` | `playbooks/provision_vm.yml` | `Sales Demo VMs`, `limit: sandbox` |
| `Sales Demos - Check VMs` | `playbooks/check_vm.yml` | `Sales Demo VMs`, `limit: linuxweb` |

**One working inventory, not two.** `Sales Demo VMs` holds both populations:
`sandbox-local` / `demo-local`, synced from this repo's own `inventory/hosts.yml`
by an SCM inventory source, and the demo VMs registered at run time. That sync is
what lets a job template use `connection.yml` instead of a second copy of every
hostname. `Sales Demo VMs - Control` stays **empty** and is reserved for teardown
(#6), which cannot run in the inventory whose hosts it deletes.

**How AAP reaches the VMs: plain `ssh` on port 22.** AAP runs on the same
cluster, each VM has a headless Service giving it stable in-cluster DNS, and
there is no NetworkPolicy between the namespaces. No bastion is involved, and
`virtctl` is not either — that is the laptop path, and the execution environment
does not ship the binary. The only thing required is the `Sales Demos - Linux
Machine` credential, holding the private half of `demo_ssh_public_key`.

> **`demo_ssh_public_key` must not be empty.** cloud-init then emits
> `ssh_pwauth: true` with no authorized key *and* no password, and the guest has
> no credentials at all. Because cloud-init writes authorized keys only on first
> boot, a VM created that way must be **re-created**, not restarted.

To test a job template before its playbook has merged, override the project's
branch — a job template validates `playbook:` against the project's current
checkout, so an unmerged playbook cannot otherwise be wired up:

```bash
ansible-playbook playbooks/config.yml -i inventory --limit sandbox \
  -e target_env=sandbox -e sales_demos_branch=my-branch \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

Re-apply without the override before calling anything done.

## Execution environment

AAP runs this repo's playbooks on a custom image,
`quay.io/zigfreed/sales-demos-ee`, defined by
[`execution-environment.yml`](execution-environment.yml).

It exists for one reason: Phase 3 drives `terraform/ocpvirt/` by shelling out to
the terraform CLI, and no stock execution environment ships that binary.
Everything else in the image is `ee-supported-rhel9` (AAP 2.6, pinned by digest)
plus the same `collections/requirements.yml` your laptop installs — so the skill
path and the job-template path resolve identical collection code.

```bash
./utilities/build-ee.sh          # build + verify
./utilities/build-ee.sh --push   # build + verify + publish
```

Use the script, not `ansible-builder` directly. It stages `~/.ansible.cfg` —
which holds the Automation Hub token the build needs for certified collections —
into the gitignored `.ee-build/`, because the EE definition cannot portably
reference a path in `$HOME` and **a tracked `ansible.cfg` at the repo root would
shadow `~/.ansible.cfg` and break certified installs machine-wide**. The token
reaches the galaxy build stage only; the published image carries no credential.

The script then verifies the built image **as UID 1000**, which is who AAP runs
a job as: `terraform version` must execute, and every pinned collection must be
present at exactly its pinned version. `Complete!` from ansible-builder is not
verification — `==> Verified` is.

**AAP pulls it from Private Automation Hub, not from quay** (#35). quay stays
the published artifact and the source of truth; PAH mirrors it into a local
`sales_demos_ee` repository and Controller pulls that, which takes quay.io out
of the demo's runtime dependencies and makes the pull cluster-local. The mirror
is config-as-code in `hub_ee_registries.yml` and `hub_ee_repositories.yml`.

> **The sync has two gates and needs both.** The repository item must carry
> `sync: true`, *and* a variable named `hub_ee_repository_sync` must be
> **defined** — dispatch includes that role on `... is defined` and never reads
> the value. Miss either and there is no error: the repository is created, stays
> empty, and Controller later fails to pull an image that was never mirrored.

The image reference is `{{ aap_hostname }}/sales_demos_ee:v1.0.0` — templated
because PAH is fronted by the AAP gateway on the AAP hostname, which differs per
environment, and underscored because Hub repository names allow only
alphanumerics and underscores.

The image is registered in AAP by
[`inventory/group_vars/aap/controller_execution_environments.yml`](inventory/group_vars/aap/controller_execution_environments.yml),
applied by `playbooks/config.yml` like every other object. It is a **public**
quay repository on purpose, so the cluster pulls it with no image pull secret and
no AAP registry credential — one less thing to rebuild on each fresh RHDP
environment.

**Tags are immutable. Never re-push one.** Job templates pin a tag with
`pull: missing`, so re-pushing changes what a job runs with no corresponding
change in git — a failure that surfaces mid-demo. Publish a new tag and bump the
reference. The `sales-demos-ee-build` skill has the bump rules and the build
gotchas.

## Terraform: the `ocpvirt` module

`terraform/ocpvirt/` builds the VMs — Linux and Windows, sized by `sd1.*` cluster
instance types, each with a headless Service. Phase 3 will drive this same module
from AAP; until then it is run by hand.

State and `terraform.tfvars` are gitignored and must stay that way. Rather than
writing a token to disk, pass the variables as `TF_VAR_*` straight from the vault:

```bash
cd terraform/ocpvirt

export TF_VAR_openshift_api_token=$(
  ansible-vault view ../../playbooks/group_vars/aap/secrets.yml \
    --vault-id sales.demos@~/secrets/.vault_pass_sales_demos \
  | python3 -c 'import sys,yaml;print(yaml.safe_load(sys.stdin)["env_secrets"]["sandbox"]["openshift_api_token"])')

export TF_VAR_openshift_api_url=https://api.cluster-<id>.dyn.redhatworkshops.io:6443
export TF_VAR_openshift_insecure=true
export TF_VAR_namespace=sales-demos-sandbox
export TF_VAR_vm_size_tier=small-1cpu-2gb   # | medium-1cpu-4gb | large-2cpu-6gb
export TF_VAR_os_type=linux                 # | windows | both

terraform init && terraform apply
```

**`apply` finishing does not mean the guest is up.** The default StorageClass is
`WaitForFirstConsumer`, so the disk clones only once the VM first schedules —
apply returns in about 10s, and the VM reports `Ready` well after. Budget ~6
minutes on a cold cluster, where CDI imports the boot source for real; repeat
builds against a warm boot source have come up in ~30s. Watch the VM, not the
Ansible or Terraform recap:

```bash
oc get vm,vmi,pvc -n sales-demos-sandbox -w
```

Tiers are repo-owned `sd1.*` instance types, not Red Hat's `u1.*`, and `large` is
6 GiB rather than 8. Post-CNV this node has ~14 GiB free, so `u1.large` would make
`os_type=both` need ~16.6 GiB and never schedule. A precondition enforces that
budget, so an over-budget request fails in `plan` instead of leaving a VM `Pending`
while Terraform reports success. The `u1.*` types are left untouched.

Windows is wired but cannot boot until [#3](https://github.com/ericcames/sales.demos/issues/3) —
CNV ships `win2k22` as an empty DataSource placeholder.

### SSH access

NodePort was spiked on RHDP and is **filtered** — the RHDP firewall blocks high
ports, so a direct `ssh -p <nodePort>` from a laptop never connects. SSH access
uses `virtctl ssh`, which tunnels over the Kubernetes API (port 6443, confirmed
open).

Prerequisites: `virtctl` (download from the cluster's ConsoleCLIDownload) and
`oc` logged in. Then:

```bash
virtctl ssh -n sales-demos-sandbox -l cloud-user vm/sd-lnx-small-1cpu-2gb
```

The key is injected via cloud-init's `ssh_authorized_keys`. Set
`TF_VAR_demo_ssh_public_key` to your public key; when set, password-based SSH is
disabled on the guest. The `ssh_command` output gives the exact `virtctl` command
for the current VM.

```bash
export TF_VAR_demo_ssh_public_key="$(cat ~/.ssh/id_rsa.pub)"
```

### HTTP access

When `TF_VAR_openshift_apps_domain` is set, Terraform creates a `-web` ClusterIP
Service on port 80 and an OpenShift Route targeting it. The `web_url` output
gives the public URL.

```bash
export TF_VAR_openshift_apps_domain=apps.cluster-<id>.dyn.redhatworkshops.io
# find it with: oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}'
```

**The URL returns 503 until httpd is installed** by the AAP demo content
([#5](https://github.com/ericcames/sales.demos/issues/5)). That is expected, not
a bug.

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

### Keep the run log

Phase 0 takes 10–20 minutes. If it fails and the terminal is gone, so is the
evidence. Set a log path before running:

```bash
export ANSIBLE_LOG_PATH=~/ansible-logs/sales-demos-$(date +%F).log
```

Logs go to `~/ansible-logs/`, **outside the repo** — this repo is public, and
keeping them out entirely beats relying on an ignore rule.

**Do not pipe through `tee`.** In a pipeline the exit status comes from `tee`,
not from `ansible-playbook`, so a failed run reports success. That is not
hypothetical: it caused a real misread during Phase 0, where the harness showed
exit 0 for a playbook that had actually failed.

To apply the AAP configuration itself — organization, sign-in banner, the
environment-badged logo, analytics settings — use the config-as-code pair.
Always run `validate.yml` first; it is the same play in check mode:

```bash
ansible-playbook playbooks/validate.yml -i inventory --limit sandbox \
  -e target_env=sandbox --vault-id sales.demos@~/secrets/.vault_pass_sales_demos

ansible-playbook playbooks/config.yml -i inventory --limit sandbox \
  -e target_env=sandbox --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

`config.yml` reports `changed` on **every** run. AAP returns
`SUBSCRIPTIONS_CLIENT_SECRET` as `$encrypted$` and never in the clear, so the
role cannot compare desired against actual and rewrites it each time. That is
the platform refusing to hand back a secret, not drift — see the header of
`inventory/group_vars/aap/controller_settings.yml`.

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
