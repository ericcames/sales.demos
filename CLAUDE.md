# sales.demos — repo conventions

Read [`docs/plan/ocpvirt-demo-plan.md`](docs/plan/ocpvirt-demo-plan.md) before
starting work. It holds the environment research, the design decisions, and the
phase plan, including *why* each choice was made.

## This repo is public

No customer information, ever. No RHDP hostname, cluster ID, deployment URL,
password, or API token in any tracked file, commit message, PR title or body,
issue, or CHANGELOG. Use generic placeholders in committed docs and examples
(`api.cluster-<id>.dyn.redhatworkshops.io`).

Audit every diff before pushing:

```bash
git ls-files -z | xargs -0 grep -nEi \
  'redhatworkshops|sha256~|[0-9]{1,3}(\.[0-9]{1,3}){3}|BEGIN [A-Z ]*PRIVATE KEY'
```

Only placeholder lines in `secrets.yml.example` may match.

## Secrets: exactly one mechanism

`inventory/group_vars/<env>/secrets.yml` (gitignored) is the only secrets file.

- **Every** environment-specific value goes there — hostnames, URLs, tokens,
  passwords — not just the strictly secret ones. A new RHDP environment must be
  a one-file edit.
- `connection.yml` is committed and holds structure only. It never varies
  between environments.
- `secrets.yml.example` is the **only** `.example` file in the repo. Do not
  create `connection.yml.example` or any other `.example` twin.
- Do **not** introduce a second sourceable secrets file. `docs/dev-environment.sh`
  is retired and must not come back.

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
