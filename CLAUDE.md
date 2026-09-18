# sales.demos — repo conventions

Read the plan doc for the use case you are touching before starting work. Each
holds the environment research, the design decisions, and the phase plan,
including *why* each choice was made.

| Use case | Plan |
|---|---|
| OpenShift Virtualization | [`ocpvirt-demo-plan`](https://ericcames.github.io/sales.demos-docs/plan/ocpvirt-demo-plan/) |
| Private Automation Hub as code | [`pah-plan`](https://ericcames.github.io/sales.demos-docs/plan/pah-plan/) |
| Network MCP servers | [`network-mcp-plan`](https://ericcames.github.io/sales.demos-docs/plan/network-mcp-plan/) |
| Platform add-ons (MCP servers) | [`platform-addons-plan`](https://ericcames.github.io/sales.demos-docs/plan/platform-addons-plan/) |
| Automation Orchestrator | [`automation-orchestrator-plan`](https://ericcames.github.io/sales.demos-docs/plan/automation-orchestrator-plan/) |
| Grafana Cloud observability | [`grafana-plan`](https://ericcames.github.io/sales.demos-docs/plan/grafana-plan/) |

**The plans live in [sales.demos-docs](https://github.com/ericcames/sales.demos-docs),
not here** (#422). So do the talk tracks, run sheets and every documentation
image. They used to exist in *both* repos with nothing keeping them in step, and
20 of the 35 shared files had drifted — including a run sheet still telling
presenters that Windows "cannot be logged into yet", days after that was proven
working end to end. Clone it beside this repo:

```bash
git clone https://github.com/ericcames/sales.demos-docs.git
```

`utilities/render-demo-assets.py` and `utilities/check-docs-artifacts.py` both
default to `../sales.demos-docs`, and `utilities/notebooklm-sources.txt` names it
as a source repo.

## `docs/` does not exist here — `assets/aap-branding/` is not documentation

**Do not create a `docs/` directory in this repo.** Documentation goes to
`sales.demos-docs`. The exceptions are the four files that would break something
if moved, all of which sit beside the thing they describe: `CONTRIBUTING.md`
(GitHub surfaces it during PR creation), `terraform/ocpvirt/README.md`,
`utilities/aap-env-badge/README.md`, and `assets/aap-branding/README.md`.

**`assets/aap-branding/` holds AAP gateway configuration inputs that look like
screenshots.** `inventory/group_vars/<env>/gateway_settings.yml` reads
`logo-<env>.png.b64` through a `file` lookup **at playbook run time, including
from AAP's SCM checkout**, and `utilities/make-env-logo.py` reads
`aap-logo-white.svg` as its source artwork. Deleting any of them breaks
`config.yml` or the generator.

That is exactly what nearly happened: `aap-logo-white.svg` is byte-identical to
the copy in the docs repo, so a sweep of "images already duplicated over there"
would have taken it, and nothing would have explained why the generator stopped
working. The directory name is the fix.

`utilities/check-env-logos.py` verifies each `.b64` really is the base64 of the
`.png` beside it, and that every `gateway_settings.yml` lookup path resolves. It
deliberately does **not** regenerate the PNG to compare — that needs ImageMagick,
librsvg and a specific font, and font rasterisation is not byte-reproducible
across machines, the same reason `check-docs-artifacts.py` skips
`demo-page.png`.

## This repo is public

No customer information, ever. No customer name, password, or API token in any
tracked file, commit message, PR title or body, or issue.

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
**vault-encrypted and local only — never tracked** — and lives in the `all` group
directory so it loads for every host: both environments, *and the demo VMs*.

Untracking it in #130 is what makes this repo reusable — `secrets.yml.example`
is the contract now. #129's custom credential type replaced the vault-decrypt
approach for AAP job templates. It was `group_vars/aap/` until #5 moved it to
`all/` to cover every play. See [conventions
rationale](https://ericcames.github.io/sales.demos-docs/reference/conventions-rationale/#why-secretsyml-is-untracked-and-in-all)
for the full design history.

**It sits beside the PLAYBOOKS, not the inventory, and that is not cosmetic.**
AAP's SCM inventory sync runs `ansible-inventory` against files next to the
inventory and would expose credentials in three different ways. Do not move it
back. See [conventions
rationale](https://ericcames.github.io/sales.demos-docs/reference/conventions-rationale/#why-secrets-sit-beside-playbooks-not-inventory)
for the verification against a live AAP instance (#4).

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
- **A new RHDP environment means updating `local.yml` plus two keys in the
  vault.** `connection.yml` is **not** updated during a bootstrap or repoint — a
  stale `connection.yml` is the expected state during active development, not a
  defect. `utilities/update-connection.sh <env>` (#513) exists for the separate,
  deliberate step of committing `connection.yml` when the environment is stable.
- **`inventory/group_vars/<env>/local.yml` is the per-SE repoint overlay — and
  that IS the COP practice being taught** (#131, #499, #554).
  `local.yml.example` beside each `connection.yml` shows the keys to override;
  copy it to `local.yml` and fill in your cluster's values. Ansible loads a
  `group_vars/<group>/` directory in sorted order and the last file wins, so it
  overrides `connection.yml` with no code change. Each SE creates their own,
  points at their own cluster, and can `git pull` without conflicting on the
  identity lines. This is the same pattern the Red Hat Automation COP uses to
  manage many AAPs from one codebase.

  **`local.yml` IS the answer to the AAP job-template question**, and the
  mechanism is `config.yml`. `config.yml` runs locally with `local.yml`, resolves
  the effective values, and populates AAP inventory host variables via the API.
  So `local.yml` reaches AAP, through `config.yml`, without ever being committed.
  See [conventions
  rationale](https://ericcames.github.io/sales.demos-docs/reference/conventions-rationale/#the-localyml-overlay-and-what-it-replaced)
  for the earlier design this replaced (#166).

  **The name is load-bearing.** `connection.local.yml` sorts *before*
  `connection.yml` and loses; it would be read, silently overridden, and leave
  the user on the committed cluster believing otherwise. Measured, not assumed.
- **A fork must repoint two things, and both are variables** (#132):
  `sales_demos_scm_url` (the AAP project's `scm_url`) and
  `sales_demos_ee_upstream` (the PAH EE mirror). The first is the sharp one — a
  fork that misses it has an AAP syncing *upstream*, so its own changes never
  take effect and nothing looks wrong. `EE_IMAGE` in `utilities/build-ee.sh` was
  already env-overridable; `.github/CODEOWNERS` is deliberately left alone, as a
  fork's own to rewrite.
- **`SALES_DEMOS_VAULT_PASS` overrides the vault password path** for the three
  places that *execute* it — the `file` lookup in
  `inventory/group_vars/aap/main.yml`, `utilities/make-kubeconfig.sh`, and
  `utilities/derive-ocp-token.sh`. One variable for all three, so they cannot
  disagree. The ~73 documentation mentions of the default path are deliberately
  left alone.
- The vault password is at `~/secrets/.vault_pass_sales_demos` (`600`, in a
  `700` directory), outside this repo, following the same convention as
  `aap_config`'s `.vault_pass_<env>` files.
- **Do not create `connection.yml.example` or any new `.example` file without
  the same justification the existing ones have.** Three `.example` files exist:
  `secrets.yml.example` (the gitignored vault-encrypted secrets file),
  `terraform.tfvars.example` (the gitignored Terraform vars), and
  `local.yml.example` (one per environment — the gitignored laptop overlay,
  #499). All three follow the same rule: a gitignored file whose shape nothing
  else documents. Adding another needs that same justification.

  `connection.yml.example` in particular remains wrong because `connection.yml`
  is committed and IS the reference — an example twin would be redundant.
- Do **not** introduce a second sourceable secrets file. `docs/dev-environment.sh`
  is retired and must not come back.
- **Never weaken the guard** in `utilities/check-no-secrets.sh`. It is the only
  thing preventing a credential file from being pushed to this public repo, and
  it now makes three checks that cannot silently pass:

  1. nothing named `secrets.yml` is tracked — catches `git add -f`
  2. the `.gitignore` rule actually matches, tested with `git check-ignore`
  3. a tracked `secrets.yml`, if one exists anyway, still begins with
     `$ANSIBLE_VAULT`

  Check 1 must run **before** check 2, and the order is load-bearing. See
  [conventions
  rationale](https://ericcames.github.io/sales.demos-docs/reference/conventions-rationale/#why-check-no-secretssh-has-three-ordered-checks)
  for why.

## Environments

`sandbox` (building against), `demo` (showing customers), and `edge`
(bare-metal SNO on a NUC — on-prem / edge demo). There is no `golden`
environment — proven-good config is `main` plus a release tag, not a connection
target.

`edge` differs from the RHDP environments: it is a persistent bare-metal
cluster on a home network, not an ephemeral RHDP provisioning. DNS is local
(dnsmasq, not a public domain). The same playbooks target it via `--limit edge`.
Its SNO installer is produced by `image.builder.pipeline` Phase 5 (#86).

## Skills and playbooks

Every phase is runnable as a skill and as an AAP job template. The skill never
reimplements logic.

- `playbooks/<phase>.yml` does all the work. Idempotent, no interactive prompts,
  every input via `extra_vars`, required vars asserted at the top so both entry
  points fail identically.
- `.claude/skills/<name>/SKILL.md` does preflight checks, collects inputs, and
  invokes the playbook. Follow the shape of the skills already here — see
  `.claude/skills/sales-demos-setup/SKILL.md`: frontmatter `name` + `description`
  with explicit **TRIGGER** and **SKIP** clauses, then a Preflight Check section
  of shell one-liners, and a verification step that asks the target rather than
  trusting the Ansible recap.
- Survey variable names, skill prompt names, and playbook `extra_vars` must
  match exactly. The variable names *are* the contract.

Skills live in `.claude/skills/` and are discovered natively — no marketplace,
no `plugin.json`.

**When referencing a skill in markdown, the skill name is the link text** —
backtick-code style, linked to the SKILL.md on GitHub:

```markdown
[`/sales-demos-first-time`](https://github.com/ericcames/sales.demos/blob/main/.claude/skills/sales-demos-first-time/SKILL.md)
```

Not `[interactive skill](url) (/skill-name in Claude Code)` or other
indirect phrasings. The skill name is what you type, so it is what you read.

**A laptop run and a job template are not the same run, and only one of them is
production** (#120). `ansible-playbook` resolves `~/.ansible/collections` and the
system python; an AAP job template resolves what the EE baked in. CI cannot see
the difference — the lint gate executes nothing — so a local run is the only
pre-merge verification here and by default it checks the wrong dependency set.
`utilities/run-in-ee.sh` closes that, and `/sales-demos-verify-ee` documents it.

- **It is additive.** `ansible-playbook` stays the documented everyday command in
  every skill. Navigator is the *verification* path, run before a PR merges.
- **The arguments are byte-identical.** The wrapper adds the image and two
  read-only mounts and changes nothing you pass. `~/` paths resolve inside because
  the mounts are placed at the container's home. If the two ever have to be
  written differently, something has drifted.
- **The mounts live in the wrapper, never in a committed config.** No
  `ansible-navigator.yml`: a tracked one would put a credential directory path in
  a public repo, apply silently to anyone running `ansible-navigator` here, and
  become a second source of truth for the EE tag. The wrapper reads that tag out
  of `controller_execution_environments.yml` instead, and **fails rather than
  guessing** if it cannot.
- **`--with-hub-token` is opt-in** and required for `config.yml`, `validate.yml`,
  `setup.yml`, `sync_hub.yml`, `curate_hub.yml`. A run-time bind mount is the
  same single file #22 and #68 made authoritative, not a second stored copy — the
  distinction those issues actually turn on. Everything else runs with no token
  reachable in the container at all.
- **Pinned collections are not a pinned environment.** Measured 2026-09-04: every
  collection pin matched exactly while the laptop ran ansible-core `2.18.18rc1`
  and the EE ran `2.16.19`. That gap is currently holding a real defect (#173),
  and `build-ee.sh`'s drift check was green throughout. Quote which layer you
  mean, the same way controller `4.8.x` and platform `2.7` have to be kept apart.
- **This does not make anything runnable from AAP.** `sync_hub.yml` is still
  laptop-only (#68) — AAP has no laptop to mount from.

**`.mcp.json` is committed, and holds only what carries no secret.** The three
OpenShift servers are stdio and authenticate from a gitignored kubeconfig
generated by `utilities/make-kubeconfig.sh`; the two AAP servers (`aap-sandbox`,
`aap-demo`) are stdio and authenticate from a gitignored bearer token in `.aap/`
generated by `utilities/make-aap-mcp.sh` (#515); the two portal servers
(`portal-sandbox`, `portal-demo`) are stdio and authenticate from a gitignored
static token in `.portal/` generated by `utilities/make-portal-mcp.sh` (#555).
All three patterns name paths in the tracked file, never credentials. The AAP
and portal bridges use `npx supergateway` to convert stdio to the remote
Streamable HTTP endpoint.

The environment is in each server's *name* — `openshift-sandbox`,
`openshift-demo`, `openshift-edge`, `aap-sandbox`, `aap-demo`,
`portal-sandbox`, `portal-demo` — because one
server whose target changed underneath you is exactly the #16 failure, and it
would now have cluster-write tools attached. `openshift-demo` is `--read-only`
on purpose. AAP server posture is controlled server-side by
`aap_mcp_allow_write_operations` — during setup it runs write-enabled; after
setup it can be toggled to read-only without a Claude restart (the token and URL
do not change). `edge` is read-write like `sandbox`: it is a persistent
bare-metal SNO you own, not an environment a customer is watching.

**Ask the cluster over MCP; shell out only when no tool covers it.** When a
question can be answered by asking a cluster or AAP, use the
`openshift-<env>` or `aap-<env>` server rather than `oc`, `curl` or the AAP
API by hand. The servers exist to make that the cheap path — a tool call
instead of a kubeconfig plus a vault lookup — and they are useless if the
agent reaches for `oc` out of habit. Two things make this stick:

- **`.claude/settings.json` is tracked and allowlists the servers**, so the MCP
  path is the one that does *not* interrupt you. It is merged with each
  person's own `settings.local.json`, never a replacement for it.
- **The allowlist is per-server wildcards on purpose.** The read-only guard
  belongs at the server — `openshift-demo` is `--read-only` and `demo`'s
  `aap_mcp_allow_write_operations` is `false` — not in a list of tool names
  that goes stale the moment a server gains a tool. The environment is in the
  server's name (#16), so naming the server *is* choosing the posture.

You can check which path was taken: the terminal renders each call by its
name, so `mcp__openshift-sandbox__pods_list` used the server and
`Bash(oc get pods)` did not.

**When reporting MCP server status, call each server — do not read config
files.** A stdio server reports "Connected" if its local process starts; it
does not prove the remote cluster is alive. `openshift-demo` showed
"Connected" while `cluster-6d5xj` was expired and every call failed with
`no such host` (#523). Use lightweight calls to verify:

- OCP: `mcp__openshift-<env>__namespaces_list` with
  `fieldSelector=metadata.name=default`
- AAP: `mcp__aap-<env>__me_list`

Report **Live** if data comes back, **Dead** if it errors. Never report a
server as working based on a kubeconfig or token file existing.

**When servers are dead, run `utilities/check-mcp-staleness.sh <env>`** to
find out why — it compares kubeconfigs, AAP URLs, and AO registrations
against the effective inventory values (respecting `local.yml`) and prints
the exact `make-*` command to fix each one (#533).

**One sanctioned exception, and it is the AAP platform version.** No tool on
the AAP MCP server returns it — measured 2026-09-03, `config_retrieve` and
`status_retrieve` both give the *controller* version (`4.8.6`) and
`gateway-settings_list` returns setting categories. The server exposes API
objects; the gateway ping is not among them. So this one curl is correct, and
it needs no credential:

```bash
curl -sk https://<aap_hostname>/api/gateway/v1/ping/
# {"status":"good","version":"2.7","db_connected":true,...}
```

Named here so it is not re-argued every time someone checks a version claim,
and because the distinction it turns on — controller `4.8.x` versus platform
`2.7` — is the one that let a stale pin sit unnoticed (#101). Before shelling
out for anything else, confirm no tool covers it rather than assuming; that
check is part of the rule.

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

- **AAP 2.7** — measured on the live sandbox 2026-09-03, the gateway reports
  `2.7` and the controller behind it `4.8.6`. This line said 2.6 and told you
  to pin to it; the catalog item moved and #92's environment arrived on 2.7
  (#101). `aap_config` also targets 2.7 now, but still do not copy its
  connection settings verbatim — that caution was never about the version.

  **The controller version is not the platform version.** `4.8.x` is the
  controller; `2.7` is the platform. Reading the first as the second is exactly
  how the stale 2.6 pin survived unnoticed, so quote which one you mean.
- **`ansible.platform` over `ansible.controller`** — controller is legacy.
- **Always clean up tokens** — any playbook creating a token must delete it in an
  `always:` block so stale tokens do not accumulate.

  **The exception is a token that IS the deliverable**, and there are two:

  **1. The AAP MCP client token** (#102, #515), created by
  `utilities/make-aap-mcp.sh`. Never committed; retired by hand — the script
  prints cleanup instructions.

  **2. The PAH Galaxy token** (#69), created by `playbooks/link_hub.yml`.
  Minted from environment credentials, never stored. The playbook retires its
  own previous token. `-e hub_galaxy_link_state=absent` is the proven cleanup.

  Both inherit the creating user's permissions. See [conventions
  rationale](https://ericcames.github.io/sales.demos-docs/reference/conventions-rationale/#token-cleanup-exceptions)
  for the full safety analysis.
- **Never ship a project-local `ansible.cfg`** — Ansible picks one cfg file and
  does not merge. A local one shadows `~/.ansible.cfg`, which holds the working
  Automation Hub token, and breaks `ansible-galaxy collection install` for Red
  Hat certified content. Set inventory and options via CLI flags or env vars.
- Pin collections in `requirements.yml`.
- **`infra.aap_configuration` is the upstream reference** for config-as-code
  patterns. The [Red Hat Automation COP](https://github.com/redhat-cop/infra.aap_configuration)
  maintains it; sales.demos aligns its bootstrap patterns with this collection's
  approach (laptop bootstraps AAP, then AAP handles day-2).

## Terraform

- Official `hashicorp/kubernetes` provider with `kubernetes_manifest`. Do not add
  a community KubeVirt provider.
- `terraform/` is keyed by **platform**, not by demo — demos reuse platforms.
- State and `*.tfvars` are gitignored and must stay that way.

## Workflow

- **Start Claude here for anything spanning this repo and `image.builder.pipeline`.**
  `.mcp.json` defines `openshift-sandbox` and `openshift-edge`
  (`kubernetes-mcp-server`, toolsets `core,config,kubevirt`, read-write) and
  `openshift-demo` (same, read-only). All three are **project-scoped — they
  load only when Claude Code starts in this directory.** The producer repo has no MCP servers at all, so a session started
  there gets no cluster tools; a session started here can `cd` into it and run
  its playbooks anyway, because the working directory does not restrict shell
  access. Strictly better in one direction only.

  **It does not supply that repo's credentials.** Its Windows playbooks read
  `K8S_AUTH_HOST` and `K8S_AUTH_API_KEY` from the environment and assert them
  non-empty; `image.builder.pipeline/docs/design.md` §4.1 records that both, plus
  `WINDOWS_ADMIN_PASSWORD`, are maintained *here* and nowhere else. MCP covers
  cluster inspection and this repo's half, not those.

- **The Windows golden image pipeline is proven end-to-end** (2026-09-06).
  Three stacked bugs blocked it — the producer's cached answer file in
  `%WINDIR%\Panther` (`image.builder.pipeline` #69), the consumer's Secret key
  naming (`autounattend.xml` → `Unattend.xml`, #234), and the 15-char NetBIOS
  `ComputerName` limit (#234). All fixed and verified: clone reaches the
  desktop, `win_ping` succeeds from AAP (#257).

  **To repoint to a new image tag**, set `quay_windows_image` in
  `inventory/group_vars/{sandbox,demo}/connection.yml`, re-run
  `playbooks/link_windows_image.yml`, then clone as usual. That playbook already
  creates the private-repo pull secret, adds the `DataImportCron` template and
  imports via an explicit DataVolume (#224). Tags are immutable, so **repoint —
  never overwrite**; `20260905-1826` keeps the defect for ever.

  **The import decision is now identity, not readiness**, and the identity is
  re-read from the cluster and asserted on every run, including runs that
  import nothing. A DataVolume's source is immutable, so a changed tag deletes
  and re-imports rather than editing in place. See [conventions
  rationale](https://ericcames.github.io/sales.demos-docs/reference/conventions-rationale/#windows-golden-image-identity-not-readiness)
  for the #358 incident that drove this.

- **Run logs go to `~/ansible-logs/`, never into this repo**, and the easy way to
  get that right is `utilities/run-playbook.sh`, which names the log, creates the
  directory, passes the vault id and prints the path:

  ```bash
  ./utilities/run-playbook.sh playbooks/config.yml --limit sandbox -e target_env=sandbox
  ```

  The rule is not new — `.gitignore` states it and every skill sets
  `ANSIBLE_LOG_PATH`. What was missing is a rule for an **ad-hoc**
  `ansible-playbook` run, which belongs to no skill and so met the convention
  nowhere. Ten stray logs accumulated in `logs/` and `run-logs/` before anyone
  noticed, because the same `.gitignore` that states the rule also hides every
  breach of it. Do not recreate either directory.

  **CI cannot catch this**, and that is why the answer is a wrapper rather than a
  check: CI checks out a clean tree, so a job asserting "no `logs/` here" passes
  on every run and means nothing.

  Never pipe a run through `tee` — in a pipeline the exit status comes from
  `tee`, so a failed run reports success. The wrapper redirects and reports the
  real status.

- **Document before fixing** — open a GitHub issue before making code changes.
- **Always label new issues** — run `gh label list --repo ericcames/sales.demos`
  and apply every label that genuinely fits.
- **One concern per PR** — group by shared root cause. Would you revert these
  together? Then ship them together.
- **Additive only** — do not remove working capability until the replacement is
  proven.
- **There is no `CHANGELOG.md`, and adding one back is not the fix** (#432).

  | Question | Where the answer lives |
  |---|---|
  | What changed, and when | `git log`, plus the closed issue and merged PR |
  | Why a convention exists | this file |
  | What is planned | `ROADMAP.md` |
  | What happened before 2026-09-10 | the [archive](https://ericcames.github.io/sales.demos-docs/reference/history/) in `sales.demos-docs` |

  See [conventions
  rationale](https://ericcames.github.io/sales.demos-docs/reference/conventions-rationale/#why-there-is-no-changelogmd)
  for the full reasoning.
- **Branch from `main`; never commit to it directly.** Name the branch
  `<type>-<issue>-<slug>` — `fix-86-preflight-vault-lookup`,
  `docs-94-network-mcp-plan`. `<type>` is `fix`, `docs`, or the area being
  changed; `<slug>` is two to four words describing the change, not the file.
  Carrying the issue number is the point: it links the branch back to the
  decision without anyone reading `git log`.

  **Merged branches delete themselves — on the remote only.**
  `delete_branch_on_merge` is enabled on the repository, so a merged PR cleans up
  `origin/<branch>`. That is a repository setting, not a tracked file, so it is
  recorded here — it cannot be seen by reading the tree (#97).

  **The local branch survives the merge.** Delete it when you merge:

  ```bash
  git checkout main && git pull && git branch -d <branch>
  ```

  **`git branch --merged main` misses squash-merged branches.** Use:

  ```bash
  gh pr list --state merged --limit 30 --json headRefName -q '.[].headRefName' \
    | while read -r b; do git show-ref -q --verify "refs/heads/$b" && echo "$b"; done
  ```

  Use `-d` by default; once the upstream is gone after `delete_branch_on_merge`
  and `fetch --prune`, `-D` is correct after confirming `gh pr view <n>` says
  MERGED. See [conventions
  rationale](https://ericcames.github.io/sales.demos-docs/reference/conventions-rationale/#branch-cleanup-under-squash-merge)
  for the squash-merge edge cases (#177, #197, #571).

  **`main` is now protected, and the rule above is enforced rather than
  trusted.** Recorded here for the same reason as the line above: it is a
  repository setting and invisible in the tree.

  - **A pull request is required**, with **0 required approvals**. Zero is
    deliberate: a PR should not block on a second person being around.
  - **CODEOWNERS requests review; it does not gate.**
    `require_code_owner_reviews` is `false`.
  - **All 9 lint checks are required** — `yamllint`, `ansible-lint`,
    `secret-guard`, `secrets-example-sync`, `generated-files`,
    `skills-frontmatter`, `docs-artifacts-current`, `renderer-matches-role`,
    `fact-normalisation-agrees`.
    **Adding or renaming a CI job means updating this list** and the branch
    protection API — two steps, every time:

    1. add the job to `.github/workflows/lint.yml` and to the list above;
    2. `gh api -X PATCH repos/ericcames/sales.demos/branches/main/protection/required_status_checks`
       with `-F strict=false` and the full `contexts[]` set — **the full set**,
       because the endpoint replaces rather than appends.

    The context name must match the job id exactly — a typo does not error; the
    PR waits forever. Confirm on the next PR with `gh pr checks`.
  - **It applies to admins.**
  - Force pushes and branch deletion on `main` are blocked, and PR conversations
    must be resolved before merging.

  See [conventions
  rationale](https://ericcames.github.io/sales.demos-docs/reference/conventions-rationale/#branch-protection-and-ci-check-registration)
  for the incidents behind these settings (#435, #647).

- **This working tree is shared by more than one Claude session at a time, and
  the branch can change under you.** See [conventions
  rationale](https://ericcames.github.io/sales.demos-docs/reference/conventions-rationale/#the-worktree-mandate)
  for the 2026-09-04 incident that proved this.

  **Always use an isolated worktree for code changes.** Do not create branches,
  edit files, or commit in the main checkout — treat it as read-only. The main
  checkout stays on `main` and serves as the stable home base for MCP queries,
  `oc get`, log tailing, and other read-only work.

  ```bash
  # Create — sibling directory, descriptive suffix
  git worktree add ../sales.demos-<slug> <branch-name>

  # List all worktrees
  git worktree list

  # Work in it
  cd ../sales.demos-<slug>

  # Clean up after merge
  git worktree remove ../sales.demos-<slug>
  ```

  Claude Code's Agent tool accepts `isolation: "worktree"` and automates this —
  the worktree auto-cleans if the agent makes no changes; otherwise the path and
  branch come back in the result.

  **This is mandatory, not a suggestion.** The unconditional rule ("always use a
  worktree for code changes") eliminates the assumption that you are alone in the
  checkout. The main checkout never moves off `main`, so there is nothing to
  collide with.

  **What worktrees do not solve: cluster conflicts.** Two sessions modifying the
  same OpenShift namespace, AAP objects, or Grafana resources can still collide.
  Coordinate by giving each session a different scope — different playbooks,
  different namespaces, or different environments via `--limit`.

  The defensive habits (re-check branch before commit, explicit `git add`,
  `--head` on PR create, `git show --stat` after committing) stay as a safety
  net.
