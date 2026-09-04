# sales.demos — repo conventions

Read the plan doc for the use case you are touching before starting work. Each
holds the environment research, the design decisions, and the phase plan,
including *why* each choice was made.

| Use case | Plan |
|---|---|
| OpenShift Virtualization | [`docs/plan/ocpvirt-demo-plan.md`](docs/plan/ocpvirt-demo-plan.md) |
| Private Automation Hub as code | [`docs/plan/pah-plan.md`](docs/plan/pah-plan.md) |
| Network MCP servers | [`docs/plan/network-mcp-plan.md`](docs/plan/network-mcp-plan.md) |
| Platform add-ons (MCP servers) | [`docs/plan/platform-addons-plan.md`](docs/plan/platform-addons-plan.md) |

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
**vault-encrypted and local only — never tracked** — and lives in the `all` group
directory so it loads for every host: both environments, *and the demo VMs*.

**It used to be committed, and untracking it in #130 is what makes this repo
reusable.** A public repo that ships one person's encrypted credentials hands
everyone else a blob they cannot decrypt, cannot replace without diverging from
upstream, and that conflicts on every pull. `secrets.yml.example` is the contract
now; each machine builds its own real file from it. On a fresh clone the file
does not exist and you create it — that is the point, not a gap.

**This is why #129 exists.** AAP job templates used to receive the vaulted file
in the project's SCM checkout and decrypt it with the "Sales Demos - Vault"
credential. With nothing to decrypt, they get their credentials from the
"Sales Demos - Env Secrets" custom credential type instead, injected as
`extra_vars`. Untracking the file without that credential type breaks every job
template — the two changes belong together.

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
  two keys in the vault. **That is still the path for this repo's own two
  environments, and for anything that runs from AAP** — a job template reads the
  SCM checkout, so the change has to be committed.
