# sales.demos

Sales demo automation, built as code. Every demo runs two ways from the same
playbooks — as a Claude Code skill on your laptop, or as a job template inside
Ansible Automation Platform — so what you rehearse is literally what you
present. The environments are disposable and the configuration is not: when a
Red Hat Demo Platform cluster expires, you repoint three variables at a new one
and the demo comes back exactly as it was.

> [!TIP]
> **New here?** Jump to [🚀 Getting started](#-getting-started). Everything
> else — talk tracks, run sheets, reference — is on the
> **[docs site](https://ericcames.github.io/sales.demos-docs/)**.

| | |
|---|---|
| **For** | Red Hat pre-sales engineers running customer demos |
| **Produces** | Five repeatable demos across three environments — `sandbox`, `demo`, `edge` |

## 🚀 Getting started

🎤 **Presenting a demo?** You do not need this repo. Pick your demo on the
[docs site](https://ericcames.github.io/sales.demos-docs/demos/) and hold its
**run sheet** while you present. Nothing to clone, nothing to install.

🛠️ **Running or changing the automation?**

```bash
git clone https://github.com/ericcames/sales.demos.git
git clone https://github.com/ericcames/sales.demos-docs.git          # the words
git clone https://github.com/ericcames/image.builder.pipeline.git    # optional: the image factory — edge or golden-image work only
cd sales.demos
claude .
# then:  /sales-demos-first-time
```

1. **Set up your laptop** —
   [`/sales-demos-first-time`](.claude/skills/sales-demos-first-time/SKILL.md),
   or read [First-time setup](https://ericcames.github.io/sales.demos-docs/reference/first-time-setup/).
2. **Point it at your RHDP cluster** — three inputs from the RHDP page (AAP
   URL, AAP admin password, kubeadmin password) and one copy-paste prompt for
   [`/sales-demos-bootstrap`](.claude/skills/sales-demos-bootstrap/SKILL.md):
   see the [New environment quick start](https://ericcames.github.io/sales.demos-docs/reference/new-environment/#quick-start).
   Your cluster lives in a gitignored `local.yml`, so you never conflict on a
   pull — see [Reusing this repo](https://ericcames.github.io/sales.demos-docs/reference/reusing-this-repo/).
3. **Opening a pull request?** Read [`CONTRIBUTING.md`](CONTRIBUTING.md) first.

## 🎬 Use cases

| Use case | Audience | Run sheet |
|---|---|---|
| [OpenShift Virtualization](https://ericcames.github.io/sales.demos-docs/demos/openshift-virtualization/) | Linux / platform sysadmins | [🎤 Run sheet](https://ericcames.github.io/sales.demos-docs/demos/openshift-virtualization/run-sheet/) |
| [Private Automation Hub — ClickOps vs. config-as-code](https://ericcames.github.io/sales.demos-docs/demos/private-automation-hub/) | Sysadmins and automation leads | [🎤 Run sheet](https://ericcames.github.io/sales.demos-docs/demos/private-automation-hub/run-sheet/) |
| [MCP Servers — Agentic Automation](https://ericcames.github.io/sales.demos-docs/demos/mcp-servers/) | Platform engineers and automation leads | [🎤 Run sheet](https://ericcames.github.io/sales.demos-docs/demos/mcp-servers/run-sheet/) |
| [Automation Orchestrator](https://ericcames.github.io/sales.demos-docs/demos/automation-orchestrator/) | Automation architects | [🎤 Run sheet](https://ericcames.github.io/sales.demos-docs/demos/automation-orchestrator/run-sheet/) |
| [Edge / Single Node OpenShift](https://ericcames.github.io/sales.demos-docs/demos/edge-sno/) | Infrastructure and edge architects | [🎤 Run sheet](https://ericcames.github.io/sales.demos-docs/demos/edge-sno/run-sheet/) |

## 🧰 Skills

Every phase runs as a Claude Code skill **and** as an AAP job template, driving
the same `playbooks/<phase>.yml` — the variable names are the contract.
**A green CI run does not mean a playbook works**: the lint gate executes
nothing, and nothing deploys from CI.

<details>
<summary><b>All skills</b> — click to expand</summary>

🏗️ **Environment** — take a cluster to demo-ready and keep AAP in step

| Skill | Playbook | Does |
|---|---|---|
| [`/sales-demos-setup`](.claude/skills/sales-demos-setup/SKILL.md) | `setup.yml` | Bare RHDP environment to demo-ready in one command |
| [`/sales-demos-verify-env`](.claude/skills/sales-demos-verify-env/SKILL.md) | `prepare_env.yml` | Verify a fresh environment is warm, and time a real VM build |
| [`/sales-demos-probe-env`](.claude/skills/sales-demos-probe-env/SKILL.md) | `probe_env.yml` | Measure the cluster and recommend `available_memory_gb` |
| [`/sales-demos-config`](.claude/skills/sales-demos-config/SKILL.md) | `config.yml` | Apply AAP config-as-code — templates, credentials, gateway branding |
| [`/sales-demos-env-urls`](.claude/skills/sales-demos-env-urls/SKILL.md) | `generate_env_urls.yml` | Regenerate the environment URL reference file |

🖥️ **VMs & golden images** — build, repair and destroy the demo guests

| Skill | Playbook | Does |
|---|---|---|
| [`/sales-demos-provision`](.claude/skills/sales-demos-provision/SKILL.md) | `provision_vm.yml` | Run Terraform, register the new VMs in AAP |
| [`/sales-demos-windows-image`](.claude/skills/sales-demos-windows-image/SKILL.md) | `link_windows_image.yml` | Point CNV at the published Windows golden image |
| [`/sales-demos-rhel9-image`](.claude/skills/sales-demos-rhel9-image/SKILL.md) | `link_rhel9_image.yml` | Point CNV at the published RHEL 9 CIS L1 golden image |
| [`/sales-demos-ocpvirt-demo`](.claude/skills/sales-demos-ocpvirt-demo/SKILL.md) | `repair_linux_vm.yml` | Repair an existing Linux VM: register, configure, rescan |
| [`/sales-demos-teardown`](.claude/skills/sales-demos-teardown/SKILL.md) | `teardown.yml` | Destroy VMs; keep CNV and the golden images |

📦 **Private Automation Hub**

| Skill | Playbook | Does |
|---|---|---|
| [`/pah-sync`](.claude/skills/pah-sync/SKILL.md) | `sync_hub.yml`, `curate_hub.yml` | Populate Private Automation Hub; reconcile the `approved` repo |
| [`/pah-link-aap`](.claude/skills/pah-link-aap/SKILL.md) | `link_hub.yml` | Point AAP project syncs at `approved`, reversibly |

🧩 **Platform add-ons** — portal, orchestrator, observability

| Skill | Playbook | Does |
|---|---|---|
| [`/sales-demos-portal`](.claude/skills/sales-demos-portal/SKILL.md) | `portal.yml` | Deploy the AAP self-service portal (RHDH + AAP plugin) |
| [`/sales-demos-orchestrator`](.claude/skills/sales-demos-orchestrator/SKILL.md) | `install_ao.yml` | Install Automation Orchestrator and its CloudNativePG database |
| [`/sales-demos-orchestrator-config`](.claude/skills/sales-demos-orchestrator-config/SKILL.md) | `configure_ao.yml` | Connect AO to AAP — OIDC SSO and AAP integration |
| [`/sales-demos-orchestrator-workflow`](.claude/skills/sales-demos-orchestrator-workflow/SKILL.md) | `ao_workflows.yml` | Load the AO demo workflows from config-as-code, resolving names to this environment's IDs |
| [`/sales-demos-alloy`](.claude/skills/sales-demos-alloy/SKILL.md) | `deploy_alloy.yml` | Deploy Grafana Alloy for metrics and logs to Grafana Cloud |
| [`/sales-demos-dashboard`](.claude/skills/sales-demos-dashboard/SKILL.md) | `deploy_dashboard.yml` | Push Grafana Cloud dashboards (dashboard-as-code) |

🔧 **Repo maintenance** skills have no playbook, deliberately — they touch your
laptop or a registry, never a demo environment, so they must never run from AAP:

| Skill | Does |
|---|---|
| [`/sales-demos-first-time`](.claude/skills/sales-demos-first-time/SKILL.md) | One-time setup on a new machine — start here |
| [`/sales-demos-bootstrap`](.claude/skills/sales-demos-bootstrap/SKILL.md) | Full environment bootstrap from a single AAP URL — setup, MCP, probe, verify |
| [`/sales-demos-collections-sync`](.claude/skills/sales-demos-collections-sync/SKILL.md) | Pin, install, and verify `collections/requirements.yml` |
| [`/sales-demos-ee-build`](.claude/skills/sales-demos-ee-build/SKILL.md) | Build, verify, and publish the execution environment |
| [`/sales-demos-mcp`](.claude/skills/sales-demos-mcp/SKILL.md) | Connect Claude Code over MCP — up to ten servers across clusters, AAP, portal, AO, Grafana |
| [`/sales-demos-verify-ee`](.claude/skills/sales-demos-verify-ee/SKILL.md) | Run a playbook *inside* the EE AAP uses, and diff it against a laptop run |
| [`/sales-demos-talk-track`](.claude/skills/sales-demos-talk-track/SKILL.md) | Scaffold or verify a use-case directory in the docs repo |
| [`/sales-demos-dev-workflow`](.claude/skills/sales-demos-dev-workflow/SKILL.md) | The end-to-end dev/test cycle — branch, PR, merge, `config.yml`, workflow |

CI enforces that every skill in `.claude/skills/` appears above.

</details>

## 📚 Where everything else lives

| You want | Go to |
|---|---|
| Talk tracks, run sheets, objections | [Demos](https://ericcames.github.io/sales.demos-docs/demos/) |
| Which cluster is which — `sandbox`, `demo`, `edge` | [Environments](https://ericcames.github.io/sales.demos-docs/reference/environments/) |
| Running a phase from a laptop, verifying in the EE | [Running playbooks](https://ericcames.github.io/sales.demos-docs/reference/running-playbooks/) |
| The workflows and job templates AAP has | [Running from AAP](https://ericcames.github.io/sales.demos-docs/reference/running-from-aap/) |
| Where a file lives, and why `secrets.yml` is not where you would guess | [Repo layout](https://ericcames.github.io/sales.demos-docs/reference/repo-layout/) |
| The execution environment | [Execution environment](https://ericcames.github.io/sales.demos-docs/reference/execution-environment/) |
| Design plans — *why* it is built this way | [Design Plans](https://ericcames.github.io/sales.demos-docs/plan/ocpvirt-demo-plan/) |
| The Terraform module — sizing, SSH, HTTP, Cockpit | [`terraform/ocpvirt/README.md`](terraform/ocpvirt/README.md) |
| Conventions — AAP 2.7, `ansible.platform`, token cleanup | [`CLAUDE.md`](CLAUDE.md) |
| What is planned | [`ROADMAP.md`](ROADMAP.md) |
| What changed and when | `git log`, [closed issues](https://github.com/ericcames/sales.demos/issues?q=is%3Aissue+is%3Aclosed), and the [history archive](https://ericcames.github.io/sales.demos-docs/reference/history/) |

## 🔗 Related repositories

| Repo | What it is | Which way the dependency runs |
|---|---|---|
| [sales.demos-docs](https://github.com/ericcames/sales.demos-docs) | Talk tracks, run sheets, plans, reference | **Documents** this repo |
| [image.builder.pipeline](https://github.com/ericcames/image.builder.pipeline) | The **image factory** — CIS-hardened RHEL and Windows Server 2022 golden images | **Produces** what this repo consumes |
| [rego_policy_libraries](https://github.com/ynotbhatc/rego_policy_libraries) | OPA policy library | Consumes the factory's compliance data, not this repo |

## ⚖️ License

[MIT](LICENSE)
