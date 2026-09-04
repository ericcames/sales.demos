# sales.demos

Sales demo automation, built as code. Each demo can be run two ways — as a
Claude Code skill from your laptop, or as a job template inside Ansible
Automation Platform — driving the same playbooks either way.

> **Status:** early. Two use cases: OpenShift Virtualization, and Private
> Automation Hub as code (#68). The layout admits more demos later; nothing from
> the other daily-demo repos has been migrated and that decision is
> deliberately open.

## Getting started

New machine, or a fresh clone? **Start here.** A clone passes CI and still
cannot run a playbook until you have supplied three things that deliberately do
not live in this repo: an Automation Hub token, a vault password, and a
`secrets.yml` you build yourself.

```bash
git clone https://github.com/ericcames/sales.demos.git
cd sales.demos
claude .
# then:  /sales-demos-first-time
```

[`.claude/skills/sales-demos-first-time/SKILL.md`](.claude/skills/sales-demos-first-time/SKILL.md)
is the real onboarding document — it walks every prerequisite and validates each
one. It is written to be *run* as a skill in Claude Code, but it reads perfectly
well as a checklist if you would rather work through it by hand.

| You need | Where it goes | Why it is not in the repo |
|---|---|---|
| Automation Hub token | `~/.ansible.cfg` | One authoritative copy; a second would go stale on rotation (#22) |
| Vault password | `~/secrets/.vault_pass_sales_demos` | The one secret that cannot itself be vaulted |
| `secrets.yml` | `playbooks/group_vars/all/` | Built from `secrets.yml.example`; shipping one person's encrypted credentials is what made this repo un-reusable (#130) |
| Your cluster's hostnames | `connection.yml` **or** a `local.yml` overlay | Two legitimate paths — see below; which one depends on whether you run from a laptop or from AAP (#131) |

### Pointing it at your own environment

`inventory/group_vars/sandbox/connection.yml` and `demo/connection.yml` are
committed with working RHDP values — those URLs are a documented non-secret
here, not an oversight. Three lines identify the cluster:

```yaml
aap_hostname:          "aap-aap.apps.cluster-<id>.dyn.redhatworkshops.io"
openshift_api_url:     "https://api.cluster-<id>.dyn.redhatworkshops.io:6443"
openshift_apps_domain: "apps.cluster-<id>.dyn.redhatworkshops.io"
```

**There are two legitimate ways to change them, and which one is right depends
on where you run from.**

| You are | Repoint by | Why |
|---|---|---|
| On a laptop, tracking this repo for updates | a gitignored `local.yml` overlay | You pull upstream fixes without ever conflicting |
| Forked, running from AAP | editing `connection.yml` on your own branch | Gitignored files are **not** in the SCM checkout a job template runs from |

#### From a laptop: the `local.yml` overlay

Create it beside the `connection.yml` you want to change, holding **only the
keys that differ** — not a copy of the file. Everything else keeps coming from
upstream:

```bash
cat > inventory/group_vars/sandbox/local.yml <<'YAML'
---
aap_hostname: "aap-aap.apps.cluster-<id>.dyn.redhatworkshops.io"
openshift_api_url: "https://api.cluster-<id>.dyn.redhatworkshops.io:6443"
openshift_apps_domain: "apps.cluster-<id>.dyn.redhatworkshops.io"
YAML
```

Ansible loads every file in a `group_vars/<group>/` directory in sorted order
and the **last one wins**, so this overrides `connection.yml` with no code
change at all.

**What it buys you is conflict avoidance, and that is worth quantifying.** Since
March, ten commits have touched these two files and eighteen of those edits were
to the three identity lines above — roughly monthly, as RHDP environments are
rebuilt and repointed. Edit `connection.yml` directly and you conflict on every
one of those pulls. Keep your values in `local.yml` and you never do.

**The name must be `local.yml`.** `connection.local.yml` sorts *before*
`connection.yml` and therefore loses: it would be loaded, silently overridden,
and leave you running against the committed cluster while believing you had
repointed it.

Confirm what is actually in effect rather than trusting the file you edited:

```bash
ansible -i inventory --limit sandbox aap -m debug -a 'msg={{ aap_hostname }}'
```

#### From AAP: edit `connection.yml`

An AAP job template gets its playbooks and inventory from the SCM project
checkout, and a gitignored file is not in it. So `local.yml` does nothing for a
job template, and repointing one means committing the change:

```bash
git checkout -b my-environment
$EDITOR inventory/group_vars/sandbox/connection.yml
```

Point your AAP project's `scm_url` at your own fork —
`inventory/group_vars/aap/controller_projects.yml` currently hardcodes this
repo, which is [#132](https://github.com/ericcames/sales.demos/issues/132).

You can do both: the overlay for laptop runs, the committed file for AAP. They
do not interfere — `local.yml` simply is not present in the checkout.

### Forking

Running from AAP means forking, and four things in this repo name *this* repo or
its author. Two are now variables; two are deliberately left alone (#132).

**Point AAP's project at your fork.** This is the one that bites, because
nothing looks wrong when it is missed — AAP happily syncs upstream, and your
changes simply never take effect:

```bash
ansible-playbook playbooks/config.yml -i inventory --limit sandbox \
  -e sales_demos_scm_url=https://github.com/<you>/sales.demos.git
```

**Mirror your own execution environment,** if you build one. Pulls from the
default namespace are public and work for anyone, so this matters only once you
push your own image:

```bash
EE_IMAGE=quay.io/<you>/sales-demos-ee:v1.1.0 ./utilities/build-ee.sh
ansible-playbook playbooks/config.yml -i inventory --limit sandbox \
  -e sales_demos_ee_upstream=<you>/sales-demos-ee
```

Both default to this repo's own values, so nothing changes if you ignore them.

| Baked-in identity | Status |
|---|---|
| AAP project `scm_url` | **Variable** — `sales_demos_scm_url` |
| PAH EE `upstream_name` | **Variable** — `sales_demos_ee_upstream` |
| `EE_IMAGE` in `utilities/build-ee.sh` | Already env-overridable |
| `linux_configure_repo_url` (demo page footer) | Already a role default — override it in `group_vars`, and CI now fails if `render-demo-assets.py` is not updated to match |
| `.github/CODEOWNERS` | **Left alone.** Correct for this repo; a fork's own to rewrite |

If your vault password lives somewhere other than the default path, export
`SALES_DEMOS_VAULT_PASS`; both `utilities/make-kubeconfig.sh` and the AAP Vault
credential in `inventory/group_vars/aap/main.yml` read that same variable.

## Use cases

| Use case | Audience | Plan | Talk track |
|---|---|---|---|
| **OpenShift Virtualization** | Linux / platform sysadmins | [`docs/plan/ocpvirt-demo-plan.md`](docs/plan/ocpvirt-demo-plan.md) | [`docs/demos/openshift-virtualization/`](docs/demos/openshift-virtualization/) |
| **Private Automation Hub — ClickOps vs. config-as-code** | Sysadmins and automation leads | [`docs/plan/pah-plan.md`](docs/plan/pah-plan.md) | [`docs/demos/private-automation-hub/`](docs/demos/private-automation-hub/) |
| **MCP Servers — Agentic Automation** | Platform engineers and automation leads | [`docs/plan/platform-addons-plan.md`](docs/plan/platform-addons-plan.md) | [`docs/demos/mcp-servers/`](docs/demos/mcp-servers/) |

## The demo: OpenShift Virtualization on the RHDP "Ansible Product Demo"

Terraform provisions Windows and Linux VMs onto OpenShift Virtualization with
small / medium / large t-shirt sizing, AAP registers them as managed hosts, and
the existing daily-demo content layers on top unchanged.

The full research findings, design decisions, and phase-by-phase plan are in
[`docs/plan/ocpvirt-demo-plan.md`](docs/plan/ocpvirt-demo-plan.md). Read that
first — it records *why* things are the way they are, not just what to do.

**Presenting it rather than building it?**
[`docs/demos/openshift-virtualization/`](docs/demos/openshift-virtualization/)
is the talk track: a 30-minute run sheet, the narrative behind each beat, the
questions this audience asks, and the answers. It needs no live environment —
the demo page and login banners are rendered from the same templates the guests
serve by `utilities/render-demo-assets.py`, and committed.

## Layout

Two independent axes, kept separate so adding demos later does not multiply out:

```
.claude/skills/<name>/SKILL.md   in-repo skills, discovered when the repo is open
demos/ocpvirt/                   demo content — job templates, surveys
hub/                             what Private Automation Hub SYNCS (generated)
inventory/group_vars/
  aap/                             shared, demo-agnostic config
  sandbox/  demo/                  per-environment connection + secrets
terraform/ocpvirt/               keyed by PLATFORM, not demo — demos reuse platforms
playbooks/                       the work: one playbook per phase
```

**`hub/` is not `collections/`.** `collections/requirements.yml` is what your
laptop and the execution environment *install*. `hub/*-requirements.yml` is what
PAH *syncs from upstream*. Different direction, different lifecycle — mixing
them up is the likeliest mistake in the second use case.

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

### Telling them apart after login

The sign-in badge is gone the moment you are logged in, which is when you are
actually clicking things. No gateway setting fixes that (#54 re-measured it with
`custom_logo` applied — the masthead still rendered stock), so the post-login
half is a browser extension:

```bash
# chrome://extensions -> Developer mode -> Load unpacked
utilities/aap-env-badge/
```

It paints a `SANDBOX` / `DEMO` pill in the middle of the masthead in the same
colours and matches both environments in one load. It changes nothing on the
cluster. See
[`utilities/aap-env-badge/README.md`](utilities/aap-env-badge/README.md).

**It asks AAP which environment it is** rather than recognising the hostname,
so there is nothing to regenerate when RHDP hands you a new cluster: a new
environment really is just the `connection.yml` edit plus the vault. It reads
`target_env`, which this repo already sets on its job templates. A cluster that
answers but declares no environment gets a neutral `UNRECOGNIZED ENV` pill —
deliberately, since that is when you are most likely to act on the wrong one.

This replaced a generated hostname map that went stale on every rotation and
failed silently (#87).

## Secrets: one vaulted file, both environments

`playbooks/group_vars/all/secrets.yml` is **vault-encrypted and local only — it
is not tracked**. It sits in the `all` group directory, so it loads for
`sandbox`, `demo` and the demo VMs alike — one file, no per-environment copy to
keep in step.

**On a fresh clone it does not exist, and you create it.** That is deliberate:
this repo is public, and shipping one person's encrypted credentials would hand
everyone else a blob they cannot decrypt and cannot replace without diverging
from upstream (#130). `secrets.yml.example` is the contract — copy it, fill in
your own values, encrypt it:

```bash
cp playbooks/group_vars/all/secrets.yml.example \
   playbooks/group_vars/all/secrets.yml
# fill in real values, then:
ansible-vault encrypt playbooks/group_vars/all/secrets.yml \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

The vault password is yours to choose and lives outside this repo at
`~/secrets/.vault_pass_sales_demos` (`chmod 600`, in a `chmod 700` directory)
alongside the other `.vault_pass_*` files. **Back up both the password and the
file** — nothing in git can restore either one now.

The `sales.demos` vault-id label is not cosmetic: it must match the label baked
into the file's header, and `inventory/group_vars/aap/controller_credentials.yml`
depends on it.

```bash
ansible-vault edit playbooks/group_vars/all/secrets.yml \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

**It holds credentials only.** Values that differ per environment are keyed
under `env_secrets` by environment name; each `connection.yml` selects its own
slice with `env_secrets[aap_env_name]`, which is also what stops one
environment from picking up another's credentials.

Everything that is *not* a credential — `aap_hostname`, `openshift_api_url`,
usernames, namespaces — lives in the committed plaintext
`inventory/group_vars/<env>/connection.yml`. So a new RHDP environment means
editing that environment's `connection.yml` plus two keys in the vault — or, if
you are a reuser running from a laptop, a `local.yml` overlay plus those same
two keys. See [Pointing it at your own environment](#pointing-it-at-your-own-environment).

`secrets.yml.example` is the only `.example` file in the repo, and shows the
shape of the real one. **It is a contract, not a courtesy**, and CI enforces
it: `utilities/check-secrets-example.py` finds every variable the code reads
bare and nothing defines — those can only come from the vault — and fails if
one is not declared here. It also fails on a key nothing reads, and on a
credential added to one environment's `env_secrets` but not the other.

That check exists because the example had already drifted: `rhsm_org_id` and
`rhsm_activation_key` are asserted by `playbooks/roles/linux_register` and
were missing from it, so a secrets file built from the example passed every
preflight and then failed Phase 4 on guest registration (#128).

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

**One documented exception: `pah-sync`.** The Red Hat offline token that syncs
certified content lives in `~/.ansible.cfg`, and an AAP execution environment has
no such file. A vaulted fallback was built and verified working, then removed —
it bought one job template at the cost of a second copy of a rotating credential.
So PAH work runs from a laptop, which is where `config.yml` has always been: you
cannot use AAP to bootstrap itself. See [`docs/plan/pah-plan.md`](docs/plan/pah-plan.md).

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
| `ocpvirt-setup` | `playbooks/setup.yml` | Bare RHDP environment to demo-ready in one command | Done ([#1](https://github.com/ericcames/sales.demos/issues/1)) |
| `ocpvirt-new-env` | `playbooks/prepare_env.yml` | Verify a fresh environment is warm, and time a real VM build | Done ([#30](https://github.com/ericcames/sales.demos/issues/30)) |
| `ocpvirt-provision` | `playbooks/provision_vm.yml` | Run Terraform, register the new VMs in AAP | Done ([#4](https://github.com/ericcames/sales.demos/issues/4)) |
| `ocpvirt-windows-image` | `playbooks/build_windows_golden.yml` | Build and publish the Windows golden image | Not started |
| `ocpvirt-demo` | `playbooks/run_demo.yml` | Register the VMs and configure the web server | Done ([#5](https://github.com/ericcames/sales.demos/issues/5)) |
| `ocpvirt-teardown` | `playbooks/teardown.yml` | Destroy VMs; keep CNV and the golden image | Done ([#6](https://github.com/ericcames/sales.demos/issues/6)) |
| `sales-demos-probe-env` | `playbooks/probe_env.yml` | Measure what the cluster actually has and recommend `available_memory_gb` | Done ([#100](https://github.com/ericcames/sales.demos/issues/100)) |
| `pah-sync` | `playbooks/sync_hub.yml`, `playbooks/curate_hub.yml` | Populate Private Automation Hub, and reconcile the curated `approved` repository | Done ([#68](https://github.com/ericcames/sales.demos/issues/68), [#70](https://github.com/ericcames/sales.demos/issues/70)) |
| `pah-link-aap` | `playbooks/link_hub.yml` | Point AAP project syncs at the curated `approved` repository, reversibly | Done ([#69](https://github.com/ericcames/sales.demos/issues/69)) |
| `sales-demos-portal` | `playbooks/portal.yml` | Deploy the AAP self-service portal (RHDH + AAP plugin) via Helm | Done ([#103](https://github.com/ericcames/sales.demos/issues/103)) |
| `sales-demos-orchestrator` | `playbooks/install_ao.yml` | Install Automation Orchestrator and its CloudNativePG database | Done ([#141](https://github.com/ericcames/sales.demos/issues/141)) |

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
| `sales-demos-mcp` | Connect Claude Code to the clusters over MCP — per-environment kubeconfigs |
| `sales-demos-verify-ee` | Run a playbook *inside* the EE AAP uses, and diff it against a laptop run |
| `sales-demos-talk-track` | Scaffold or verify a use-case directory under `docs/demos/` — structure, rendered artifacts, source table |

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
Everything else in the image is `ee-supported-rhel9` (AAP 2.7, pinned by digest)
plus the same `collections/requirements.yml` your laptop installs — so the skill
path and the job-template path resolve identical collection *code*.

**Identical collections is not an identical environment**, and the difference is
underneath them. Measured 2026-09-04: the laptop ran ansible-core `2.18.18rc1` on
python 3.14 while `sales-demos-ee:v1.1.0` runs core `2.16.19` on python 3.12 —
two minor versions of core apart, with every collection pin matching exactly.
That gap is invisible to CI, to a laptop run, and to `build-ee.sh`'s drift check,
and it is currently holding a real defect (#173). See
[*Verify it in the EE*](#verify-it-in-the-ee) below.

### The published image carries no credential

The image is public. It holds **no token**, and that is checkable rather than
asserted:

```bash
podman run --rm --entrypoint /bin/bash quay.io/zigfreed/sales-demos-ee:v1.1.0 \
  -c 'ls /etc/ansible 2>&1; ansible --version | grep "config file"'
# ls: cannot access '/etc/ansible': No such file or directory
#   config file = None

podman history --no-trunc quay.io/zigfreed/sales-demos-ee:v1.1.0 | grep ansible.cfg
# (no match)
```

`execution-environment.yml` stages `~/.ansible.cfg` — which carries the Red Hat
offline token — into the **galaxy build stage only**. The final image is built
`FROM base` and copies the installed collections out, not that file.

Anything that needs a credential at run time gets it **mounted read-only from
your laptop for that run and never persisted**, which is why
`utilities/run-in-ee.sh` prints every mount before it starts. Making the build
*enforce* the emptiness rather than merely achieve it is [#172](https://github.com/ericcames/sales.demos/issues/172).

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
  ansible-vault view ../../playbooks/group_vars/all/secrets.yml \
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
apply returns in about 10s, and the VM reports `Ready` well after.

**Budget ~45 seconds for the build, and roughly 20 minutes from a bare RHDP
environment** — the latter being mostly the environment provisioning itself,
plus ~4 minutes to install CNV. A fresh cluster is usually already warm: the
boot-source import runs alongside the CNV install, so by the time Phase 0
returns, all six VolumeSnapshots are typically `readyToUse`.

An older ~6 minute "cold cluster" figure appears in earlier notes. It is a real
measurement, but it did **not** reproduce on a genuinely fresh environment,
which built in 44s — the same as a warm one. It most likely came from building
immediately after the install, catching the import mid-flight. Rather than trust
either number, run `ocpvirt-new-env`, which proves it in about a minute.

Watch the VM, not the Ansible or Terraform recap:

```bash
oc get vm,vmi,pvc -n sales-demos-sandbox -w
```

Tiers are repo-owned `sd1.*` instance types, not Red Hat's `u1.*`, and `large` is
6 GiB rather than 8. That sizing came from a smaller cluster with ~14 GiB free;
`sales-demos-probe-env` measured 75.63 GiB free on sandbox 2026-09-03 and
`available_memory_gb` is now 67 to match (#118). The tier sizes were not
revisited — that constraint is gone, but a number should move because something
was measured, not because it now could. A precondition enforces that
budget, so an over-budget request fails in `plan` instead of leaving a VM `Pending`
while Terraform reports success. The `u1.*` types are left untouched.

Windows is wired but cannot boot until [#3](https://github.com/ericcames/sales.demos/issues/3) —
CNV ships `win2k22` as an empty DataSource placeholder.

### SSH access

NodePort was spiked on RHDP and is **filtered** — the RHDP firewall blocks high
ports, so a direct `ssh -p <nodePort>` from a laptop never connects. SSH access
uses `virtctl ssh`, which tunnels over the Kubernetes API (port 6443, confirmed
open).

Prerequisites: `virtctl` (download from the cluster's ConsoleCLIDownload), and
this repo's kubeconfig for the environment — **not** `oc login` (#161):

```bash
KUBECONFIG=.kube/sandbox.kubeconfig \
  virtctl ssh -n sales-demos-sandbox cloud-user@vm/sd-lnx-small-1cpu-2gb
```

**Name the kubeconfig; do not rely on whatever `~/.kube/config` points at.**
`virtctl` defaults to that file, it is shared with other demo repos, and an
environment that has been rebuilt leaves it pointing at a cluster whose DNS no
longer resolves — the failure reads `dial tcp: lookup api.cluster-... no such
host` and says nothing about kubeconfigs. Generate the per-environment file with
`utilities/make-kubeconfig.sh <env>`, and check it still matches with
`utilities/check-kubeconfig.sh <env>`.

No `-i` is needed: the VM's authorized key is `demo_ssh_public_key`, whose
private half is an ordinary default identity in `~/.ssh`, which ssh offers
automatically.

> **No `--local-ssh`.** Older notes and anything copied from a pre-#49
> `ssh_command` output carry that flag. virtctl v1.x removed its built-in SSH
> client, so local ssh became the only mode and the flag was deleted rather than
> defaulted — it now fails with `unknown flag: --local-ssh` before connecting.
> Pass ssh options with `-t/--local-ssh-opts` instead. Keep the `vm/` prefix:
> virtctl takes a `(VM|VMI)` resource, not a bare name.

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
`playbooks/group_vars/all/secrets.yml`. Without it the run fails with
*"Attempting to decrypt but no vault secrets found"*.

### Verify it in the EE

That command runs on **your laptop**, against `~/.ansible/collections` and your
system python. An AAP job template runs the same playbook inside
`sales-demos-ee`, against whatever that image baked in. Two dependency sets, and
only one of them is what production uses.

Nothing else here can tell them apart — CI executes nothing, so a local run is
this repo's only pre-merge verification and by default it verifies the wrong one.
Before a playbook change merges, run it in the image as well:

```bash
utilities/run-in-ee.sh playbooks/probe_env.yml \
  -i inventory --limit sandbox -e target_env=sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

**Everything after the playbook is byte-identical to the `ansible-playbook`
command above it.** The wrapper adds `ansible-navigator`, the right image, and
two read-only mounts; it changes none of your arguments. `~/` paths resolve
inside the container because the mounts are placed where the container's home is.

Add `--with-hub-token` for `config.yml`, `validate.yml`, `setup.yml`,
`sync_hub.yml` and `curate_hub.yml`, which read the Red Hat offline token from
`~/.ansible.cfg`. The wrapper refuses rather than warns if you forget — without
the mount the `ini` lookup **raises** (`Invalid filename: 'None'`) rather than
returning an empty string.

This is a verification path, not a replacement: `ansible-playbook` stays the
everyday command. `/sales-demos-verify-ee` walks the whole thing, including which
playbooks need what and how to diff the two runs.

It has already earned it. [#122](https://github.com/ericcames/sales.demos/issues/122)
(a hijacked python interpreter) and [#173](https://github.com/ericcames/sales.demos/issues/173)
(`validate.yml` failing on the EE's older ansible-core) were both invisible to CI,
to a laptop run, and to `build-ee.sh`.

Every run now prints both ansible-core versions, because #173 turned out not to
be a collection problem at all — every pin matched exactly while the laptop ran
core `2.18.18rc1` and the EE ran `2.16.19`. **Pinned collections are not a
pinned environment**, and the difference is a note rather than an error: running
the EE's dependency set instead of the laptop's is the point of the wrapper.

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
Always run `validate.yml` first; it is the same play in check mode. **It needs
`--check`, and refuses to run without it** — a play-level `check_mode: true`
sets the task's check mode but leaves the `ansible_check_mode` variable False,
and `infra.aap_configuration`'s entire check-mode handling keys off that
variable ([#173](https://github.com/ericcames/sales.demos/issues/173)):

```bash
ansible-playbook playbooks/validate.yml --check -i inventory --limit sandbox \
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

See [`CLAUDE.md`](CLAUDE.md). The short version: AAP 2.7, `ansible.platform`
over `ansible.controller`, tokens always deleted in an `always:` block, no
project-local `ansible.cfg`, issues before code.

## License

[MIT](LICENSE)
