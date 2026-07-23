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

## Secrets: one file to edit

Copy the example and fill it in:

```bash
cp inventory/group_vars/sandbox/secrets.yml.example \
   inventory/group_vars/sandbox/secrets.yml
```

`secrets.yml` is gitignored and is the **only** secrets mechanism in this repo.
Every environment-specific value lives there — AAP hostname, OpenShift API URL,
tokens, quay credentials — not just the strictly secret ones.

That is deliberate: **a new RHDP environment means editing exactly one file.**
`connection.yml` is committed, holds structure only, and never changes between
environments.

`secrets.yml.example` is the only `.example` file in the repo. Its whole job is
to show you what `secrets.yml` must look like.

### Public repo

This repo is public. No RHDP hostname, cluster ID, token, or password belongs in
any tracked file, commit message, issue, or PR. Before pushing:

```bash
git ls-files -z | xargs -0 grep -nEi \
  'redhatworkshops|sha256~|[0-9]{1,3}(\.[0-9]{1,3}){3}|BEGIN [A-Z ]*PRIVATE KEY'
```

That should return nothing but placeholder lines in `secrets.yml.example`.

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

## Conventions

See [`CLAUDE.md`](CLAUDE.md). The short version: AAP 2.6, `ansible.platform`
over `ansible.controller`, tokens always deleted in an `always:` block, no
project-local `ansible.cfg`, issues before code.

## License

[Apache 2.0](LICENSE)