- **`inventory/group_vars/<env>/local.yml` is a gitignored overlay for reusers**
  (#131). Ansible loads a `group_vars/<group>/` directory in sorted order and
  the last file wins, so it overrides `connection.yml` with no code change. It
  exists so someone who clones can point this at their own cluster and still
  `git pull` without conflicting on the three identity lines, which move roughly
  monthly here. It does **nothing** for AAP — gitignored files are not in the
  checkout — so do not offer it as the answer to a job-template question (#166).

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
- **`SALES_DEMOS_VAULT_PASS` overrides the vault password path** for the only
  two places that *execute* it — the `file` lookup in
  `inventory/group_vars/aap/main.yml` and `utilities/make-kubeconfig.sh`. One
  variable for both, so they cannot disagree. The ~73 documentation mentions of
  the default path are deliberately left alone.
- The vault password is at `~/secrets/.vault_pass_sales_demos` (`600`, in a
  `700` directory), outside this repo, following the same convention as
  `aap_config`'s `.vault_pass_<env>` files.
- `secrets.yml.example` is the **only** `.example` file in the repo. Do not
  create `connection.yml.example` or any other `.example` twin.
- Do **not** introduce a second sourceable secrets file. `docs/dev-environment.sh`
  is retired and must not come back.
- **Never weaken the guard** in `utilities/check-no-secrets.sh`. It is the only
  thing preventing a credential file from being pushed to this public repo, and
  it now makes three checks that cannot silently pass:

  1. nothing named `secrets.yml` is tracked — catches `git add -f`
  2. the `.gitignore` rule actually matches, tested with `git check-ignore`
  3. a tracked `secrets.yml`, if one exists anyway, still begins with
     `$ANSIBLE_VAULT`

  **Check 2 is the answer to a real objection, not a replacement for one.** The
  rule here used to say an ignore rule hides the file instead of verifying it,
  and that was correct: gitignoring the file and keeping the old loop would have
  been *silent*. `git ls-files` returns nothing, the loop never iterates, `fail`
  stays `0`, and the script prints "passed" — and because every other pattern in
  it also pipes from `git ls-files`, a plaintext untracked `secrets.yml` full of
  live tokens would be invisible to all of them too. So the ignore rule is not
  trusted; it is *verified*. Deleting it fails the build.

  Check 1 must run **before** check 2, and the order is load-bearing: git reports
  a tracked file as "not ignored" whatever `.gitignore` says, so testing
  check-ignore first blames `.gitignore` for a rule that is present and correct.

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

**`.mcp.json` is committed, and holds only what carries no secret.** The two
OpenShift servers are stdio and authenticate from a gitignored kubeconfig
generated by `utilities/make-kubeconfig.sh`, so the tracked file names paths, not
credentials. The environment is in each server's *name* — `openshift-sandbox`
against `openshift-demo` — because one server whose target changed underneath
you is exactly the #16 failure, and it would now have cluster-write tools
attached. `demo` is `--read-only` on purpose; keep that in step with
`aap_mcp_allow_write_operations`, which is the same decision on the AAP side.
Anything needing a bearer token stays out of this file — see the token exception
under *Ansible*.

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

  **The exception is a token that IS the deliverable**, and there are two. A
  credential created so that something else can keep using it cannot be deleted
  in an `always:` block without destroying the thing it was created for. The rule
  still holds without exception for every token created *incidentally*, to get a
  playbook's own work done.

  **1. The AAP MCP client token** (#102), created by `/sales-demos-mcp` on a
  laptop. It is never committed — `claude mcp add --scope local` writes to the
  operator's own config rather than the tracked `.mcp.json`, the same reasoning
  that keeps the Red Hat offline token (#22) and the PAH API token (#68) to a
  single copy. **It is retired by hand**; the skill documents how to list and
  delete them, and you should say so out loud when handing this to anyone.

  **2. The PAH Galaxy token** (#69), created by `playbooks/link_hub.yml`. This
  one **is** created by a playbook — the rule's earlier wording said no playbook
  creates such a token, and that stopped being true here rather than being
  wrong before. Three things keep it from being a hole:

  - **It is minted, never stored.** It comes from `aap_username` /
    `aap_password`, which already rotate with the environment, so a rebuilt
    cluster reconstructs it with nothing to go stale. That is the whole answer
    to #69's gate 3: ask how long the *environment* lives before designing
    anything that stores a credential from it.
  - **The playbook retires its own.** Gateway tokens *accumulate* (unlike the
    galaxy_ng endpoint, which resets), so `link_hub.yml` deletes the tokens it
    minted on earlier runs before minting a fresh one, matched on description.
    Exactly one should ever exist.
  - **There is a real cleanup path, and it is proven.**
    `-e hub_galaxy_link_state=absent` unassigns the credential, deletes it, and
    deletes the token. This is the half that makes the exception narrow, and it
    ships in the same PR as the link.

  Both **inherit the creating user's permissions** — Red Hat's words, not a
  paraphrase — so making one as `admin` gives the holder admin. For MCP the
  environment's `aap_mcp_allow_write_operations` is a second gate, not the only
  one. For the Galaxy token the mitigation is scope: `read`, verified sufficient
  against the hub index before it was chosen, because a project sync only ever
  downloads.
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
- **Branch from `main`; never commit to it directly.** Name the branch
  `<type>-<issue>-<slug>` — `fix-86-preflight-vault-lookup`,
  `docs-94-network-mcp-plan`. `<type>` is `fix`, `docs`, or the area being
  changed; `<slug>` is two to four words describing the change, not the file.
  Carrying the issue number is the point: it links the branch back to the
  decision without anyone reading `git log`.

  Both older styles remain in the history and are fine where they sit —
  `issue-5-ocpvirt-demo` (numbered, no type) and `docs-pill-proof` (typed, no
  number). This rule is the two of them reconciled, not a correction of either.

  **Merged branches delete themselves — on the remote only.**
  `delete_branch_on_merge` is enabled on the repository, so a merged PR cleans up
  `origin/<branch>`. That is a repository setting, not a tracked file, so it is
  recorded here — it cannot be seen by reading the tree (#97).

  **The local branch survives the merge, and this note used to say it did not**
  (#177). It read "no manual pruning is needed", which is true of the remote and
  false of the clone you are standing in, so leftovers accumulated silently —
  the note told you not to look. Delete the local copy when you merge:

  ```bash
  git checkout main && git pull && git branch -d <branch>
  ```

  `git branch --merged main` lists any that were missed.

  **Use `-d`, never `-D` — but `-d` is not a merge check, and this note used to
  say it was** (#179). `git branch --help`: *"The branch must be fully merged in
  its upstream branch, or in HEAD if no upstream was set with `--track` or
  `--set-upstream-to`."* `git push -u` sets an upstream, so every branch here has
  one, and `-d` is really asking "have you pushed?" It deleted
  `docs-177-local-branch-cleanup` while that PR was still open, and said so:

  ```
  warning: deleting branch '...' that has been merged to
           'refs/remotes/origin/...', but not yet merged to HEAD
  ```

  **So the order in the command above is load-bearing, not incidental.** Pulling
  `main` first means it already contains the merge, so the branch is merged on
  both criteria and `-d` is checking something real. Run `-d` before the pull and
  it waves through a branch whose PR never merged.

  `-d` still beats `-D`: it refuses to drop **unpushed** work, which is the loss
  that actually matters.

  **`main` is now protected, and the rule above is enforced rather than
  trusted.** Recorded here for the same reason as the line above: it is a
  repository setting and invisible in the tree.

  - **A pull request is required**, with **0 required approvals**. Zero is
    deliberate, not laziness: there is one collaborator, GitHub does not let you
    approve your own PR, and requiring one approval would deadlock every PR.
    Zero still forces the branch-and-PR flow, which is the part that matters.
  - **All 8 lint checks are required** — `yamllint`, `ansible-lint`,
    `secret-guard`, `secrets-example-sync`, `generated-files`,
    `skills-frontmatter`, `docs-artifacts-current`, `renderer-matches-role`.
    **Adding or renaming a CI job means updating this list**, or PRs will either
    wait forever on a check that never reports, or merge without one that should
    have run.
  - **It applies to admins.** Anything less would not have prevented what
    prompted it: a commit went straight to `main` because a `git checkout -b`
    failed on an existing branch and `|| true` swallowed the error. Admin bypass
    would have let that through, since the push already carried admin rights.
    Turning enforcement off for a genuine emergency is two clicks — doing that
    deliberately is a different thing from doing it by accident.
  - Force pushes and branch deletion on `main` are blocked, and PR conversations
    must be resolved before merging.
