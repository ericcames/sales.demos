# sales.demos

Sales demo automation, built as code. Every demo runs two ways from the same
playbooks — as a Claude Code skill on your laptop, or as a job template inside
Ansible Automation Platform — so what you rehearse is literally what you
present. The environments are disposable and the configuration is not: when a
Red Hat Demo Platform cluster expires, you repoint three variables at a new one
and the demo comes back exactly as it was.

| | |
|---|---|
| **For** | Red Hat pre-sales engineers running customer demos |
| **Produces** | Four repeatable demos — OpenShift Virtualization, Private Automation Hub, MCP servers, and edge / single-node OpenShift |
| **Run it** | `/sales-demos-first-time` in Claude Code, or an AAP job template |
| **Status** | Four use cases live across three environments — `sandbox`, `demo`, `edge` |

**The words live elsewhere.** Talk tracks, run sheets, architecture guides,
design plans and operator reference are published as a site from
[sales.demos-docs](https://github.com/ericcames/sales.demos-docs):

**[ericcames.github.io/sales.demos-docs](https://ericcames.github.io/sales.demos-docs)**

## Getting started

**Presenting a demo?** You do not need this repo. Pick your demo on the site
above and read the **run sheet** — that is the page to hold while you present.
Nothing to clone, nothing to install.

**Running or changing the automation?**

```bash
git clone https://github.com/ericcames/sales.demos.git
git clone https://github.com/ericcames/sales.demos-docs.git          # the words
git clone https://github.com/ericcames/image.builder.pipeline.git    # the image factory
cd sales.demos
claude .
# then:  /sales-demos-first-time
```

[First-time setup](https://ericcames.github.io/sales.demos-docs/reference/first-time-setup/)
is the full walkthrough — every prerequisite, every verification command.
[`/sales-demos-first-time`](.claude/skills/sales-demos-first-time/SKILL.md)
is the same thing as a Claude Code skill that runs each step interactively.

[`CONTRIBUTING.md`](CONTRIBUTING.md) is next if you intend to open a pull
request — what must never be committed, where values live, the leak audit, and
the branch-and-PR workflow.

## Use cases

| Use case | Audience | Talk track and plan |
|---|---|---|
| **OpenShift Virtualization** | Linux / platform sysadmins | [docs site](https://ericcames.github.io/sales.demos-docs/demos/openshift-virtualization/) |
| **Private Automation Hub — ClickOps vs. config-as-code** | Sysadmins and automation leads | [docs site](https://ericcames.github.io/sales.demos-docs/demos/private-automation-hub/) |
| **MCP Servers — Agentic Automation** | Platform engineers and automation leads | [docs site](https://ericcames.github.io/sales.demos-docs/demos/mcp-servers/) |
| **Edge / Single Node OpenShift** | Infrastructure and edge architects | [docs site](https://ericcames.github.io/sales.demos-docs/demos/edge-sno/) |

## Skills

Every phase runs as a Claude Code skill **and** as an AAP job template, driving
the same `playbooks/<phase>.yml`. The skill never reimplements logic — the
variable names are the contract. Skills are discovered natively from
`.claude/skills/`; no marketplace, no `plugin.json`.

| Skill | Playbook | Does |
|---|---|---|
| `ocpvirt-setup` | `setup.yml` | Bare RHDP environment to demo-ready in one command |
| `ocpvirt-new-env` | `prepare_env.yml` | Verify a fresh environment is warm, and time a real VM build |
| `ocpvirt-provision` | `provision_vm.yml` | Run Terraform, register the new VMs in AAP |
| `ocpvirt-windows-image` | `link_windows_image.yml` | Point CNV at the published Windows golden image |
| `ocpvirt-rhel9-image` | `link_rhel9_image.yml` | Point CNV at the published RHEL 9 CIS L1 golden image |
| `ocpvirt-demo` | `repair_linux_vm.yml` | Repair an existing Linux VM: register, configure, rescan |
| `ocpvirt-teardown` | `teardown.yml` | Destroy VMs; keep CNV and the golden images |
| `sales-demos-probe-env` | `probe_env.yml` | Measure the cluster and recommend `available_memory_gb` |
| `pah-sync` | `sync_hub.yml`, `curate_hub.yml` | Populate Private Automation Hub; reconcile the `approved` repo |
| `pah-link-aap` | `link_hub.yml` | Point AAP project syncs at `approved`, reversibly |
| `sales-demos-portal` | `portal.yml` | Deploy the AAP self-service portal (RHDH + AAP plugin) |
| `sales-demos-orchestrator` | `install_ao.yml` | Install Automation Orchestrator and its CloudNativePG database |
| `sales-demos-orchestrator-config` | `configure_ao.yml` | Connect AO to AAP — OIDC SSO and AAP integration |
| `sales-demos-alloy` | `deploy_alloy.yml` | Deploy Grafana Alloy for metrics and logs to Grafana Cloud |
| `sales-demos-config` | `config.yml` | Apply AAP config-as-code — templates, credentials, gateway branding |
| `sales-demos-dashboard` | `deploy_dashboard.yml` | Push Grafana Cloud dashboards (dashboard-as-code) |

### Repo maintenance skills

No playbook, deliberately — they touch your laptop or a registry, never a demo
environment, so they must never run from AAP:

| Skill | Does |
|---|---|
| `sales-demos-first-time` | One-time setup on a new machine — start here |
| `sales-demos-collections-sync` | Pin, install, and verify `collections/requirements.yml` |
| `sales-demos-ee-build` | Build, verify, and publish the execution environment |
| `sales-demos-mcp` | Connect Claude Code to the clusters over MCP — six servers |
| `sales-demos-verify-ee` | Run a playbook *inside* the EE AAP uses, and diff it against a laptop run |
| `sales-demos-talk-track` | Scaffold or verify a use-case directory in the docs repo |
| `sales-demos-dev-workflow` | The end-to-end dev/test cycle — branch, PR, merge, `config.yml`, workflow |

CI enforces that every skill in `.claude/skills/` appears above.

**A green CI run does not mean a playbook works** — the lint gate executes
nothing. Run each phase against `sandbox`, and run it in the execution
environment too, before its PR merges.

## Layout

```
.claude/skills/<name>/SKILL.md   in-repo skills, discovered when the repo is open
assets/aap-branding/             AAP gateway config inputs — NOT documentation
collections/requirements.yml     what your laptop and the EE install
hub/                             what Private Automation Hub SYNCS (generated)
inventory/
  hosts.yml                        one host per environment — never share one
  env-urls.yml                     GITIGNORED, generated — product URLs per env
  group_vars/
    aap/                             shared config: job templates, workflows, credentials
    sandbox/  demo/  edge/           per-environment connection settings:
      connection.yml                   committed — hostnames, API URLs, namespaces
      local.yml.example                copy to local.yml and fill in your cluster
      local.yml                        GITIGNORED laptop-only overlay (#166)
playbooks/                       the work: one playbook per phase
  group_vars/all/
    secrets.yml                      GITIGNORED, vault-encrypted — the ONLY secrets file
    secrets.yml.example              the contract you build it from
terraform/ocpvirt/               keyed by PLATFORM, not demo — demos reuse platforms
utilities/                       build, check and generate scripts
```

**`hub/` is not `collections/`.** `collections/requirements.yml` is what your
laptop and the execution environment *install*. `hub/*-requirements.yml` is what
PAH *syncs from upstream*. Different direction, different lifecycle — mixing them
up is the likeliest mistake in the PAH use case.

**AAP objects are config-as-code in `inventory/group_vars/aap/`** —
`controller_templates.yml` and `controller_workflows.yml` hold the 32 job
templates and 4 workflows, applied by `playbooks/config.yml`.

**`assets/aap-branding/` is not documentation**, however much it looks like
screenshots. `gateway_settings.yml` reads `logo-<env>.png.b64` from there at
playbook run time. See [its README](assets/aap-branding/README.md).

**Two files are not where you would guess, and both placements are load-bearing.**

- **`secrets.yml` sits beside the *playbooks*, not the inventory.** AAP's SCM
  inventory sync runs `ansible-inventory`, which parses every `group_vars` file
  next to the inventory — a vaulted file there fails the sync with
  `ERROR! Attempting to decrypt but no vault secrets found`.
- **The overlay is `local.yml`, not `connection.local.yml`.** Ansible loads a
  `group_vars/<group>/` directory in sorted order and the *last* file wins.
  `connection.local.yml` sorts **before** `connection.yml` and loses silently —
  you would run against the committed cluster believing you had repointed.

`local.yml` is the laptop path only. A job template reads the SCM checkout, and a
gitignored file is not in it, so repointing AAP means committing to
`connection.yml` (#166). Both routes are written up in
[Reusing this repo](https://ericcames.github.io/sales.demos-docs/reference/reusing-this-repo/).

**There is no `docs/` directory.** Documentation lives in
[sales.demos-docs](https://github.com/ericcames/sales.demos-docs).

## Environments

- **`sandbox`** — the RHDP environment you build against and break.
- **`demo`** — the RHDP environment you show customers.
- **`edge`** — a persistent bare-metal single-node OpenShift cluster on a NUC.
  Not an RHDP provisioning: it does not expire, and DNS is local (dnsmasq). The
  same playbooks target it with `--limit edge`.

There is deliberately **no `golden` environment**. "This config is proven good"
is a state of the config, not a connection target — git already models that with
`main` plus a release tag.

All three are badged at the AAP sign-in page so you can tell them apart before
you touch anything — green for the one you break, red for the one customers
watch, purple for the one you own (#426). Details in
[Environments](https://ericcames.github.io/sales.demos-docs/reference/environments/).

## Running a phase

```bash
ansible-galaxy collection install -r collections/requirements.yml

ansible-playbook playbooks/setup.yml \
  -i inventory --limit sandbox -e target_env=sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

**`--limit` selects the environment and is mandatory** — playbooks target
`hosts: aap`, so without it they match every environment at once and fail closed.
**`--vault-id` is required**; credentials come from the vault-encrypted
`playbooks/group_vars/all/secrets.yml`.

Or open this repo in Claude Code and invoke the matching skill, which runs the
same playbook after collecting inputs and checking prerequisites. From AAP, the
same playbook runs as a job template with survey answers mapped to the same
`extra_vars`. All three paths are the same code.

**Nothing deploys from CI.** GitHub Actions is a pull-request gate only — lint,
secret hygiene, skill portability. That keeps the vault password off every
runner (#7).

## Where everything else lives

| You want | Go to |
|---|---|
| First-time setup — prerequisites and verification | [First-time setup](https://ericcames.github.io/sales.demos-docs/reference/first-time-setup/) |
| Talk tracks, run sheets, objections | [docs site](https://ericcames.github.io/sales.demos-docs) |
| Design plans — *why* it is built this way | [Design Plans](https://ericcames.github.io/sales.demos-docs/plan/ocpvirt-demo-plan/) |
| Running playbooks, verifying in the EE, run logs | [Running playbooks](https://ericcames.github.io/sales.demos-docs/reference/running-playbooks/) |
| The workflows and job templates AAP has | [Running from AAP](https://ericcames.github.io/sales.demos-docs/reference/running-from-aap/) |
| The execution environment | [Execution environment](https://ericcames.github.io/sales.demos-docs/reference/execution-environment/) |
| Pointing this at your own cluster, or forking | [Reusing this repo](https://ericcames.github.io/sales.demos-docs/reference/reusing-this-repo/) |
| What changed and when | `git log` and the [closed issues](https://github.com/ericcames/sales.demos/issues?q=is%3Aissue+is%3Aclosed) — the per-PR changelog was retired in [#432](https://github.com/ericcames/sales.demos/issues/432) and is [archived here](https://ericcames.github.io/sales.demos-docs/reference/history/) |
| Secrets, the leak audit, the PR workflow | [`CONTRIBUTING.md`](CONTRIBUTING.md) |
| The Terraform module — sizing, SSH, HTTP, Cockpit | [`terraform/ocpvirt/README.md`](terraform/ocpvirt/README.md) |
| The post-login environment badge | [`utilities/aap-env-badge/README.md`](utilities/aap-env-badge/README.md) |
| Conventions — AAP 2.7, `ansible.platform`, token cleanup | [`CLAUDE.md`](CLAUDE.md) |
| What is planned | [`ROADMAP.md`](ROADMAP.md) |

## Related repositories

| Repo | What it is | Which way the dependency runs |
|---|---|---|
| [sales.demos-docs](https://github.com/ericcames/sales.demos-docs) | Talk tracks, run sheets, plans, reference | **Documents** this repo |
| [image.builder.pipeline](https://github.com/ericcames/image.builder.pipeline) | The **image factory** — CIS-hardened RHEL AMIs and the Windows Server 2022 containerDisk | **Produces** what this repo consumes |
| [rego_policy_libraries](https://github.com/ynotbhatc/rego_policy_libraries) | OPA policy library | Consumes the factory's compliance data, not this repo |

**The golden images are deliberately split across two repos.** Building and
publishing them is the factory's job; pointing a cluster at a published image is
this repo's. **The only thing binding them is one string — a containerdisk tag**,
carried in `quay_windows_image` and `quay_rhel9_image` in
`inventory/group_vars/<env>/connection.yml`.

Both halves ship. The Windows image is built, published, and proven end to end —
a clone reaches the desktop and `win_ping` succeeds from AAP (#257).

### Working across the factory and this repo

Most work needs only one. Some spans both, and the edge / SNO demo does by
construction, since the installer ISO is built there and the cluster is
configured here. When it does, **start the agent in this repo**:

```bash
cd sales.demos && claude .
```

`.mcp.json` here is project-scoped, so the cluster servers load only in a session
started in *this* directory, and the factory repo has no MCP servers at all. From
here you can `cd ../image.builder.pipeline` and run its playbooks anyway — the
working directory does not restrict shell access. Better in one direction only.

**Its skills are the exception.** Skills are discovered from the directory the
agent starts in, so the factory's own skills are **not** reachable from a session
started here. Open a second session there to use them.

## License

[MIT](LICENSE)
