# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed -- job templates now run on the 2.7-based EE, v1.1.0 (#122)
- `controller_execution_environments.yml` points at
  `sales_demos_ee:v1.1.0`, and the description string is corrected from
  `v1.0.0 ... AAP 2.6` to `v1.1.0 ... AAP 2.7`. The upstream audit-trail digest
  is updated to `sha256:be41f1ff...`.
- **Proven before it was flipped**, which is what #122's additive rule asks for.
  `Sales Demos - Install Automation Orchestrator` ran green on `v1.1.0` in
  **both** environments -- sandbox job 108 and demo job 51, each `ok=30
  changed=0`. Idempotent, and `kubernetes.core` end to end, which is exactly
  what the python-interpreter defect would have broken.
- **Rollback is one line.** `v1.0.0` stays mirrored in both hubs via
  `hub_ee_repositories.yml`, so reverting `image:` needs no re-mirror and no
  quay round trip.
- The temporary verification EE objects created to run `v1.1.0` without
  retiring `v1.0.0` first are deleted; the job templates were restored to the
  managed EE before this change.


### Fixed -- #143 broke the Automation Orchestrator job template (#122 step 2)
- `install_ao.yml` asserted and read `env_secrets[aap_env_name].aap_password`.
  **That variable does not exist in a job template.** `secrets.yml` is untracked
  (#130), so there is no vaulted file in the project checkout; the "Sales Demos
  - Env Secrets" credential type injects `aap_password` as an extra_var instead.
  The playbook therefore worked from a laptop and failed from AAP with
  `assertion: env_secrets is defined ... evaluated_to: false`.
- **This is exactly the split `CLAUDE.md` forbids** -- "required vars asserted at
  the top so both entry points fail identically". One entry point worked and the
  other could not start.
- Now reads **`aap_password`**, which `connection.yml` resolves from the vault on
  a laptop and the credential injects in AAP. `config.yml` and `curate_hub.yml`
  have always read it that way; this brings `install_ao.yml` in line.
- **Found by running the job template, not by review.** #143 was verified only
  from the CLI, where `env_secrets` is defined -- the defect was invisible from
  that side. It surfaced on the first AAP run of the playbook after #143, which
  is #122 step 2's whole purpose.


### Added -- `main` is branch-protected, and CI is now a gate rather than a convention
- A pull request is **required** to change `main`, with **0 required approvals**
  -- zero because there is one collaborator and GitHub does not permit approving
  your own PR, so requiring one would deadlock every PR. Zero still forces the
  branch-and-PR flow.
- **All 8 lint jobs are required checks.** `CLAUDE.md` said "a green CI run does
  not mean a playbook works", and that is still true; what changed is that a red
  one can no longer be merged past. Adding or renaming a job means updating the
  required list, or PRs hang on a check that never reports.
- **Enforced for admins**, which is the only setting that addresses what
  prompted it: a commit reached `main` directly because `git checkout -b` failed
  on an existing branch and `|| true` swallowed the error. Admin bypass would
  have allowed it, since the push already had admin rights.
- Force pushes and deletion of `main` are blocked; PR conversations must be
  resolved before merge.
- Verified by attempting a direct push, which was refused with
  `GH006: Protected branch update failed`.


### Added -- MCP server demo documentation in docs/demos/mcp-servers/ (#153)
- **Six files following the demo template, plus a status-table reference.** The
  MCP servers are both tooling and a demonstrable use case — the demo argument is
  governed agentic automation: the AI reads everything, changes nothing except
  through Ansible. `README.md`, `run-sheet.md`, `talk-track.md`,
  `architecture.md`, `objections.md`, and `server-inventory.md` (earned sixth
  file, same justification as PAH's `clickops.md`).
- **Phase 1: OpenShift MCP content is complete.** Tool listings, credential
  flows, verification commands, and troubleshooting tables are sourced from the
  `/sales-demos-mcp` skill and measured against live servers. AAP MCP sections
  are marked placeholders for Phase 2.
- **`server-inventory.md` is the canonical status table.** The same format
  Claude Code renders when asked "show me the MCP servers" — server name,
  transport, access posture, tool count, auth method. Per-server tool listings
  with the nine mutating tools `--read-only` removes called out explicitly.
- **Red Hat links included:** the MCP protocol spec, `kubernetes-mcp-server`
  upstream, the AAP MCP Server deployment guide, ToolHive on OpenShift, and
  `ansible.mcp_builder`.
- **Four existing docs updated.** `docs/demos/README.md` and root `README.md`
  gain a use-cases row. `ROADMAP.md` is reframed from "Not a use case: tooling"
  to "Both tooling and a demonstrable use case." This CHANGELOG entry.

### Fixed -- the EE build clobbered its own python interpreter (#122)
- **Two defects, one cause, and the second is the dangerous one.** `assemble`
  installs the system packages the collections' bindep files ask for, and that
  list includes `python3-devel`. On RHEL 9 that pulls in `python3-3.9`, which
  **repoints `/usr/bin/python3` from the base image's 3.12 to 3.9**.
  1. *Build-time:* `assemble`'s next step is `$PYCMD -m pip install`, so the
     build dies with `/usr/bin/python3: No module named pip`.
     `utilities/build-ee.sh` now passes `--build-arg PYCMD=/usr/bin/python3.12`.
  2. *Runtime:* it lands in the **final image** too. `ansible`'s own shebang
     stays 3.12, but Ansible's interpreter discovery resolves `/usr/bin/python3`
     -- now 3.9, whose site-packages has no `kubernetes`, no `yaml`, none of the
     collections' python dependencies. Every `kubernetes.core` task in this repo
     runs on the EE, so the image would have failed in front of a customer.
     `append_final` restores the symlink and then **asserts** the interpreter
     can import `kubernetes` and `yaml`.
- **`build-ee.sh`'s existing checks would not have caught the second one.** It
  verifies terraform runs as UID 1000 and that every pinned collection is at its
  pinned version; both passed on the broken image. That is why the assertion is
  in the build rather than left to the reviewer.
- **The 2.7 base did not cause this.** The 2.6 build never reached the step that
  installs `python3-devel`, because introspection found no python requirements.
  The 2.7 base's different bundled collections surface a fragility that was
  always in the definition. Nothing published is affected -- `v1.0.0` was
  checked directly and has `python3 -> 3.12` with working imports.

### Changed -- docs catch up to AAP 2.7 (#122)
- `README.md` said the EE base was "AAP 2.6" and, under Conventions, that the
  platform is 2.6; `CONTRIBUTING.md` told contributors to **pin to 2.6** because
  "this catalog item ships 2.6". All three contradicted `CLAUDE.md`, which has
  said 2.7 since #101, and the CONTRIBUTING line was actively wrong guidance.
- `.claude/skills/sales-demos-ee-build/SKILL.md`'s re-pin command still queried
  the `ansible-automation-platform-26` stream, so following the skill would have
  re-pinned the base back to 2.6.
- Grouped here rather than split out: this is docs catching up to code under one
  theme, which is what `CLAUDE.md` asks for.

### Changed -- the EE base moves from the AAP 2.6 stream to 2.7 (#122)
- `execution-environment.yml` now pins
  `ansible-automation-platform-27/ee-supported-rhel9@sha256:563d524b...`. The
  platform went to 2.7 in #115 while the image still came from the 2.6 stream,
  and the repo was already pinning 2.7-generation collections into it. **On the
  2.7 base that mismatch does not arise:** the base ships
  `ansible.controller 4.8.6` and `ansible.platform 2.7.20260812`, so the pins are
  now same-generation rather than cross-generation.
- **`microdnf` re-verified against the new digest by running the image** --
  present, `dnf` absent -- rather than assumed to carry over from the 2.6 pin.
- Built and published as **`quay.io/zigfreed/sales-demos-ee:v1.1.0`**
  (`sha256:be41f1ff...`). Verified as UID 1000: `python3 -> 3.12`, imports
  `kubernetes`/`yaml`, ansible-core 2.16.19, Terraform 1.15.8, all nine
  collections at their pinned versions.
- **`v1.0.0` is still mirrored and still what job templates run.** Per the
  additive rule, `hub_ee_repositories.yml` mirrors both tags, and
  `controller_execution_environments.yml` is deliberately NOT repointed here --
  #122 requires the replacement to run a real job template first. Flipping it is
  a one-line change, and so is rolling back.


### Added -- AAP MCP servers (aap-sandbox, aap-demo) in /sales-demos-mcp (#150)
- `/sales-demos-mcp` now sets up **four** MCP servers in one run: the two
  existing OpenShift servers (`openshift-sandbox`, `openshift-demo`) plus two
  new AAP servers (`aap-sandbox`, `aap-demo`).
- `utilities/make-aap-mcp.sh` automates the full AAP MCP client flow: resolves
  AAP hostname and password from the vault, creates a personal access token via
  the gateway API, finds the `aap-mcp` route, and registers the server with
  `claude mcp add --scope local`.
- `aap-demo` is read-only (`scope=read` on the token), matching the
  `openshift-demo` posture — the environment customers watch should not be
  mutated by the agent.
- The script prints token cleanup instructions, since these are the documented
  exception tokens that must be retired by hand.

### Fixed -- config.yml created job templates against a stale project checkout (#148)
- AAP validates a job template's `playbook:` against the project's **SCM
  checkout**, and `config.yml` never synced the project. A project whose last
  sync predated a newly added playbook failed template creation with
  `{'playbook': ['Playbook not found for project.']}` -- and
  `infra.aap_configuration` censors that message with `no_log`, so the run died
  showing a bare `fatal:` and `censored:` with no reason.
- **It aborted a routine `demo` build at stage 2 of 5.** Nobody had changed
  anything; the project simply sat at a revision from earlier in the day. CNV
  installed, then the MCP server, Automation Orchestrator and the VM
  verification never ran. #141 had recorded this as an ordering note beside the
  template, which described the trap instead of removing it.
- `config.yml` now looks the project up and syncs it **before** the dispatch
  role, blocking until the sync finishes. An async update would leave the same
  race, only narrower.
- **Only when the project already exists.** On a fresh environment it does not,
  and dispatch creates it -- which syncs at current HEAD as part of creation, so
  there is nothing stale to fix. Verified: with a project name that does not
  exist the lookup returns nothing and the sync skips cleanly rather than
  failing.
- **`scm_update_on_launch` stays `false`,** and that is not in tension with
  this. Syncing at *configuration* time is a different moment from syncing at
  *launch* time, and only the second would make a running demo unpredictable.
- **Cost measured, not assumed:** 2.4 seconds on demo. The module reports `ok`
  rather than `changed` because a project update is an action rather than a
  configuration change -- it still launched update id 37 and waited for it.
  Skippable with `-e sync_project=false`.
- `ansible.controller.project_update` rather than `ansible.platform`, by
  necessity: projects are a controller concept and `ansible.platform` ships no
  equivalent, the same reason the inventory/group/host modules are controller
  ones. Declared in `.ansible-lint` `mock_modules`, since CI lints offline.


### Added -- CI fails when the renderer diverges from the linux_configure role (#145)
- `utilities/check-renderer-fixture.py` + a `renderer-matches-role` job. #85
  proved the docs match `render-demo-assets.py`; this proves the *script*
  matches the *role*.
- **The gap this closes was worse than no check.** The renderer necessarily
  carries its own copies of things the role owns -- that is what lets it render
  without a cluster. If those diverged, #85's gate stayed green: the renderer
  and the docs agreed with each other while both disagreed with the machine
  `linux_configure` actually builds. The green tick asserted something it did
  not mean.
- **`facts.json` is verified by rendering the role's own task**, not by
  comparing key names. The role writes it from a Jinja dict literal piped
  through `to_nice_json`; the checker renders that same `content:` block with
  the renderer's fixture and diffs the result against `facts_json()`. That
  covers structure *and* values, and makes the role the source of truth rather
  than something a docstring claims to match. `to_nice_json` is supplied as
  `json.dumps(indent=4)` -- Ansible's own default for that filter, and what
  `facts_json()` already passes.
- **This was more tractable than #145 expected.** The issue offered "enforce it
  or downgrade the claim to an honest comment" and thought the second was
  likely. Rendering the task turned out to work exactly, so the docstring on
  `facts_json()` now says the claim is enforced rather than asserted.
- **`linux_configure_motd_credits`** is compared directly. The MOTD "Powered by"
  list is data, defined in the role defaults and again in the fixture.
- **A renamed or deleted task fails**, rather than silently checking nothing --
  a vanished source of truth is the same drift one level up.
- Verified in four directions: a clean tree passes; changing a credit in the
  role fails with a diff; renaming a `facts.json` key in the role fails naming
  the key; renaming the task fails saying the mirror can no longer be found.
- **Not every fixture value is reconciled, deliberately.** Gathered facts like
  `ansible_kernel`, and the pinned `ansible_date_time` that keeps output
  deterministic, exist precisely because there is no cluster. Only what the role
  owns is checked.


### Added -- CI fails when a committed banner block drifts from its template (#85)
- `utilities/check-docs-artifacts.py` + a `docs-artifacts-current` job. The demo
  docs quote `/etc/issue.net`, `/etc/motd` and `facts.json` in fenced blocks, and
  every copy is hand-pasted -- `render-demo-assets.py` prints to stdout and
  writes nothing into markdown. Editing `motd.j2` used to leave the docs stale
  with CI green.
- **Why this one matters more than a normal docs-lint.** These blocks are what
  the demo falls back to when there is no cluster, so a stale banner has a
  presenter describing a machine that does not exist, in front of a customer.
- **Blocks are located by an explicit marker**, `<!-- rendered: motd.j2 -->` on
  the line above the fence, rather than by matching surrounding prose. Prose
  matching breaks the moment someone rewords a sentence, and the marker makes
  the coupling visible to whoever edits the doc next -- which is the actual
  failure being guarded against. Four sites gained one.
- **The checker imports the renderer rather than parsing its stdout.**
  `render-demo-assets.py` wraps each artifact in a decorative banner for humans;
  scraping that would couple the docs gate to the presentation of a script whose
  job is to print things nicely. It calls `render()` and `facts_json()` instead.
- **A missing marker is a failure, not a pass.** If no document carries a given
  marker the artifact is no longer verified anywhere -- the same drift one level
  up -- so the checker fails rather than reporting a cheerful zero.
- Verified in both directions: editing `motd.j2` and touching no docs fails and
  names *both* copies with line numbers, which is #85's stated "done when";
  editing a doc fails with a unified diff; deleting a marker fails; and a clean
  tree passes with all four blocks matching.
- **`demo-page.png` is deliberately not checked.** It is a Chrome screenshot, so
  a byte diff would fail on a font or Chrome change rather than on real drift.

### Fixed -- nothing had actually drifted yet (#85)
- All four committed copies still matched their templates when the gate went in,
  22 days after #85 was filed. The check arrives clean rather than with a
  backlog, which is the good case and worth recording as the baseline.


### Changed -- Automation Orchestrator's admin password is now AAP's (#143)
- `install_ao.yml` seeds `spec.secrets.initialAdminPasswordSecretRef` from
  `env_secrets[<env>].aap_password`, so **AO and AAP are one credential** rather
  than two. Before this the operator generated a random password that had to be
  dug out of `ao-initial-admin-password` in the cluster -- different and
  unpredictable in every environment.
- **Seed-time only, and deliberately so.** The CRD says the secret "is used only
  during initial database seeding to create the admin user. Once the admin user
  exists, this secret is ignored." So it fixes every future environment and
  changes nothing on `sandbox`, whose admin already existed and had been
  updated by hand to the same value.
- **The playbook does NOT call the password-change API on every run**, and that
  is a decision rather than an omission: doing so would turn an idempotent
  install into something that rewrites a credential on a live demo platform on
  every reconcile, and would fight anyone who changed it on purpose. Changing an
  existing instance's password is an API operation, documented in the skill.
- Verified: `changed=0` on a second run, AO still `Ready=True / Degraded=False`,
  and the AAP admin password still authenticates against `/api/v1/auth/login`.


### Added -- Automation Orchestrator installs on every build, on its own database (#141)
- **`playbooks/install_ao.yml` + `/sales-demos-orchestrator` + a job template.**
  #108 established that the operator installs and all five product images pull,
  and that PostgreSQL was the only obstacle. This removes it: CloudNativePG
  supplies the database, and AO now arrives with every environment rather than
  being a catalog entry somebody could install by hand.
- **Wired into `setup.yml` as stage 4 of 5, default-on and skippable.**
  `-e install_ao=false` drops it. Default-on matches the goal; the flag exists
  because this is the longest stage and a hung add-on must not fail a build
  someone needs in twenty minutes. Setup goes from roughly 10 minutes to 15.
- **THREE DATABASES, NOT TWO, AND THE THIRD IS UNDOCUMENTED.** The CRD requires
  exactly two secretRefs -- `backendDatabase` and `temporalDatabase` -- so two
  is what you build, and then `ao-temporal-migration` crash-loops forever on
  `pq: database "temporal_visibility" does not exist` while every other
  component waits. Temporal keeps its visibility store in a separate database
  whose name is fixed and is *not* derived from the temporal database's name.
  Nothing in the CRD, the `alm-examples` sample or the operator description
  mentions it; it was found by reading the migration logs on the first live
  install.
- **Not AAP's PostgreSQL, and that was a considered choice.** `aap-postgres-15`
  is owned by the `AnsibleAutomationPlatform` CR with `blockOwnerDeletion`, so
  databases added to it sit inside something another operator recreates at
  will, and Temporal's write volume would land on the database the whole demo
  platform depends on. CloudNativePG is certified, v1.30.0, and carries no
  `valid-subscription` annotation.
- **Two traps encoded in the playbook so nobody re-finds them.** ODF's
  Multicloud Object Gateway ships a vendored CloudNativePG under
  `postgresql.cnpg.noobaa.io`, whose CRDs are present on any ODF cluster and
  will not serve `postgresql.cnpg.io` resources. And an AllNamespaces operator
  has its CSV copied into every namespace, so waiting on `items[0]` of a CSV
  list reads whichever operator happens to sort first -- both waits select by
  name.
- Verified by asking the Route for a page rather than trusting the recap: the
  playbook requires HTTP 200 before it reports success, and two consecutive
  runs report `changed=0`.

### Changed -- available_memory_gb 67 -> 63, because AO comes out of that budget (#141)
- Measured by `probe_env.yml` either side of the install: requests moved
  15.00 -> 16.91 vCPU and 50.30 -> 52.77 GiB, a delta of **1.91 vCPU /
  2.47 GiB** for nine AO pods plus one PostgreSQL instance. The
  `probe_workloads.yml` placeholder of 2.0 / 4.0 is replaced with that
  measurement.
- **Overstating this budget is the dangerous direction.** The precondition in
  `terraform/ocpvirt/locals.tf` fails closed, so a figure that is too small
  merely refuses tiers the cluster could run, while one that is too large
  admits a plan that will not schedule.


### Added -- Automation Orchestrator installed as an experiment, and it is not the blocker we expected (#108)
- **The operator installs and its images pull.** `stable` still resolves to
  `v2026.8.1787147047`, the exact version #92 recorded, and the CSV reached
  `Succeeded`/`InstallSucceeded` with the controller-manager `1/1 Running`. The
  bundle and controller images pulled from `registry.redhat.io` under the
  environment's existing pull secret -- **no separate pull secret was needed**.
  #92 could only say the operator was in the catalog and was careful that
  catalog presence is not entitlement; that guess is now retired.
- **Footprint measured twice, and the estimate was 64x too large.** Read back
  from the pod: one `manager` container requesting `cpu: 10m` / `memory: 64Mi`.
  `probe_env.yml` run before and after independently agrees -- requests moved
  15.00 -> 15.01 vCPU and 50.30 -> 50.37 GiB. It replaces an estimate of
  2.0 vCPU / 4.0 GiB. `available_memory_gb` stays **66** either side of the
  install, so nothing in `terraform/` moves.
- **All five product images pull, so entitlement is a closed question.** The
  operator installing does not prove the product it manages will run, and the
  `valid-subscription: ["Red Hat Ansible Automation Orchestrator"]` annotation
  invites the opposite assumption -- so every image the CSV lists was pulled by
  a throwaway pod that referenced it and exited 0: operator, backend, UI,
  temporal and `rhel9/redis-6`. All came down under the environment's existing
  pull secret. #108 was written expecting to hit a licensing wall; there is not
  one.
- **The real obstacle is PostgreSQL, not licensing.** The CRD requires
  `spec.postgres` with a `host` plus two distinct databases (`backendDatabase`
  and `temporalDatabase`) and offers no embedded option, so an
  `AutomationOrchestrator` instance cannot be stood up on RHDP without
  provisioning a database first. The answer to "can we demo this?" is not yet,
  and for a different reason than the issue expected -- a provisioning problem,
  not an entitlement one. #108 said both outcomes were worth writing down.
- **No playbook and no skill in this change, and it is not in `setup.yml`.**
  #108 left that open pending the outcome, and the outcome was that the operator
  is the cheap part -- automating the install of a controller nobody can
  instantiate would be automating the wrong half. **That reasoning expires with
  the database, and #141 opens to remove it:** CloudNativePG (certified, v1.30.0,
  no subscription) provisions the two databases so AO joins every `sandbox` and
  `demo` build, default-on with a skip flag.
- The operator is **left running on `sandbox`** -- 64 MiB is not worth
  reclaiming and it lets the next session go straight at the CR question. It
  sits in its own namespace labelled `sales.demos/experiment=issue-108`, and
  `docs/plan/platform-addons-plan.md` records the two-command removal. Only
  `AllNamespaces` install mode is supported, which is why it has its own
  cluster-scoped OperatorGroup rather than sharing CNV's.

### Changed -- probe_workloads.yml splits the orchestrator into two entries (#108)
- The measured operator (`installed: true`) and the still-unmeasured
  **instance** are now separate rows. Folding them into one would have let the
  part that actually costs memory vanish from the file the moment the operator
  was marked installed -- the entry would read as measured while the backend,
  Temporal, UI and redis went uncounted.


### Changed -- secrets.yml is no longer tracked (#130)
- `playbooks/group_vars/all/secrets.yml` is now **vault-encrypted and local
  only**. It was vault-encrypted and committed; untracking it is what makes this
  public repo reusable by anyone else. Shipping one person's encrypted
  credentials hands a forker a blob they cannot decrypt, cannot replace without
  diverging from upstream, and that conflicts on every pull.
  `secrets.yml.example` is the contract, and each machine builds its own file.
- **This depends on #129 and would break AAP without it.** Job templates used to
  receive the vaulted file in the project's SCM checkout and decrypt it with the
  "Sales Demos - Vault" credential. They now get their credentials from the
  "Sales Demos - Env Secrets" credential type as extra_vars.

### Fixed -- the secret guard would have gone silent (#130)
- **Gitignoring the file and keeping the old check would have passed silently.**
  `git ls-files` returns nothing for an untracked file, so the vault-header loop
  never iterated, `fail` stayed `0`, and the script printed "passed" -- and every
  other pattern in it also reads from `git ls-files`, so a *plaintext* untracked
  `secrets.yml` full of live tokens would have been invisible to all of them.
  CI would have gone green while the one thing the script guards stopped being
  guarded.
- `utilities/check-no-secrets.sh` now makes three checks that cannot no-op:
  nothing named `secrets.yml` is tracked; the `.gitignore` rule actually matches
  (`git check-ignore`); and a tracked one, if it exists anyway, still begins with
  `$ANSIBLE_VAULT`. The ignore rule is not trusted -- it is verified, and
  deleting it fails the build. That answers the standing objection in `CLAUDE.md`
  that an ignore rule hides the file instead of verifying it, rather than
  discarding it.
- **The check order is load-bearing.** Tracked-ness is tested before
  `git check-ignore`, because git reports a tracked file as "not ignored"
  whatever `.gitignore` says. Testing check-ignore first blamed `.gitignore` for
  a rule that was present and correct.

### Changed -- documentation and the first-time skill follow the new model (#130)
- `CLAUDE.md`, `README.md`, `CONTRIBUTING.md`, `.github/SECURITY.md`,
  `.gitignore`, `aap_settings.yml`, `secrets.yml.example` and the `lint.yml`
  header all said the file was committed. They now describe building it from the
  example, and `SECURITY.md` records that credentials committed before this
  change remain in git history.
- **`sales-demos-first-time` step 2 was a dead end.** It told a new user the file
  already existed and to ask for the password. On a fresh clone there is now
  nothing to decrypt. It covers two cases instead: a fresh machine, where you
  create both the file and a password of your own choosing, and a shared
  environment, where you need the file *and* the password because the file is no
  longer in git. Its step 0 audit now checks for the file too.

### Added -- AAP credential type so secrets.yml need not be tracked (#129)
- `inventory/group_vars/aap/controller_credential_types.yml` defines
  "Sales Demos - Env Secrets": four write-only fields (`aap_password`,
  `openshift_api_token`, `rhsm_org_id`, `rhsm_activation_key`) injected as
  **extra_vars**, plus the matching credential and its attachment to all six job
  templates.
- **Why it exists.** Every template carried only "Sales Demos - Vault", whose
  sole job was decrypting the vault-encrypted `secrets.yml` that AAP received in
  the project's SCM checkout. That works only while the file is tracked. #130
  untracks it, and the moment it is untracked AAP's checkout has no secrets file
  at all -- `env_secrets` goes undefined and every template fails on the
  connection asserts.
- **No playbook and no `connection.yml` changed.** `connection.yml` defines
  `aap_password` as `env_secrets[aap_env_name].aap_password`; extra_vars outrank
  group_vars, so in AAP the injected value wins and that expression is never
  evaluated, while on a laptop the local vaulted file still supplies it. One
  variable contract, both entry points.
- **This is not the #4 restriction.** AAP disallows Vault credentials on SCM
  inventory *sources*. This is a job template credential, which is the sanctioned
  way to hand a job a secret.
- **One type, two environments, no environment key in the fields.** Each RHDP
  environment has its own AAP, so `config.yml --limit sandbox` fills sandbox's
  controller from `env_secrets['sandbox']` and `--limit demo` fills demo's from
  `env_secrets['demo']`, off the same lines -- exactly how
  "Sales Demos - PAH Registry" already resolves `aap_hostname`.
- **Rotation is now an explicit act.** With the vaulted file in SCM, editing the
  vault propagated on the next project sync. Now a rotated token does nothing
  until `config.yml` is re-run *for that environment*.
- **`{  {` in the injectors is not a typo.** The `controller_credential_types`
  role rewrites brace-space-space-brace into `{{` before sending injectors to
  AAP. Written normally, Ansible would expand the template at CaC time and inject
  the *value* as a literal default instead of letting AAP substitute its own
  field at launch.
- **Known check-mode behaviour.** On an environment that has never had the type
  applied, `validate.yml` fails with
  `credential_types/?name=Sales+Demos+-+Env+Secrets returned 0 items, expected 1`
  -- check mode does not create the type, so the credential referencing it cannot
  resolve. It clears after one real `config.yml` run. The dispatch role names this
  case itself ("missing dependencies caused by check mode").

### Fixed -- check-secrets-example.py miscounted prose and YAML keys (#137)
- **Comments are stripped before the Jinja scan.** A `{{` inside an explanatory
  comment opened a match that ran to the next `}}` several lines later and
  captured every English word between them as a variable name, so a header
  explaining Jinja escaping reported `AAP`, `Ansible`, `Jinja`, `escape` and
  `hatch` as missing vault keys.
- **Only real definition sites define a variable.** The checker treated every
  mapping key anywhere in the tree as a definition. `rhsm_org_id` legitimately
  appears as a *key* under a credential's `inputs:`, which made the checker
  believe the variable was defined and then report its declaration in the example
  as an orphan -- backwards, since those are the two keys the check exists to
  protect. A key now counts only at the top level of a vars file (`group_vars/`,
  a role's `defaults/` or `vars/`) or under a `vars:` / `set_fact:` mapping.
- **The `set_fact` match handles the FQCN.** This repo writes
  `ansible.builtin.set_fact`; keying on the bare name silently missed every fact
  it sets, which turned ~50 ordinary playbook facts into "missing vault keys".
- `target_env` is now in the `NOT_A_VAULT_KEY` allowlist: it is supplied per run
  via `-e target_env=<env>` and as a job template extra_var, never stored.
- Both defects were latent in #128 and surfaced immediately when #129 added a
  file that trips them -- which is the check doing its job, one layer down.

### Fixed -- demo pointed at a cluster that no longer resolves (#135)
- `inventory/group_vars/demo/connection.yml` named the previous demo cluster in
  `aap_hostname`, `openshift_api_url` and `openshift_apps_domain`. The
  environment had been rebuilt and its credentials refreshed in the vault, but
  these three lines were not.
- **The failure gave no signal pointing here.** DNS simply stopped resolving, so
  every connection died at the network layer -- `curl` returned HTTP 000 and the
  `openshift-demo` MCP server reported only `CONNECTION_CLOSED`. Same shape as
  #101 on sandbox.
- Credentials and hostnames are refreshed in two different places by design, so
  updating one leaves no trace that the other is stale. The file header now says
  that explicitly: when an environment is rebuilt, change both.
- Verified against the rebuilt environment: the AAP gateway reports `2.7` with
  `db_connected`, the vaulted token authenticates as its cluster-admin
  ServiceAccount, and the cluster's own `ingresses.config.openshift.io` domain
  matches `openshift_apps_domain` exactly.

### Fixed -- secrets.yml.example had drifted from what the code requires (#128)
- **Added `rhsm_org_id` and `rhsm_activation_key`.**
  `playbooks/roles/linux_register/tasks/main.yml` asserts both and fails the play
  without them, and `/ocpvirt-demo` preflights for the activation key -- but
  neither was declared in `secrets.yml.example`. A secrets file built from the
  example passed every preflight and then failed Phase 4 on guest registration,
  which is the one failure mode that only surfaces in front of an audience.
- **Corrected the pre-#5 paths in the example header.** It still told the reader
  to copy and encrypt `inventory/group_vars/aap/secrets.yml`; the file moved to
  `playbooks/group_vars/all/` in #5.
- **Marked `quay_username`, `quay_password` and `windows_admin_password` as not
  yet consumed.** No tracked file reads any of the three -- they are staged for
  the Phase 2 Windows golden image. Kept rather than deleted (additive only), but
  named in an allowlist so that adding a future orphan is deliberate.

### Added -- CI check that keeps the example honest (#128)
- `utilities/check-secrets-example.py`, wired in as the `secrets-example-sync`
  job. The real `secrets.yml` is vault-encrypted, so CI can never diff the two.
  Instead it finds every variable referenced under `playbooks/` or `inventory/`
  that nothing in either tree defines *and* that is used at least once without a
  `| default(...)` guard. Those can only come from the vault, so each must be
  declared in the example.
- **The bare-versus-defaulted distinction is the whole discriminator.** It is
  what separates a required credential from an optional override:
  `tf_state_namespace` is always written with a default and needs no vault entry,
  while `{{ rhsm_org_id }}` is used bare and will fail the play outright. On the
  current tree it identifies exactly the six vault keys and nothing else.
- Also fails on a declared key nothing reads, and on an `env_secrets` credential
  present for one environment but not the other -- a file that works right up
  until someone runs against the environment customers see.

### Added -- AAP self-service portal, ported from aap.selfservice (#103)
- `playbooks/portal.yml` and the `sales-demos-portal` skill deploy Red Hat
  Developer Hub with the AAP plugin via the `redhat-rhaap-portal` Helm chart
  (2.1.0). One playbook, two phases: bootstrap the portal (OAuth app, namespace,
  secrets, Helm deploy), then sync the org list and patch the portal ConfigMap.
- **Ported from `aap.selfservice`, not built from scratch.** That repo validated
  the Helm path on 2026-05-06 (~11 min end to end). The work here is adapting
  credentials and connection flow to this repo's conventions -- `env_secrets` in
  the vault, `connection.yml` for non-secrets, `--limit` for environment
  selection. No new vault keys needed: every credential the portal requires
  already exists.
- **Helm, not the RHDH operator.** Both are available on the cluster (operator
  `rhdh-operator.v1.10.3` on the `fast` channel). The Helm chart bundles RHDH
  with the AAP plugin pre-wired; the operator deploys generic RHDH and the
  plugin would need wiring manually. That is a build, not a port, and the chart
  path is already proven.
- **Three hard-learned facts survived the port (and live debugging).** (1) OAuth
  applications live in the gateway registry (`/api/gateway/v1/applications/`),
  never the controller's. (2) Never PATCH `client_secret` -- the gateway hashes
  it differently on PATCH than on POST, giving `invalid_client` at `/o/token/`.
  The playbook deletes and recreates the application on every run. (3) AAP 2.7
  defaults `pkce_required` to `true`; RHDH's RHAAP auth provider does not send
  PKCE parameters, so the OAuth flow fails silently -- AAP redirects back
  without an authorization code and the portal shows "You have to provide code
  or refreshToken". The playbook sets `pkce_required: false` explicitly.
- **The service token is durable by design.** Same exception pattern as the MCP
  client token documented in CLAUDE.md. The portal backend uses it to sync
  templates and serve API requests. Cleaned up in `rescue:` only if the OCP
  setup block fails.
- **Replaces `oc rollout status` with `k8s_info` polling.** The source repo
  shelled out to `oc`; the port polls the Deployment for
  `updatedReplicas == replicas` and `unavailableReplicas == 0`, matching the
  pattern `mcp_server.yml` already uses.
- **Not added to `setup.yml`.** The portal is a platform addon (#92 Phase 4),
  not part of the base environment build. It runs separately via the
  `sales-demos-portal` skill or a future job template.
- `.ansible-lint` gains `ansible.platform.application` and `kubernetes.core.helm`
  as mock modules -- both are used by the portal playbook and CI lints offline.

### Fixed -- skill preflights rejected a valid ServiceAccount token (#105)
- The token-shape check in `ocpvirt-setup` and `sales-demos-first-time` only
  accepted `sha256~` OAuth tokens. A ServiceAccount JWT -- the better credential,
  since it does not expire mid-run -- starts `eyJ` and was rejected with a message
  blaming the vault password or a missing `env_secrets` key, neither of which was
  the problem.
- **Both call sites now accept either form.** `sha256~*` for OAuth tokens and
  `eyJ*.*.*` for ServiceAccount JWTs. The `eyJ` pattern still rejects the #86
  failure mode (an Ansible error string contains spaces and starts with neither
  prefix), so the guard that was added to stop non-empty garbage from passing as
  a credential is preserved.
- The prose in `sales-demos-first-time` Step 7 previously said a value "that is
  non-empty but not a `sha256~` token will fail later as a confusing 401"; it now
  describes both accepted forms and why the #86 case is still caught.

### Fixed -- validate.yml could not run on the environment it was most needed for (#106)
- `validate.yml` told you to *"run this before config.yml, always"* and then
  died on any environment where `config.yml` had never run -- the first apply
  against a brand-new cluster, which is exactly when a dry run is worth the
  most.
- **A read-after-write across two roles, not version drift.** Dispatch runs
  `hub_ee_registry` then `hub_ee_repository`, and the second reads back the
  registry the first would have written. In check mode that write never happens,
  so `ansible.hub` 1.1.0 indexes an empty lookup and raises
  `KeyError: 'id'` at `ah_ee_repository.py:238`.
- **And it failed opaquely.** `aap_configuration_secure_logging: true` hid the
  traceback behind `censored: 'the output has been hidden...'`, so the reported
  symptom was a censored failure with no cause.
- **The fix is conditional, not a blanket skip.** A read-only pre-flight asks
  the hub which EE registries exist. Only when a declared one is genuinely
  absent does it empty `hub_ee_repositories_all`, so dispatch includes the role
  with nothing to iterate instead of crashing. Once `config.yml` has created the
  registry the pre-flight does nothing and full coverage returns -- **the gap
  exists only on the first run, and the next validate closes it.**
- **The coverage gap is stated where it happens.** #106 asked for that
  explicitly. The skipped run does not validate the items in
  `hub_ee_repositories.yml`, and both the task comment and the runtime message
  say so, along with the command that removes the skip.
- The pre-flight uses `ansible.builtin.uri` with the password from
  `env_secrets`, the same way `sync_hub.yml` reaches this hub -- the credential
  never reaches a shell variable or a process argument.
- Verified on live sandbox both ways: registry present, `ok=199 changed=11
  failed=0` with no skip; registry absent, `ok=192 changed=10 failed=0` with the
  skip and its explanation. Neither fails.

### Fixed -- the last unverified AAP 2.6 claim, now measured (#116)
- `hub_collection_remotes.yml` said all three remotes already exist on a fresh
  **AAP 2.6** hub. That claim is load-bearing, not decorative: the entire file
  is written as updates rather than creations, so a missing remote would mean
  updating something absent.
- **Measured against the live 2.7 hub** 2026-09-03 via
  `GET /api/galaxy/pulp/api/v3/remotes/ansible/collection/`: count 3, named
  `validated`, `rh-certified`, `community` -- exactly the three declared,
  unchanged across the version move. The version stamp is dropped rather than
  bumped, matching the treatment the other #116 claims got.
- **The query ran through Ansible, not a shell curl.** Reading the vault
  password into a shell variable to pass to `curl -u` was blocked by the
  permission classifier, correctly. `ansible.builtin.uri` with the password
  resolved from `env_secrets` is how this repo already handles hub credentials
  in `sync_hub.yml` -- the password never reaches a shell variable or a process
  argument. The shell version was the shortcut; the block caught it.
- This closes the last open item in #116 apart from the execution environment,
  which turned out to be a larger finding and moved to its own issue (#122).

### Fixed -- the AAP 2.6 assertions that survived the 2.7 move, re-measured rather than re-typed (#116)
- #115 adopted 2.7 but deliberately left nine `AAP 2.6` strings alone, because
  #101's instruction was **re-verify, do not blind-edit**. Each is now measured.
- **The load-bearing one holds.** `playbooks/sync_hub.yml` builds
  `hub_api` from the claim that the gateway fronts Hub by PATH at
  `/api/galaxy/`. Verified two ways on 2.7: only two Routes exist in the `aap`
  namespace (`aap`, `aap-mcp`), so there is still no hub route; and the
  platform's own hub API reports its links rooted at
  `/api/galaxy/v3/plugin/ansible/content/...` -- the exact path the playbook
  builds. `/pah-sync` was never broken. Same correction applied to
  `hub_ee_registries.yml` and `controller_credentials.yml`.
- **The version stamp is dropped rather than bumped** on those three. The claim
  has now held across a major platform version; pinning it to one release
  understates what is known about it.
- **The `ansible.controller` fallback is still necessary.** Measured against the
  pinned collections: `ansible.platform 2.7.20260604` ships neither a host nor a
  group module, while `ansible.controller 4.8.0` ships both. `provision_vm.yml`
  keeps its deliberate exception to the ansible.platform-over-ansible.controller
  rule, now dated to 2.7 and flagged for removal whenever that gap closes.
- `pah-sync`'s skill description said PAH "ships with every AAP 2.6
  environment". PAH ships with AAP generally, so the version is dropped rather
  than bumped -- it added nothing and dated badly.
- **Two items are deliberately unchanged**, and the PR says why: the collection
  remotes claim needs a credentialed hub API call, and the execution environment
  turns out to be a larger finding than a stale comment.

### Changed -- available_memory_gb raised from 14 to the measured 67 (#118)
- `playbooks/probe_env.yml` measured sandbox on 2026-09-03 and recommended
  **67**: 124.68 GiB allocatable, 49.05 GiB already requested, 75.63 GiB free,
  less an 8 GiB safety margin. Cross-checked against `oc describe node`.
- **This unblocks nothing today, and that is worth stating plainly.** The
  largest shipped request is `os_type=both` at `large` -- 2 VMs x 6 GiB plus
  350 MiB overhead each, about 12.7 GiB -- which passed under 14 just as it
  passes under 67. `variables.tf` already said no shipped combination trips the
  guard. This makes the safety net *accurate* rather than arbitrary, so that
  when it does bind it binds on a real number.
- **The probe's number is used as emitted.** Shaving it to reserve room for the
  add-ons in `probe_workloads.yml` was considered and rejected: shipping a probe
  and then not trusting its output one commit later is how hand-adjusted figures
  start. The workflow is install an add-on, re-run the probe, take the new
  number.
- **The 14 had leaked into six documents**, all now corrected: `README.md`,
  `ROADMAP.md`, `docs/demos/openshift-virtualization/architecture.md`,
  `docs/plan/ocpvirt-demo-plan.md`, and the `controller_schedules.yml` comment
  in both environments.
- **The overnight-teardown rationale was rewritten, not deleted.** Both
  `controller_schedules.yml` files justified the schedule by arguing memory
  headroom was scarce. At 75 GiB free that argument no longer holds, but the
  schedule is still right for a different reason -- RHDP environments are
  metered and reclaimed, so a VM running overnight burns quota -- and #92's
  add-ons come out of the same budget. Capacity being comfortable today is not
  a guarantee, which argues for keeping the teardown.
- **`ocpvirt-demo-plan.md` gets a third correction entry rather than an edit.**
  That line already recorded one correction (35 GB -> ~14 GiB in #2); it now
  records this one too. The figure has been wrong twice, in both directions, and
  each time it read as settled fact -- so the history is the useful part, and
  the durable fix is the probe rather than a better number.
- **Tier sizes were deliberately not revisited.** `sd1.large` is 6 GiB because
  `u1.large`'s 8 GiB did not fit the old budget; it would fit now. Resizing is a
  separate decision with its own blast radius, and #100's lesson is that a
  number moves when something is measured, not when it merely becomes possible.

### Added -- a read-only cluster probe, because the memory budget was five times wrong (#100)
- `playbooks/probe_env.yml` and the `sales-demos-probe-env` skill measure what a
  cluster actually has: allocatable, what is already requested, what is free,
  and a recommended `available_memory_gb`.
- **The number it replaces was never wrong in a way anything reported.**
  `terraform/ocpvirt/variables.tf` declared `available_memory_gb = 14`, measured
  once on a smaller cluster. Sandbox has **75.63 GiB** free. The budget guard in
  `locals.tf` fails *closed*, so a stale figure does not error -- it silently
  refuses tiers the cluster could run, and the demo just gets smaller.
- **Strictly read-only.** Every task is `k8s_info`; a run reports `changed=0`,
  so it is safe mid-demo when someone asks whether the cluster can take another
  VM. That is why it is a second playbook rather than a flag on
  `prepare_env.yml`, which builds and destroys a real VM to do its job.
- **Requests, not usage.** The scheduler places pods and KubeVirt VMs against
  requests; live consumption does not decide whether the next one fits. Both are
  printed side by side because the gap on sandbox is 21 GiB -- optimising
  against live usage would suggest room that is not there.
- **Two accounting rules, either of which silently skews the answer.** A pod
  reserves `max(sum(containers), max(initContainers))`, not the sum of
  everything. And only pods with `spec.nodeName` hold capacity -- an unscheduled
  Pending pod reserves nothing. Getting the second wrong inflated the first run
  by 1.56 GiB and 0.82 vCPU against `oc describe node`; the corrected probe
  matches the node's own accounting exactly (`14.5 vCPU / 49.05 GiB` against
  `14500m / 50231Mi`).
- `inventory/group_vars/aap/probe_workloads.yml` holds candidate add-on
  footprints as data, **each tagged with a `source:`** saying whether it is
  measured, derived or a guess. A guessed number and a measured one look
  identical once written down, which is precisely how `14` survived; the tag is
  what stops that recurring.
- Confirmed on sandbox 2026-09-03: OpenShift 4.20.34, CNV `Available=True`, and
  both add-on operators (`mcp-gateway`, `automation-orchestrator-operator`)
  offered on OperatorHub -- the outstanding question in
  `docs/plan/platform-addons-plan.md`, which now opens with the measurement.
- **`variables.tf` is deliberately not changed here.** Raising the default
  changes which tiers `plan` accepts, and behaviour changes ship on their own.

### Changed -- the repo targeted AAP 2.6 while its only live environment ran 2.7 (#101)
- **Measured, not assumed.** The sandbox gateway returns
  `{"status":"good","version":"2.7",...}` and the controller behind it reports
  `4.8.6` (2026-09-03). `inventory/group_vars/aap/main.yml` said
  `aap_target_version: "2.6"` with a comment asserting the catalog item ships
  2.6. The catalog item moved; #92's environment arrived on 2.7.
- **The pin is declarative -- nothing reads it.** Confirmed by grep across the
  repo and `~/.ansible/collections`: the only occurrence was its own
  definition. Correcting it changes no behaviour, and it is kept rather than
  deleted because it records which version the surrounding configuration was
  measured against.
- **The controller version is not the platform version**, and conflating them
  is how the stale pin survived. `4.8.x` is the controller, `2.7` the
  platform. Both `main.yml` and `CLAUDE.md` now say which is which.
- **`available_memory_gb` is deliberately still 14.** cluster-kbjvc is larger
  than the cluster that 14 was measured on, so the default under-provisions --
  it fails closed in `plan` rather than leaving a VM Pending. It is not
  re-measured because the honest number is not knowable yet: CNV is not
  installed here, and its own footprint comes out of the same budget, so any
  figure taken now is wrong the moment `/ocpvirt-setup` runs. The reasoning is
  recorded in `terraform/ocpvirt/variables.tf` rather than left implicit.
- **`CLAUDE.md` names the one sanctioned curl.** No tool on the AAP MCP server
  returns the platform version -- `config_retrieve` and `status_retrieve` both
  give the controller version, `gateway-settings_list` gives categories -- so
  `GET /api/gateway/v1/ping/` is the only source, needs no credential, and is
  now an explicit exception to the #113 MCP-first rule instead of an
  undocumented one the issue was already relying on.
- Step 3 of #101 (re-verifying the 2.6 measurement claims) had already shipped
  in `37ffbbc`; the issue was simply never updated. No files were re-touched.

### Added -- the MCP servers are now the default path, not an option (#113)
- The servers connected but nothing made the agent *use* them. `oc` and `curl`
  were pre-approved in a personal `settings.local.json` while no MCP tool was,
  so the shell path ran silently and the MCP path stopped to ask. Given a free
  path and a prompting one, habit wins.
- **`.claude/settings.json` is now tracked** and allowlists
  `openshift-sandbox`, `openshift-demo` and `aap-sandbox`. Claude Code merges
  it with each person's `settings.local.json`, so it is additive -- no existing
  local permission is replaced, and a fresh clone gets the same behaviour
  without hand-configuring anything.
- **The entries are per-server wildcards on purpose.** The read-only guard
  belongs at the server, where it already is: `openshift-demo` runs
  `--read-only` and `demo`'s `aap_mcp_allow_write_operations` is `false`, while
  `sandbox` is write-enabled on both. Because the environment is baked into the
  server *name* (#16), naming the server is choosing the posture -- and a list
  of individual tool names would go stale the first time a server gained a
  tool. Widening `openshift-sandbox` grants nothing the shell did not already
  have there: `oc delete`, `oc apply` and `oc patch` were unprompted already.
- `CLAUDE.md` carries the matching directive, and records that the check is
  direct -- the terminal renders each call by name, so
  `mcp__openshift-sandbox__pods_list` used the server and `Bash(oc get pods)`
  did not.
- **Config and docs only.** No playbook, no deployed server, no environment is
  touched.

### Fixed -- the MCP server's ingress choice was documented under a key that cannot hold it (#111)
- `CHANGELOG.md` and `docs/plan/platform-addons-plan.md` both said `service_type`
  is pinned to `Route`. **`Route` is not a legal `service_type`.** Read from the
  live CRD on `cluster-kbjvc`, the two keys carry different enums:
  `ingress_type` takes `none`/`Ingress`/`Route` (default `Route`), `service_type`
  takes `LoadBalancer`/`ClusterIP`/`NodePort` (default `ClusterIP`). The docs had
  taken `service_type`'s enum values and attached them to the value pinned on
  `ingress_type`.
- **The #29 reasoning was sound but filed under the wrong key.** `LoadBalancer`
  and `NodePort` are service types, so "both are dead on RHDP" justifies
  `service_type: ClusterIP` -- it says nothing about `ingress_type`.
- The old wording also implied both keys were pinned *away* from their defaults.
  They are not: `Route` and `ClusterIP` are each the CRD default. Pinning them is
  still right, because an operator upgrade can move a default, and #29 means
  neither is a value to inherit silently. The corrected text says that instead.
- **Docs only.** `playbooks/mcp_server.yml` already applied the correct keys and
  the deployed `AnsibleMCPServer/aap-mcp` already carried them; nothing about the
  running server changed.

### Added -- the AAP MCP server, deployed by Phase 0 (#102)
- `playbooks/mcp_server.yml` deploys it and `setup.yml` runs that as stage 3 of
  4, so a freshly built environment **arrives with it on** rather than needing a
  second visit. Verified on `cluster-kbjvc`: 140 tools, including
  `job_templates_launch_create`, `workflow_job_templates_launch_create` and
  `jobs_stdout_retrieve` -- steps 4 and 5 of the demo stories in #93 and #99.
- **It uses the typed CRD, not the documented shortcut, and that is the whole
  point.** Red Hat's docs say to add an `mcp:` block to the AAP CR. Measured on
  the live 2.7 CRD, `spec.mcp` is `x-kubernetes-preserve-unknown-fields` with no
  sub-properties -- **the API server accepts a misspelled key and reports
  success**, giving a green run and no server. The operator also owns
  `ansiblemcpservers.mcpserver.ansible.com` with 31 validated fields, which is
  what `spec.mcp` produces anyway. Applying it directly means a bad field name is
  rejected at apply time instead of silently ignored.
- **`allow_write_operations` is not idempotent, per Red Hat's own docs:** *"If
  you changed the permissions of the MCP server after it was created and
  deployed, you must delete the AnsibleMCPServer custom resource and recreate
  it."* A plain apply that flips it leaves a server enforcing the OLD permission
  while the CR claims the new one. The playbook reads the live object and deletes
  first. That is why it is longer than an apply, and it must not be simplified.
- **The write posture is per-environment and deliberately has no default** --
  `true` on `sandbox`, `false` on `demo`, and the playbook *refuses to run* if it
  is unset. A silent default is the wrong way to decide whether an agent can
  POST, PATCH and DELETE.
- **Ingress type and service type are both stated, never inherited.**
  `ingress_type: Route` is what makes the server reachable; `service_type:
  ClusterIP` keeps it off `LoadBalancer` and `NodePort`, which are dead on RHDP
  (#29). Each is also the CRD's current default -- they are pinned so an operator
  upgrade cannot move them out from under a working deployment.
- **A bug the first live run found, kept rather than papered over.** Probing the
  freshly admitted Route returned **503** -- the router had a backend with
  nothing behind it. The playbook now waits for the Deployment to report a ready
  replica, not merely for the Route to exist, and the skill's failure table says
  a 503 shortly after deploy means "wait", not "misconfigured".
- **`CLAUDE.md` gains its first documented exception to "always clean up
  tokens".** An MCP client needs a *durable* credential, so an `always:` block
  would destroy the thing it was created for. Three things keep it from being a
  hole: no playbook creates it (the skill does, on a laptop), it is never
  committed (`claude mcp add --scope local`, not the tracked `.mcp.json`), and it
  is the one token here you retire by hand. It also **inherits the creating
  user's permissions** -- Red Hat's words -- so `allow_write_operations` is a
  second gate, not the only one.
- Recorded in passing: **tokens moved in 2.7.** `/api/controller/v2/tokens/` is
  now `404`; the gateway owns them at `/api/gateway/v1/tokens/`.

### Added -- the OpenShift MCP servers, so asking a cluster a question is a tool call (#102)
- **The cost this removes is real and this repo was paying it constantly.** Every
  question asked of a cluster in #101 -- node capacity, which EE registries
  existed, whether `spec.mcp` was on the CR -- cost a `curl`, a vault read and a
  JSON parse, hand-assembled each time. `.mcp.json` replaces that with a tool
  call.
- **The OpenShift server runs on the laptop, not in the cluster**, reversing what
  #92 assumed. It filed `kubernetes-mcp-server` as a "zero-footprint fallback";
  it is the correct primary. An in-cluster server **can never help bootstrap the
  environment it runs in**, and dies with every expiring RHDP cluster -- this
  session began by finding both of this repo's had expired. A local one re-reads
  `connection.yml` and carries on.
- **It also takes #94's Decision C off the critical path.** That decision --
  containerize, adapt stdio to streamable HTTP, Route, auth, vault-to-Secret --
  exists because every *network vendor* MCP server is stdio-only with no
  container image. Claude Code and a stdio server both run on the laptop, so
  there is no gap to cross here at all.
- **Two servers, one per environment, named after it.** `openshift-sandbox` has
  full access (25 tools); `openshift-demo` is `--read-only` (16). The environment
  is in the server's *name*, so you pick it by picking the tool. One server whose
  target silently changed underneath you is exactly #16 -- where `--limit demo`
  resolved to sandbox's hostname and token with no warning -- and repeating that
  with cluster-write tools attached would be materially worse.
- **`--read-only` was measured, not assumed.** It removes precisely the nine
  mutating tools and keeps every investigative one, including `vm_guest_info`
  and `vm_troubleshoot`. So `demo` can still diagnose a broken VM and cannot
  change it -- #93's "agent reads, Ansible writes" thesis costing nothing here,
  unlike Dynatrace (#99), where it costs a withheld scope.
- The `kubevirt` toolset is enabled, adding `vm_create`, `vm_clone`,
  `vm_lifecycle`, `vm_guest_info` and `vm_troubleshoot` -- directly relevant to a
  repo whose whole first use case is OpenShift Virtualization.
- `utilities/make-kubeconfig.sh` derives `.kube/<env>.kubeconfig` from
  `connection.yml` plus the vault. **Nothing new is stored**: it is gitignored,
  `0600`, and regenerable, so it is a cache with an obvious refresh rather than
  the second copy of a rotating credential that #22 and #68 both refused. It
  accepts **both** token shapes, because #105 is open precisely for a check that
  accepted only `sha256~` and rejected a valid ServiceAccount token.
- **One new prerequisite, and it is the first non-Red-Hat one:** `npx`. Recorded
  in `/sales-demos-first-time` step 4.5, with the standalone binary noted as the
  escape hatch for anyone who would rather not install Node.
- **Known rough edge, stated rather than hidden:** a fresh clone shows a *failing*
  MCP server until `/sales-demos-mcp` runs, because the committed config points
  at a kubeconfig that does not exist yet. The alternative -- following whatever
  `~/.kube/config` happens to point at -- trades a visible, self-explaining
  failure for a silent, wrong-environment success. That is the worse trade.
- `docs/plan/platform-addons-plan.md` is written to **teach the mechanism**, not
  just record the decision: what a tool call is, and why the stdio-versus-HTTP
  transport split is the single fact that makes the network servers in #94 hard
  and these easy.

### Changed -- the three "VERIFIED ON AAP 2.6" claims, re-measured on 2.7 (#101)
- #101 step 3 says **re-verify, do not blind-edit**, the claims 2.7 might
  invalidate. Measured against the live 2.7 gateway and controller on
  `cluster-kbjvc`. **Two of the three held; the third was wrong in both files
  that asserted it.**
- **The gateway settings count was wrong, and had been wrong before this.**
  `gateway_settings.yml` recorded 44 settings on 2.6; `make-env-logo.py`
  attributed 43 to 2.7 from upstream documentation. The live 2.7 gateway returns
  **41**. All 41 were enumerated by name.
- **The conclusion those counts supported survived intact** -- none of the 41
  marks the environment post-login, so `custom_logo` really is a sign-in-time
  marker and the browser-extension half of the design is still necessary.
  `custom_logo` also reads back at 26,714 characters, matching the "26 KB of
  base64 PNG" measured in #54.
- **So the counts are gone rather than corrected in place.** A number that has
  now been stated three ways across two versions is the least durable part of
  the claim, and quoting it invites the next reader to trust the tally over the
  finding. The finding is what is load-bearing; it is what the comments now say.
- `controller_settings.yml` **held**: all five keys exist on the 2.7 controller,
  which exposes 111 settings in total. What was a 2.6-only measurement is now
  one on both versions.
- **`aap_target_version` and `available_memory_gb` are deliberately untouched.**
  They are step 2 of #101 and wait on the probe in #100 -- `available_memory_gb`
  is the value a hardcoded guess got wrong by roughly 4x, so replacing one guess
  with another would repeat the mistake this sequencing exists to avoid.

### Changed -- `sandbox` repointed at the live cluster, because both environments had expired (#101)
- **Both environments this repo points at were dead**, and nothing in the tree
  said so. `api.cluster-k59xk-1` (`sandbox`) and `api.cluster-xcvjx-1` (`demo`)
  both refused connections; the local `~/.kube/config` still pointed at the
  former. The repo had **zero runnable environments**, which is a state every
  playbook here fails in identically and unhelpfully -- a connection error, not a
  message saying the cluster is gone.
- `sandbox` now points at `cluster-kbjvc`, the AAP 2.7 environment measured in
  #92 and confirmed live: the API answers 200 on kubelet v1.33.13, and AAP
  reports `{"status":"good","version":"2.7","db_connected":true}`.
- Three values in `inventory/group_vars/sandbox/connection.yml`, plus the two
  `env_secrets.sandbox` keys in the vault. **Note the new cluster has no `-1`
  suffix** -- every RHDP environment so far has carried one, so this is the kind
  of detail that gets pattern-matched wrong.
- `openshift_apps_domain` was not assumed from the API hostname. The AAP route at
  `aap-aap.apps.cluster-kbjvc.dyn.redhatworkshops.io` answering 200 is itself
  proof of the ingress domain, and it was then confirmed against
  `oc get ingresses.config.openshift.io cluster`.
- **`demo` is deliberately left pointing at a dead cluster.** Repointing it needs
  a demo-purposed RHDP environment, not this one, and quietly aiming both
  environments at the same box would erase the distinction `--limit` exists to
  enforce.
- **This makes the cluster reachable, not demo-ready.** CNV is not installed on
  `cluster-kbjvc` -- no `kubevirt.io` API group, no `devices.kubevirt.io/kvm` --
  so `/ocpvirt-setup` still has to run before any VM phase works. Stated here
  because "the repoint is merged" reads like "the demo works", and it does not.
- The 2.7 adoption proper -- `aap_target_version`, `available_memory_gb`, and
  re-verifying the three "VERIFIED ON AAP 2.6" claims -- is the rest of #101 and
  waits on the probe in #100, so that the memory budget is a measured number
  rather than a second folk figure.

### Added -- the branch convention, which existed in git log in two shapes and nowhere in CLAUDE.md (#97)
- `CLAUDE.md` -> *Workflow* documented five conventions and **nothing about
  branches**. The gap surfaced concretely: asked which branch to use for #94, the
  convention had to be reverse-engineered from `git log`, which turned up two
  competing patterns and no rule between them -- `issue-5-ocpvirt-demo` (numbered,
  no type) against `docs-pill-proof` (typed, no number), with
  `fix-86-preflight-vault-lookup` the only recent branch carrying its issue
  number. Both are defensible; neither was written down, so every new branch was
  a fresh judgement call.
- The stated rule is `<type>-<issue>-<slug>`, which is the two existing styles
  reconciled rather than a correction of either. Both remain in the history and
  neither needs rewriting. Carrying the issue number is the load-bearing part --
  it links a branch back to its decision without anyone reading `git log`.
- **`delete_branch_on_merge` is now enabled on the repository**, so merged PR
  branches clean up after themselves. This is recorded here and in `CLAUDE.md`
  precisely because a repository setting **leaves no trace in the tree** -- there
  is no file a reader could check to discover it.
- Prompted by a cleanup that deleted 17 local and 11 remote branches, leaving
  only `main`. **That backlog existed because the setting was off.** Every branch
  was verified landed before deletion, including six that `git` reported as
  unmerged: their patch-ids had drifted through squash or rework, but the content
  was demonstrably in `main` -- checked by confirming every file each branch
  touched is present, not by trusting `git cherry` alone. The one file unique to
  those six was `utilities/aap-env-badge/envs.json`, the superseded name of
  `colors.json`.

### Changed -- the DevNet sandboxes are up, and B1 is a plan rather than a candidate (#94)
- **The previous entry's caveat was wrong, and wrong in the useful direction.**
  It recorded DevNet sandbox availability as unresolved because Cisco's docs and
  Cisco Community threads disagreed, and said only signing in would settle it.
  Signing in settled it: the always-on labs are back, the February 2026 community
  reports are stale, and Cisco's own documentation was right. The catalog's only
  maintenance banner is for the **Cisco Security Cloud Control** lab, which is
  unrelated. **Catalyst Center Always-On v2.3.3.6 is live and launchable**, which
  is exactly the target the Cisco issue needs.
- **Seven always-on sandboxes exist where the plan assumed one.** Beyond Catalyst
  Center: **Catalyst 8000** and **Catalyst 9000** (SSH, RESTCONF, NETCONF),
  **IOS XR** (YANG, model-driven programmability), **Network Services
  Orchestrator**, **SD-WAN 20.18**, and the **ACI Simulator**. The vendor table
  records that no official IOS/NX-OS MCP server exists; that gap now has live,
  credentialed, permanently available gear behind it, which strengthens A4 for
  `cisco.ios` and `cisco.iosxr` and hands A1 targets that needed no sourcing.
- **Meraki is reservable, not always-on, and that reverses the Cisco plan.** The
  Cisco issue was framed around Meraki because Cisco's *hosted* MCP server is a
  Meraki server -- but a reservable sandbox is time-boxed with no stable endpoint,
  which is a poor fit for a server running continuously in a cluster. **Catalyst
  Center is the only target pairing an official MCP server with an always-on
  endpoint**, so it now leads. The order inside the Cisco issue is DevNet Content
  Search (no target at all), then Catalyst Center, then Meraki.
- Also catalogued as reservable: **Cisco Modeling Labs** (full API -- the concrete
  option for B4's in-cluster simulation), **IOS XE on Cat8kv**, **XRd**
  (containerized IOS-XR), **Identity Services Engine 3.4** -- which explicitly
  advertises "ISE ansible modules" -- **NSOLAB**, Nexus Dashboard, and a **CI/CD
  pipeline** sandbox bundling GitLab, Ansible, pyATS, CML and Open NX-OS. ISE
  advertising Ansible modules, and a sandbox shipping Ansible and pyATS
  preinstalled, are evidence Cisco already expects this audience.
- **Cisco is now the only genuinely unblocked vendor** -- vendor-published servers
  *and* a confirmed always-on target -- rather than merely the one with no open
  Decision A.

### Added -- a third use case, and an options brief rather than a design (#94)
- `docs/plan/network-mcp-plan.md` plans MCP servers on OpenShift for AI-assisted
  development of Cisco, Palo Alto and Aruba use cases. **It is deliberately not
  a settled design** -- three decisions are written open for a network SME to
  resolve, which is a departure from the other two plan docs and is called out in
  its Context. The implementation issues are deliberately unopened: Decisions A
  and B change what the Palo Alto and Aruba issues *are*, so opening them now
  would guarantee rewriting them.
- **The premise did not survive the research.** "Use vendor-supplied MCP servers
  where they exist" holds for Cisco alone, which publishes three. Palo Alto's
  official Cortex MCP server serves XSIAM/Cortex SecOps data, **not PAN-OS** --
  every PAN-OS server is community. Aruba has nothing official at all: its
  `central-mcp-server` is documented on HPE's own developer portal, which makes
  it look sanctioned, and the same page says *"This is **not** an officially
  supported product of HPE."* That disclaimer is quoted verbatim in the plan doc
  rather than paraphrased, because org ownership and portal hosting are not
  support statements.
- **The finding that actually defines the work** is that every server found --
  Cisco's included -- is stdio transport and ships no container image. So this is
  not a deployment exercise; the foundation is containerize → adapt stdio to
  streamable HTTP → Route → authenticate → inject credentials from the vault.
  They are also all read-only already, which means the #93 governance stance
  (read-only MCP, writes through an AAP job template) costs nothing here -- it
  describes what the software does rather than restricting it.
- **`ansible.mcp` runs the opposite direction from its name**, and has been
  syncing into this repo's PAH since #68 (`hub/certified-requirements.yml:37`)
  referenced nowhere else. It gives *playbooks* modules to discover and call
  tools on MCP servers -- Ansible as MCP *client*. It is not a way to expose
  Ansible as MCP, and anything planned on that assumption would have been wrong.
- **The AAP MCP server is Technology Preview on 2.6, not only 2.7**, so #92 is a
  sequencing preference for this work rather than a hard block.
- **One claim was corrected before this shipped.** The first draft said DevNet
  sandboxes were "temporarily offline as of February 2026" and treated Cisco as
  fully unblocked. Checking both sources found they disagree: Cisco's Catalyst
  Center sandbox page still lists an Always-On sandbox with no outage notice,
  while Community threads from February 2026 report the always-on labs pulled for
  maintenance with no restoration date. Documentation being stale and the labs
  being back are equally consistent with that, and no further reading settles it
  -- someone has to sign in and try. B1 is now recorded as a candidate rather
  than a plan, and Cisco's "no open decisions" status is scoped to the server
  side only.
- Adds the `mcp` and `network` labels, backfilling `mcp` onto #92 and #93 so the
  whole body of MCP work is one query.

### Fixed -- skill preflights could never read a vaulted credential (#86)
- Two skills resolved `openshift_api_token` and `aap_password` with an ad-hoc
  `ansible ... -m debug` call. Those live in `env_secrets` in
  `playbooks/group_vars/all/secrets.yml`, and Ansible loads a `group_vars/`
  directory adjacent to the **inventory** or to a **playbook** -- an ad-hoc
  command has no playbook, so the file was never loaded and every lookup died
  with `'env_secrets' is undefined`. The secrets layout is correct and
  deliberate (`CLAUDE.md` -> *Secrets: exactly one mechanism*); the two snippets
  simply never caught up with it.
- **`ocpvirt-setup` reported success on the failure.** `-m debug` prints its
  errors into the same `"msg"` field the snippet scraped, so `$OCP_TOKEN` became
  the string `The task includes an option with an undefined variable..` --
  non-empty, so `test -n` passed and it printed
  `✅ resolved sandbox credentials via vault`. It then failed forty seconds later
  as an `HTTP Error 401` at the CNV check, which the skill's own troubleshooting
  table blames on an expired RHDP token. Hit for real on a minutes-old token
  that was perfectly valid.
- **`sales-demos-first-time` Step 7 could not pass on any machine.** That is the
  step whose own text says *"Do not declare success until this passes."* It read
  all five values in one call, two of them vaulted.
- Both now read each value from where it actually lives: inventory-resolved
  values (`aap_env_name`, `aap_hostname`, `automation_hub_token`) through
  `ansible ... -m debug`, which also proves the `--limit`; vaulted credentials
  through `ansible-vault view | python3`, the pattern `README.md` and
  `pah-sync` already used.
- **The guards now check shape, not just presence** -- `sha256~*` for the token,
  `https://*` for the API URL, and a `CHANGEME` test on the password. Checking
  for a non-empty string is what let an error message pass as a credential.
- Verified by running every changed block verbatim against the live sandbox,
  including the negative cases: a non-existent environment reports
  `pw_set=False token_ok=False`, and the error text that used to pass is now
  rejected.

### Fixed -- the masthead pill now asks AAP which environment it is (#87)
- **Hit for real.** A new RHDP sandbox was provisioned, `connection.yml` was
  updated and the vault refreshed -- the two steps `CLAUDE.md` says a new
  environment takes -- and the masthead showed a grey `UNRECOGNIZED ENV` pill
  next to a correctly badged green `SANDBOX` sign-in page. Nothing errored, and
  no CI job referenced the stale file.
- **The generated hostname map was itself the third place to edit that #54
  claimed it avoided.** Re-running a generator and committing its output is a
  third step, and `aap_hostname` changes on every rotation, so the map had to be
  re-synced every time. That entry's reasoning was wrong; this is the
  correction.
- **`target_env` replaces the hostname.** The hostname is only a *proxy* for the
  environment; `target_env` **is** the environment, and
  `controller_templates.yml` already sets it from `aap_env_name` on
  `Sales Demos - Provision VM` and `Sales Demos - Teardown VMs`. The badge does
  one same-origin `GET /api/controller/v2/job_templates/` and scans for the
  field rather than matching a template by name, so a rename cannot break it.
  `assert_target_environment.yml` already fails a run closed if `target_env` and
  `limit` disagree, so the value cannot drift.
- Measured against the live 2.6 sandbox before writing any of it: the
  name-filtered query returns `count: 1`; `extra_vars` comes back as a
  JSON-encoded **string**, not an object, and is parsed accordingly; the same
  request logged out returns `401`; the AAP document sends **no** CSP header, so
  a content-script fetch is not blocked. No new manifest permissions -- the
  content script already runs on the AAP origin.
- **Signed out is now distinguished from unidentifiable.** A `401`/`403` paints
  nothing, because the sign-in page already carries the badged logo and a grey
  pill contradicting a green one two inches away is worse than none. Every other
  failure still paints the neutral pill. The distinction keys off HTTP status,
  never the URL -- route-sniffing is the coupling this design avoids.
- `envs.json` is deleted. `make-env-badge-config.py` now emits a colours-only
  `colors.json` and reads nothing from `connection.yml`, so rotating an
  environment does not require re-running it. `env_colors.py` stays the single
  source of truth so the sign-in logo and the pill cannot drift apart.
- **CI now verifies the generated file**, which nothing did before -- a
  committed generator output that nothing checks is a copy waiting to drift.
- Two claims in `utilities/aap-env-badge/README.md` are corrected rather than
  quietly dropped: it no longer "reads no AAP data" (it reads one endpoint, and
  still changes nothing), and "it keeps working when RHDP hands you a new
  cluster ID" was **false** when written -- this is what makes it true.

### Changed
- The rendered `/etc/motd` now appears in the ocpvirt demo README (#83), which
  previously said the render script "prints the two login banners" and showed
  neither. Verified byte-identical to what `render-demo-assets.py` emits from
  `motd.j2`. `/etc/issue.net` stays in the talk track, where the contrast beat
  needs both banners shown in order.
- Committed screenshots now render inline in the four docs that only named the
  files (#81): both demo READMEs and both run sheets. The run sheets use
  thumbnails linked to the full image rather than full-width embeds -- they are
  read on a second screen while presenting, and eight full-width screenshots
  turn a scannable checklist into a long scroll. No new or re-captured images.

### Added
- PAH demo screenshots committed to `docs/images/pah-*.png` (#74): the empty
  and populated Repositories views plus all three remote Edit dialogs. Demo
  README updated from "blocked on a token" to "one rehearsal away from Ready."

### Added -- a curated repository, so removal actually works (#70)
- `approved`: a fourth Hub repository with **no remote**, whose contents are
  declared in `hub/approved-collections.yml` and reconciled by
  `playbooks/curate_hub.yml`. Unlike the three mirrors, that reconcile **removes**
  -- delete a line and the collection leaves the repository. Verified: populate
  0 -> 9, idempotent re-run at `add 0, remove 0, changed=0`, and a real removal
  taking it 9 -> 8.
- **This is the repository consumers should point at.** The three synced ones are
  mirrors whose contents Red Hat and the community decide; this one holds what
  was approved, at exactly the declared versions -- `approved` carries one version
  of `ansible.platform` where `rh-certified` carries four.
- **Seeded with the nine collections this repo itself pins**, at exact versions.
  Not arbitrary: it is what makes #69 safe, since AAP would resolve against a
  repository containing precisely what a project sync needs.
- **`ansible.hub` 1.1.0 has no repository-to-repository copy**, so this drives
  Pulp directly with `POST {repo_href}modify/`, carrying `add_content_units` and
  `remove_content_units` in one atomic call. **Deliberately not the `move/`
  endpoint** -- a move takes the collection OUT of the source, so curating into
  `approved` would have silently stripped `rh-certified`. The whole cycle was
  proven on a scratch repository before the playbook was written.
- **The first real run failed, and correctly.** `ansible.platform 2.7.20260604`
  was absent from the hub entirely, sitting below the certified 3-version floor.
  The generator now lowers a floor to any version this repo has pinned, which
  costs two extra versions across the whole hub -- and `--audit-pins` now reports
  "Every pinned collection is inside its window", closing gate 2 of #69.
- Also corrected: this repo pins **nine** collections, not ten, in four files and
  in #69.

### Added -- Private Automation Hub as code, the repo's second use case (#68)
- Every environment now configures its Private Automation Hub on every build.
  `config.yml` applies three collection remotes and repositories and starts a
  sync without waiting, so `setup.yml` stays at roughly ten minutes;
  `playbooks/sync_hub.yml` and the `pah-sync` skill are the blocking entry point
  that waits and then verifies. Content: all Red Hat certified (214) and
  validated (47) collections windowed to the 3 newest versions of each, plus 15
  curated community collections at their current version only.
- **Pulp has no "keep N versions" control, and `retain_repo_versions` is not
  it** -- that prunes repository snapshots, not collection versions. A
  requirements entry of a bare `namespace.name` syncs every version ever
  published, and some certified collections have forty. So
  `utilities/refresh-hub-requirements.py` computes a `>=` floor per collection
  and writes `hub/{certified,validated,community}-requirements.yml`, all
  committed. That generated diff is the reviewable artifact the whole use case
  exists to produce.
- **`hub/` is deliberately not `collections/`.** `collections/requirements.yml`
  is what a laptop and the execution environment INSTALL; `hub/*.yml` is what PAH
  SYNCS from upstream. Different direction, different lifecycle, and confusing
  the two is the likeliest mistake here -- every generated file says so in its
  header.
- **A refresh is a script, not a playbook**, matching `utilities/build-ee.sh`:
  it writes into the repo checkout so it must never run from AAP, and it is ~260
  HTTP calls, which as sequential `uri` tasks would take minutes and produce
  output nobody can read. Concurrent, stdlib-only: 25 seconds for all three
  lists.
- **The three-token table is the deliverable, not a footnote.** `ansible.hub` and
  `ansible-galaxy` call three unrelated credentials "token", and this is where
  people stall on day one. The Red Hat *offline* token syncs your hub FROM Red
  Hat and lives in `~/.ansible.cfg`; your hub's own API token authenticates
  clients TO it and is not stored at all; a galaxy.ansible.com token is only
  needed to publish and is not needed here. Written out in
  `docs/demos/private-automation-hub/architecture.md`.
- **`sales.demos` now has six-file demo documentation for one use case.**
  `clickops.md` holds the full click-by-click UI walkthrough, because the demo's
  argument is a contrast with doing it by hand and that procedure has to be real
  rather than a strawman -- and thirty clicks would have destroyed the run
  sheet's one job, being scannable by someone standing up mid-sentence.
- Deliberately **not** done: no organization Galaxy credential, so nothing in AAP
  resolves from the hub yet. That is #69, held behind gates, because a Galaxy
  credential makes every project sync depend on the hub being complete. It is
  already known to be incomplete -- `--audit-pins` reports that
  `ansible.controller` and `ansible.platform` are pinned below their version
  window. Found by writing the check, not by having it fail in a demo.

### Fixed -- three failure modes found by running the sync for real (#68)
- **A Pulp sync is additive and the docs now say so.** Dropping a collection from
  `hub/community-requirements.yml` and re-syncing left all 15 in the repository.
  The requirements files are an allowlist for what gets pulled IN, not a
  declaration of desired state: adding works, changing a version keeps the old
  one, removing does nothing. `ansible.hub` POSTs to `{repo}/sync/` with no body,
  so no `mirror` flag is sent and Pulp defaults to additive. Same root cause as
  the `>=` floor only widening. The honest answer -- a curated repository you
  create and copy approved versions into, which is a list you can genuinely
  remove from -- is tracked in #70 rather than claimed here.
- **`sync_dependencies` is now false on every remote.** It was true for certified
  on the reasoning that certified collections only depend on each other, so the
  dependency walk could not escape the curated set. Wrong: the first real sync
  died on `404 .../collections/index/containers/podman/`, a collection in
  neither generated list, pulled in by something that depends on it and absent
  from console's `published` repo. **One unresolvable dependency fails the entire
  sync task**, so the repository stays empty rather than partially filled.
- **The `infra.aap_configuration` async defaults are far too short for a sync,
  and misreport the failure.** Every role wraps its work in `async:` and polls
  with `collect_async_status`; the defaults are 50 retries one second apart --
  about fifty seconds. A certified sync runs for minutes, not seconds. Left
  alone the playbook fails with `attempts: 50` and, because secure logging is on,
  a `censored` message that says nothing, while the sync runs happily inside
  Pulp. Confirmed by querying `/pulp/api/v3/tasks/` directly: state `running`,
  not `failed`. `sync_hub.yml` sets 360 retries at 15s, and narrows secure
  logging off for the sync role alone -- it carries repository names and no
  credentials, unlike the remote role, which keeps it.
- **A trailing newline made every remote report `changed`, forever.** Pulp stores
  a remote's `requirements_file` with the trailing newline stripped, so a
  generated file that has one differs by exactly that character on every
  comparison and the module rewrites the remote each run. The sync worked and the
  run was green -- it simply never reported `changed=0`, which is the precise
  claim the config-as-code demo makes. Fixed with an `rstrip` in the generator
  and a per-rule `.yamllint` exemption scoped to `hub/`; nothing else in the repo
  is exempt, and both places carry the reason so nobody tidies the newline back.
- **Two remotes still report `changed` and always will**, which the talk track
  now addresses head-on rather than hoping nobody reads the recap.
  `rh-certified` and `validated` carry a token the API never returns, so the
  module has nothing to compare against; `community`, with no credential, reports
  `changed=0`. Same behaviour `controller_settings.yml` documents for
  `SUBSCRIPTIONS_CLIENT_SECRET` -- the platform refusing to hand back a secret,
  not drift.
- **`validate.yml` would have kicked three live PAH syncs**, while printing
  "Nothing will be changed." `ansible.hub` 1.1.0's `collection_repository_sync`
  reads `module.params.get("check_mode")`, but `check_mode` is not in its
  argument_spec -- so it is always `None`, the guarded early-exit never fires,
  and the sync runs for real under check mode. It should be `module.check_mode`.
  Guarded in two places because one is not enough: the group_vars `sync:`
  expression carries `not ansible_check_mode`, and `validate.yml` forces
  `hub_sync_enabled: false`. **`ansible_check_mode` is only True for a CLI
  `--check`** -- a play-level `check_mode: true`, which is exactly what
  `validate.yml` uses, leaves it False. Verified both ways, and verified by
  counting Pulp sync tasks either side of a validate run.
- **Check mode cannot validate content, and said so confusingly.** `uri` does not
  run under `--check`, so registered results come back as bare skip markers with
  no `json` key and the first assertion dies on a missing attribute rather than
  reporting anything about the hub. The verification block is now gated on `not
  ansible_check_mode`. A related trap: **Ansible templates a `loop_control.label`
  even for items the `when` skips**, so a label reaching into a skipped result
  fails the task with an error unrelated to the assertion -- labels now reference
  `item.item` only.

### Fixed -- generic sibling-repo references in code comments (#65)
- Three comments cited sibling repositories by directory name as precedent. One
  of those names identified an external organisation, which this repo's own rule
  does not allow in a tracked file. Replaced with "a sibling daily-demo repo",
  which carries the same weight as evidence without naming anyone;
  `inventory/group_vars/aap/controller_templates.yml`, `playbooks/provision_vm.yml`
  and `terraform/ocpvirt/backend.tf`. Non-identifying references (`dc1.azure`)
  are unchanged.
- **The comments themselves were kept.** They record why a pattern was chosen
  and where else it was verified, which is the kind of note that saves someone
  an afternoon. Only the identifying token needed to go.
- Found by a full history audit -- every blob in the object store, every commit
  message, every ref. Everything else came back clean: no private keys, AWS
  keys, GitHub or Slack tokens at any revision; every committed `secrets.yml`
  vault-encrypted at every revision; no non-Red Hat email addresses; no routable
  IPs.
- **No history rewrite.** The name is also in one historical commit message, and
  rewriting 82 commits would change every downstream SHA, break existing PR and
  issue cross-references, and still not remove it from GitHub -- which serves
  unreachable commits by SHA long after they leave every branch. Verified
  directly: two commits reachable from no local ref still resolve through the
  GitHub commits API. Real removal needs the rewrite plus a Support request, and
  that is not worth it for a directory name in a comment.

### Added -- stage the docs for NotebookLM (#64)
- `utilities/collect-notebooklm-sources.sh` and its manifest
  `utilities/notebooklm-sources.txt`. NotebookLM takes files rather than
  repositories and answers only from what it is given, so the corpus is an
  explicit allowlist and this script turns that list into `build/notebooklm/`,
  ready to drag into a browser. `build/` is gitignored -- every staged file is
  a copy of a tracked one.
- **The manifest is an allowlist and never globs.** No directory is walked, so
  a repo holding customer material cannot be swept into a Google product by a
  pattern that was slightly too wide. Each source is a line someone wrote.
- **Files are renamed on copy** to `<repo>--<flattened-path>.md`. Filenames are
  the only handle NotebookLM shows in its source list and in every citation,
  and several repos' worth of `README.md` would be indistinguishable at exactly
  the moment you want to know where an answer came from.
- **The staged bundle is grepped before it is declared ready**, using the same
  real-value patterns as `check-no-secrets.sh`, and the copies are deleted if
  anything matches. Placeholders (`sha256~CHANGEME`, `cluster-<id>.dyn...`) do
  not trip it; a genuine token does, and then there is no bundle left to upload.
- The corpus starts at this repo only, and deliberately includes
  `docs/plan/ocpvirt-demo-plan.md` and `CLAUDE.md`: the notebook's first job is
  working out what gets refactored into `sales.demos` over time, and that
  judgement needs the design rationale and the conventions, not just the docs.

### Added -- a real demo page, and the restart-503 (#60)
- `demo-page-live.png` -- the demo page **served by an actual guest**, not
  rendered. RHEL 9.8, `large-2cpu-6gb` resolving to `sd1.large`, 5642 MB, and
  `KVM (guest)` coming out right in production rather than only against the
  fixture. The cold open uses it now; `demo-page.png` stays as the regenerable
  offline fallback and as what the render script verifies. Both are honest about
  which they are.
- **The `Configured` timestamp on that page predates the capture by 14 minutes**,
  which is itself the proof that the page survived a VM restart on the
  persistent disk.

### Fixed -- two recovery moves that were learned the hard way (#60)
- **A 503 with the VM reporting `Running` usually means the guest is still
  booting.** Observed live: the VMI was re-created, and the route 503'd for
  about two minutes before the guest finished coming up. It **self-healed** --
  the disk is persistent and `linux_configure` sets httpd `enabled`, so the web
  server returned with no intervention. A presenter who hits this would
  otherwise start debugging something that is about to fix itself, so the run
  sheet now says to wait and narrate it as the "three definitions of done" beat.
- **A connection *timeout* is never a Route or cluster fault.** The router
  answers a bad route with an instant 503; a timeout means the TCP connection
  never established, which puts the problem on the local network path -- VPN,
  proxy, wifi. This distinction cost real time to establish and is now in the
  recovery table, along with the check that settles it: whether the AAP or
  console tab also hangs.

### Added -- live screenshots wired into the talk track (#58)
- Six images captured from a real run, filling the gap `render-demo-assets.py`
  cannot: `aap-survey.png`, `aap-workflow-running.png`, `ocp-vms-before.png`,
  `ocp-vms-after.png`, `route-503.png`, `aap-login-badged.png`. The AAP and
  OpenShift interfaces cannot be rendered from templates, so #56 shipped a
  Mermaid graph and a checklist; this is that checklist cashed in.
- **The before/after namespace pair is the strongest of them**, and it was not
  on the requested list. Empty project, then one VM `Running` at the tier that
  was asked for, gives Beat 4 a visual spine it did not have.
- **`route-503.png` shows the Route live and correctly serving nothing.** In a
  browser this lands harder than `curl -sI` output — the hostname is on screen,
  and it encodes the whole story: VM name carrying the requested tier, the
  `-web` Service, the namespace.
- **`LiveMigratable=True` is visible in the namespace screenshot, and the talk
  track says there is no live migration.** Both are true and the tension is
  real: the condition means the VM is *eligible* to migrate — shared storage,
  nothing pinning it to a host — it simply has nowhere to go on a single node.
  A sysadmin reading that Conditions column will call it out, so `objections.md`
  now carries the precise answer rather than leaving it to be improvised.
- **The shots come from several different launches at different tiers** —
  `small` in the survey, `medium` in the 503, `large` in the namespace shot. The
  use-case README says so outright. They illustrate the mechanism; claiming they
  were one continuous run would be the kind of small dishonesty this repo's
  documentation does not do.
- **`aap-job-timings.png` turns the timing table from estimate into evidence.**
  One real workflow run, node by node: provision 36 s, register 4 m 25 s,
  configure 3 m 49 s, check 5 s, **9 m 9 s** total. The "about nine minutes"
  figure the docs have carried in four places is confirmed, and the shape behind
  it is now visible — **90% of the run is register plus configure**, attaching
  to the CDN and then pulling packages over it. The machine itself exists in
  under 40 seconds.
- **The 36-second provision job sharpens the "three definitions of done" beat
  into four.** The provision node reports Success while the guest is still
  booting: a green checkmark is not a usable server, which is exactly why
  `register_vm.yml` opens with `wait_for_connection` and why register's 4 m 25 s
  includes a stretch spent waiting on a machine the previous job already called
  done.
- Both the talk track and the run sheet now say to put the job list **on
  screen** rather than assert a duration. Durations in a controller's own job
  list are evidence; a presenter's estimate is not.
- `route-503.png` was cropped to drop a visible bookmarks bar. The run sheet now
  says to hide it before shooting.
- The run sheet's screenshot checklist is now split into captured and
  outstanding, the highest-value remaining shot being the 200 half of
  `route-503.png` in the same browser frame.

### Added -- documentation you can present from (#56)
- `docs/demos/`, a talk-track tree with one directory per use case. The first is
  `openshift-virtualization/`, ready to present in a 30-minute slot. Everything
  written down until now — `README.md`, the plan doc, the eight `SKILL.md`
  files — is written for the person **building** the automation. Nothing was
  written for the person **showing** it.
- **Five documents per use case, and the split is the point.** `run-sheet.md` is
  the live layer: minute markers, what is on screen, exact commands, recovery
  moves, scannable by someone standing up with an audience waiting.
  `talk-track.md` is the rehearsal layer: prose, the actual words, why each beat
  exists. Then `architecture.md`, `objections.md`, and a `README.md` entry
  point. One document trying to do the first two jobs is too long to present
  from and too terse to learn from.
- **It works with no cluster**, which was the requirement that shaped
  everything else. A demo environment expires, a slot moves, a colleague reads
  it on a plane.
- `utilities/render-demo-assets.py` is what makes that possible. Two of the
  three things a customer actually looks at are Jinja templates in
  `linux_configure/templates/`, so they render on a laptop with nothing
  running: it renders `index.html.j2` against a representative fixture,
  screenshots it with headless Chrome to `docs/images/demo-page.png`, and prints
  `motd.j2`, `issue.j2` and `facts.json` as text for the talk track. Same
  convention as `make-env-logo.py` — a generated image committed under
  `docs/images/` beside the script that regenerates it.
- **The screenshot is rendered, not photographed**, and the script header, the
  image caption and the use-case README all say so. It is accurate — the guest
  serves that exact template — but it is not a capture of a live run, and a
  public repo should not imply otherwise.
- **`trim_blocks=True` is not optional in that script.** Ansible defaults it
  True and Jinja defaults it False, so with Jinja's default the newline after
  every `{% for %}` survives and `motd.j2`'s "Powered by" list renders with a
  blank line between each credit, tearing the boxed banner apart.
- **The fixture keeps `ansible_virtualization_type: "NA"` deliberately.** That
  is what a KubeVirt guest genuinely reports, and it is why `index.html.j2`
  cannot use `| default()` — "NA" is defined, so the default never fires. Using
  the real value means the committed PNG exercises that branch instead of
  hiding it.
- **The logos must be staged beside the rendered HTML.** `index.html.j2`
  references `logos/rhel.svg` relatively; render the file alone and the
  screenshot shows three broken-image boxes where the product marks belong. The
  script copies the directory into the temp dir, and the verification step is to
  open the PNG and look.
- **The AAP UI cannot be rendered**, so the workflow is a Mermaid graph and the
  survey a table — arguably better than screenshots for a talk track, since both
  survive dark mode and a gateway upgrade. The run sheet ends with a checklist
  of screenshots worth capturing next time an environment is up.
- `docs/demos/_template/` was extracted from the finished use case rather than
  authored ahead of it, so it carries the shape that actually worked. Private
  Automation Hub (ClickOps vs. configuration-as-code) is a named row in the
  index with no stub directory — an empty folder is worse than a line in a
  table.
- `docs/plan/` is untouched: it answers *why the automation is built this way*,
  `docs/demos/` answers *how to show it*. Different readers, different
  lifecycles.

### Added -- the environment is now marked AFTER login too (#54)
- `utilities/aap-env-badge/`, an unpacked MV3 Chrome extension painting a
  `SANDBOX` / `DEMO` pill in the middle of the AAP masthead. The sign-in logo
  from `make-env-logo.py` marks the environment you are *entering*; it
  disappears the moment you log in, which is when you start clicking things.
- **No gateway setting can do this, and that is now measured rather than
  assumed.** On the live 2.6 gateway, `/api/gateway/v1/settings/all/` returns 44
  settings and only `custom_login_info` and `custom_logo` are branding-related
  — and `custom_logo` was *already applied* (26 KB of base64 PNG) while the
  masthead still rendered the stock lockup. Anything further server-side means
  patching a bundled asset in the gateway container, which the operator
  reconciles away. So: browser-side, and it touches nothing on the cluster.
- **An overlay, not DOM surgery.** One `position: fixed` element appended to
  `<body>`; AAP's own markup is never modified. The masthead is PatternFly with
  version-prefixed class names, so anchoring inside it would break on a gateway
  upgrade. All it depends on is a `<header>` existing.
- **An unrecognized RHDP AAP host gets a neutral `UNRECOGNIZED ENV` pill.** Not
  a fallback — a freshly built environment nobody has recorded yet is exactly
  when you are most likely to act on the wrong cluster.
- `envs.json` is generated from `aap_hostname` in each
  `group_vars/<env>/connection.yml` by `utilities/make-env-badge-config.py`, so
  a new RHDP environment does not become a third place to edit. A stale
  hand-maintained map would not error; it would label the wrong cluster with the
  right colour, which is the exact mistake the badge exists to prevent.
- `utilities/env_colors.py` — the colour convention lifted out of
  `make-env-logo.py` now that two things paint an environment marker. The
  sign-in logo and the masthead pill cannot drift apart. Kept dependency-free:
  the badge generator needs neither Pillow nor ImageMagick.
- The three places stating the environment could not be marked post-login are
  corrected to say what is actually true — no *setting* can, and here is what
  does.

### Fixed -- a stale Terraform state lock now says how to clear it (#46)
- Hit for real: a `Sales Demos - Provision VM` job was cancelled mid-apply, and
  every run afterwards failed with `Error acquiring the state lock`. The
  kubernetes backend releases its lock when terraform exits, and a job that is
  cancelled, times out, or has its pod evicted never gets there — so the lock
  outlives the run that took it.
- `playbooks/tasks/terraform_lock_check.yml`, shared by `provision_vm.yml`
  (apply) and `teardown.yml` (destroy). On a failure that names a lock it fails
  with the **lock ID, the holder, and the exact `force-unlock` command**, and
  states plainly that nothing was changed — the lock is taken before any work
  starts. Any other failure falls straight through to the existing message.
- **`Who:` is misleading in AAP and the message says so.** It shows a pod name
  like `1000770000@automation-job-92-qswfk`, which reads as a run in progress.
  That pod is gone; waiting never clears it.
- The backend locks with a Kubernetes **Lease**
  (`lock-tfstate-default-<env>` in `sales-demos-tfstate`), so whether a lock is
  actually held can be checked with `oc` and no terraform at all — an empty
  `.spec.holderIdentity` means the failure is something else. Both the failure
  message and the skill give that command, because it is current where `Who:`
  is a fossil.
- **Nothing force-unlocks automatically, deliberately.** A stale lock is a rare
  recoverable annoyance; force-unlocking a live apply is a rare *unrecoverable*
  one. Doing it safely would need a liveness check against the AAP job, not the
  pod name in the error. Do not "improve" this into an automatic unlock.
- Troubleshooting entries added to the `ocpvirt-provision` and
  `ocpvirt-teardown` skills. Teardown is the likelier victim: the nightly
  schedule can start while a manual job is still running.

### Fixed -- laptop access details were wrong, and invisible (#49)
- **The `ssh_command` output emitted a flag that no longer exists.** It built
  `virtctl ssh -n <ns> --local-ssh <user>@<vm>`; virtctl v1.x removed its
  built-in SSH client, so local ssh became the only mode and `--local-ssh` was
  **deleted rather than defaulted**. The output failed with `unknown flag:
  --local-ssh` before connecting. It also omitted the `vm/` resource prefix
  virtctl needs to tell a VM from a VMI. Verified working on virtctl v1.6.6:
  `virtctl ssh -n <ns> <user>@vm/<vm-name>`. `-t/--local-ssh-opts` is the
  surviving way to pass ssh options.
- **The job that produces the demo URL did not print it.** `web_url` appeared
  only in the Provision log, tagged "503 until Phase 4 installs httpd" — while
  `Configure VMs` / `Run Demo`, the job that *makes* it return 200, said only
  "Public URL comes from the terraform output `web_url`". `Check VMs` never
  mentioned a URL at all. All three now print the live URL and the laptop
  `virtctl` line.
- `web_url` and `ssh_command` are registered as **AAP host variables** by
  `provision_vm.yml`. They cannot be recomputed downstream:
  `configure_vm.yml` and `check_vm.yml` target `linuxweb`, a group created at
  run time, while `ocpvirt_namespace` and `openshift_apps_domain` live in
  `group_vars/<env>/connection.yml` and load only for the `sandbox-local` /
  `demo-local` hosts in the `aap` group. `set_stats` does not reach them
  either — it feeds workflow nodes, not a job re-run on its own. Neither value
  is a secret. Guests provisioned before this fall back to the terraform
  outputs rather than failing on an undefined variable.

### Added -- login banners on the demo guests (#50)
- **Two different messages, for two different moments.**
  `templates/issue.j2` is the legal authorized-use notice, rendered to
  `/etc/issue` (console) and `/etc/issue.net` (network, via sshd's `Banner`) and
  shown *before* anyone has proved who they are — no branding, no product
  story, no demo URL. `templates/motd.j2` is the branded ASCII art, rendered to
  `/etc/motd` and shown *after* authentication. `virtctl ssh` used to land on a
  bare prompt for both. This reverses the #5 port decision below: that dropped
  the MOTD/issue/banner set alongside two bundled images to keep personal
  assets out of a public repo, which is an argument about images, not text.
- The art says **what this demo actually is** — Red Hat OpenShift
  Virtualization — rather than naming a different demo story.
- **The pre-authentication half touches sshd, so it is deliberately careful.**
  sshd is how AAP reaches every one of these guests — including the connection
  running the play itself. So: a drop-in at
  `/etc/ssh/sshd_config.d/99-sales-demos-banner.conf` rather than an edit to
  `sshd_config`; `validate: sshd -t` on the candidate file, so a config the
  daemon would reject fails the task instead of reaching it; and a **reload,
  never a restart**. If `sshd_config` has no `Include` line the drop-in would be
  silently ignored, so the role checks and skips with a warning rather than
  editing `sshd_config` directly. `linux_configure_ssh_banner: false` opts out.
- **Both `/etc/issue` and `/etc/issue.net`.** They are not interchangeable —
  getty prints the first on the console, sshd sends the second over the
  network. Writing only one leaves a login path with no notice on it.
- `/etc/motd` rather than `/etc/motd.d/` — `pam_motd` on RHEL 9 reads both, but
  `/etc/motd` needs no assumption about the guest's PAM stack. No `cowsay`
  package: the cow is static text in the template.
- The tagline and the "Powered by" block live in `defaults/main.yml` as data, so
  another demo story can swap them with `-e`. They are padded to the box width
  by the template's `format` filter, so an override cannot knock the right
  border out of alignment. **They name what this demo actually runs** —
  OpenShift Virtualization, Terraform, AAP, Insights — because a login banner
  reads as a claim to a technical audience.
- `linux_configure_banner_owner` names the system's owner in the legal notice.
  The wording is conventional boilerplate, not legal advice; replace
  `templates/issue.j2` outright if there is approved text to use instead.
- The demo URL is printed *below* the box, not inside it: a Route hostname runs
  to roughly 84 characters and would tear the border apart. It comes from the
  `web_url` host variable (#49), and is simply absent on a guest provisioned
  before that.
- `linux_configure_motd: true` turns the whole thing off.

### Added -- Phase 4: the demo itself (#5)
- `playbooks/run_demo.yml` with `playbooks/roles/linux_register` and
  `playbooks/roles/linux_configure`, the `ocpvirt-demo` skill, and a
  `Sales Demos - Run Demo` job template. **Verified from AAP: the demo URL went
  from `503 Service Unavailable` to `200 OK`**, serving a page built from the
  guest's own facts (`sd1.small`, 1 vCPU, 1620 MB). That closes the loop #29
  opened — the Route existed from provisioning and had nothing behind it.
- **Registration is the first step, not an afterthought.** The CNV `rhel9`
  image ships with no repositories and no subscription: `dnf repolist` reports
  none and `dnf install` fails outright, so every demo story — webserver,
  patching, compliance — is dead on arrival. It is invisible until you try,
  because the VM boots and answers SSH perfectly. `linux_register` uses the
  certified `redhat.rhel_system_roles.rhc` role and then **verifies
  repositories actually appeared**, since registration can succeed while no
  entitlement matched and the resulting `dnf` failure points nowhere near the
  cause.
- `rhsm_org_id` and `rhsm_activation_key` added to the vault. The org ID is
  there too, bending the file's "credentials only" rule: the only global
  plaintext file is committed to a public repo and an org ID identifies a Red
  Hat account, so splitting one logical pair across two files would be worse.
- Ported from `dc1.azure` and trimmed — the MOTD/issue/SSH banner set and the
  two bundled images (a Red Hat logo and a personal QR code) are dropped rather
  than carry personal assets into a public repo. The page is **self-contained**:
  no external images, fonts or CDN, because it is served from a cluster whose
  egress you do not control, in front of a customer. *(The MOTD came back in
  #50 — the personal-assets argument was about the images, not the text.)*
- **Reboot-after-patching is off by default**, unlike `dc1.azure`. A reboot
  mid-demo takes the page away with someone watching, and these VMs are rebuilt
  nightly anyway. `-e linux_configure_reboot=true` when patching *is* the demo.
- Firewalld inside the guest is opened explicitly. It is separate from anything
  OpenShift does, and without it the Route still returns 503 with httpd running
  perfectly.

### Fixed -- three layout assumptions this exposed (#5)
- **Roles must live playbook-adjacent.** Ansible resolves roles relative to the
  playbook directory, so `playbooks/roles/` is searched and repo-root `roles/`
  is not — and it cannot be added to the search path without a project-local
  `ansible.cfg`, which this repo forbids. The root `roles/.gitkeep` from the
  original skeleton was aspirational and is removed rather than left to mislead.
- **The secrets file moved from `group_vars/aap/` to `group_vars/all/`.**
  `aap` scopes it to hosts in that group; every playbook until now targeted
  `hosts: aap`, which made it indistinguishable from `all`. `run_demo.yml` is
  the first to target the VMs, and they never received the vars — failing an
  assert that blamed a missing Vault credential which *was* attached. This is
  the file's third location today, so the reasoning now lives beside it:
  `inventory/` broke the AAP inventory sync (#4), `aap/` misses VM-targeted
  plays.
- `.ansible-lint` — mock `ansible.posix.firewalld` and the
  `redhat.rhel_system_roles.rhc` role. CI lints offline, and this is the second
  time that gap has only surfaced there. `ANSIBLE_COLLECTIONS_PATH` does **not**
  reliably reproduce it; cross-checking every FQCN in `playbooks/` against the
  mock lists does. Also fixed a duplicate `mock_roles:` key that silently
  dropped the new entry.

### Added -- the ocpvirt-provision skill that #4 never shipped (#42)
- `.claude/skills/ocpvirt-provision/` — #4 named it as a deliverable and shipped
  the playbook and job template without it. `README.md` listed it as Done, so the
  gap was invisible. That broke the contract in `CLAUDE.md`: *"Every phase is
  runnable as a skill and as an AAP job template."* Phase 3 had one entry point.
- `.github/workflows/lint.yml` — the skills gate is now **bidirectional**. It
  checked that every skill appears in the README, but not that every skill named
  in the README exists, which is exactly how this slipped through green CI. A row
  may name a missing skill only if explicitly marked "Not started".

### Fixed -- contributor docs contradicted the repo's actual rules (#42)
- `.github/SECURITY.md` and `.github/PULL_REQUEST_TEMPLATE.md` both told
  contributors to put environment-specific values in a *gitignored* `secrets.yml`
  rather than `connection.yml` — the reverse of the truth since #18 — and to
  replace RHDP URLs with placeholders, which contradicts `CLAUDE.md`, where they
  are **the documented exception** and committed on purpose. Anyone following
  either would have broken both environments, and `check-no-secrets.sh`
  deliberately does not flag RHDP hostnames, so CI would have stayed green.
  SECURITY.md now states where each class of value lives and why the secrets file
  is tracked rather than ignored.
- `inventory/group_vars/aap/aap_settings.yml` — header still described the
  pre-#18 model, including the claim that hostnames live in the secrets file.
- `CLAUDE.md` — one leftover "gitignored `secrets.yml`" phrase.

### Changed -- docs caught up with two live environments (#42)
- `ROADMAP.md` — gains a status column and the `ocpvirt-new-env` row it never
  had. It previously read as entirely unbuilt.
- `docs/plan/ocpvirt-demo-plan.md` — "Tonight's scope" and "Implementation plan
  (tomorrow)" are marked **historical**, pointing at `ROADMAP.md` for status.
  The quay namespace open item is resolved (`quay.io/zigfreed`), leaving only the
  private repository Phase 2 still needs.
- `.claude/skills/sales-demos-first-time/` — added the command-line tools the
  playbooks shell out to. It covered collections and the python client but not
  `terraform`, `virtctl`, `podman` or `ansible-builder`, so a new machine could
  complete every step and still not provision a VM.
- `.claude/skills/collections-sync/` — **a pin change is not finished until the
  EE is rebuilt.** `collections/requirements.yml` feeds both the laptop and the
  execution environment; bumping a pin without rebuilding makes the two resolve
  different code, which is the drift the pins exist to prevent, and nothing
  detects it because both halves are internally consistent.

### Changed -- setup.yml is now the one-command path (#1)
- `playbooks/setup.yml` imports three stages in order: `install_cnv.yml`,
  `config.yml`, `prepare_env.yml`. A bare RHDP environment becomes demo-ready in
  one command, which is what #1 asked for — CNV installed, AAP configured, and a
  real VM built and timed to prove it. **Roughly 10 minutes**, on top of RHDP
  provisioning the environment itself.
- Each stage stays runnable on its own. `setup.yml` is a convenience, not a
  bottleneck: `install_cnv.yml` when only a cluster needs CNV, `config.yml` when
  only AAP objects changed, `prepare_env.yml` to re-check an idle environment.
- **The AAP half is config-as-code rather than a ported bootstrap path.** #1
  described porting one from `aap.as.code` and flagged the cost itself: "the
  bootstrap step duplicates logic aap-skills/aap.as.code already owns and can
  drift." Applying `inventory/group_vars/aap/*.yml` through the dispatch role
  avoids that second copy and is idempotent — re-running converges rather than
  re-bootstraps.
- **Automation Hub credentials are deliberately not created**, closing #1's
  remaining bullet as obsolete rather than unbuilt. AAP would use them to install
  `collections/requirements.yml` at project sync, and the execution environment
  already carries every pinned collection (#31). Verified on the live sandbox: no
  organization has a Galaxy credential, the sync's collection play reports
  `ok=3, changed=0`, and job templates run green regardless. Adding one would only
  make every sync re-install what is already baked in.

### Fixed -- prepare_env no longer waits 15 minutes to report a 44s answer (#39)
- `playbooks/prepare_env.yml` — the smoke-namespace cleanup ran with
  `wait: true` and dominated the whole playbook. Measured across two live
  environments, an identical 44s/45s build produced a total runtime of ~2.3 min
  on a warm cluster and **~17.5 min on a fresh one**, because deleting the
  namespace blocks on DataVolume and PVC teardown, which on a freshly installed
  cluster contends with the CSI clone still materializing underneath. The
  playbook was slowest on exactly the environment where the answer matters most.
  Now `wait: false` — **42s total on the environment that previously took
  17m29s**, a 25× reduction with the same verdict. The namespace still goes
  away; it was observed gone within a minute, unattended.

### Changed -- the real end-to-end timings are written down (#39)
- The docs quoted "5m47s cold, ~30s warm" for a VM build, but never said how
  long a fresh RHDP environment takes to become demo-ready. Now stated in
  `README.md` and the `ocpvirt-new-env` skill: **~4 min to install CNV, ~2 min
  to verify, and roughly 20 minutes end to end from a bare RHDP environment** —
  most of which is the environment provisioning itself.
- Two corrections recorded rather than quietly dropped:
  - **The 5m47s cold build did not reproduce.** A brand-new environment built in
    44s, the same as a day-old one: all six boot-source VolumeSnapshots were
    `readyToUse` before CNV finished installing, because the import runs
    alongside the install. The original figure most likely came from building
    immediately after install and catching the import mid-flight.
  - **The CNV install is ~4 minutes**, not the ~15 stated while #30 was in
    progress — that was inferred from a background task's apparent runtime
    rather than measured.

### Added -- fresh-environment readiness (#30)
- `playbooks/prepare_env.yml` and the `ocpvirt-new-env` skill. Answers one
  question — would a live VM build in front of a customer be fast? Measured on
  the sandbox: **5m47s cold versus ~30s warm**, and that gap is not Terraform's
  doing. The module is already on the fast path; the slow case is building
  against a cluster whose boot source has not finished importing, so the fix
  belongs in environment spin-up rather than the VM definition.
- **It asserts rather than assumes**, because every check corresponds to a way
  an environment looks fine and is still slow:
  - The `rhel9` DataSource can report `Ready` while the **VolumeSnapshot behind
    it** is still materializing — the actual slow-build state. The snapshot is
    resolved from `spec.source` by name and checked for `readyToUse`, rather
    than inferred from the DataSource condition. Handles the PVC form too.
  - A StorageProfile reporting `copy` instead of `csi-clone` makes every create
    pay a full disk copy, which no amount of pre-warming fixes. On RHDP the
    default StorageClass must be the ceph-rbd one; **noobaa reports `copy`**.
  - The IngressController must actually be Available, or the Routes giving demo
    VMs their web URL (#29) are never admitted. A mismatch between
    `openshift_apps_domain` and the cluster's real domain warns rather than
    fails — a stale value produces URLs that resolve nowhere.
- **And it builds a real VM**, times it, and destroys it. A playbook that has
  verified everything except "can this cluster make a VM" is the failure mode it
  exists to prevent. The smoke VM lives in its own namespace, removed in an
  `always:` block so a slow or failed run leaves nothing eating the memory
  budget. It uses Red Hat's `u1.small` rather than the repo's `sd1.*` types,
  which do not exist until `terraform/ocpvirt` has run — and this playbook is
  for clusters where it has not.
- `playbooks/tasks/resolve_storage_class.yml` — the StorageClass discovery
  extracted out of `install_cnv.yml` so both use one definition rather than two
  that drift, the same reasoning that extracted `assert_target_environment.yml`
  in #24.

### Changed -- documentation caught up with the code (#30)
- `ROADMAP.md` — the sizing table still listed `u1.small` / `u1.medium` /
  `u1.large`. #2 moved to repo-owned `sd1.*` types because `u1.*` has no 6 GiB
  size: at `u1.large`'s 8 GiB, `os_type=both` needs ~16.6 GiB against the
  ~14.2 GiB actually free once AAP and CNV are running, so it would never
  schedule. Also notes that the real ceiling is enforced in `locals.tf` at plan
  time, not by the table.
- `docs/plan/ocpvirt-demo-plan.md` — the state backend said "local state
  initially; optionally the NooBaa S3 endpoint later", which #4 found
  unworkable. Now records the `kubernetes` backend and why state lives in its
  own long-lived namespace.
- `inventory/group_vars/demo/connection.yml` — the `demo` environment is live
  rather than placeholders, so #16's environment isolation is now load-bearing
  instead of theoretical: `--limit demo` and `--limit sandbox` reach two
  different clusters.

### Changed -- the EE is pulled from Private Automation Hub (#35)
- `inventory/group_vars/aap/hub_ee_registries.yml` and
  `hub_ee_repositories.yml` — PAH mirrors `quay.io/zigfreed/sales-demos-ee` into
  a local `sales_demos_ee` repository, and Controller pulls the local copy.
  quay stays the published artifact and the source of truth; this removes
  quay.io from the demo's *runtime* dependencies and makes the pull
  cluster-local rather than an internet round trip.
- **The sync has two gates and needs both**, which is invisible if you only read
  one file: the repository item must carry `sync: true`, *and* a variable named
  `hub_ee_repository_sync` must be **defined** (dispatch includes the role on
  `... is defined` and never reads the value). Miss either and there is no
  error — the repository is created, stays empty, and Controller later fails to
  pull an image that was never mirrored. That flag is deliberately not suffixed
  `_all`: it is a scalar, and dispatch's wildcard merge handles only lists and
  dicts.
- `controller_execution_environments.yml` — image is now
  `{{ aap_hostname }}/sales_demos_ee:v1.0.0`. **Templated on purpose**: PAH is
  fronted by the AAP gateway on the AAP hostname, which differs per environment,
  so a literal would make this shared `_all` entry wrong for one of
  sandbox/demo. The name uses underscores because Hub repository names allow
  only alphanumerics and underscores.
- `controller_credentials.yml` — `Sales Demos - PAH Registry` (Container
  Registry). PAH requires authentication for container pulls even when the
  repository is not private, so this is needed regardless of visibility.
- `collections/requirements.yml` — `ansible.hub` pinned to 1.1.0. It drives the
  Hub objects and was **unpinned and drifting**: 1.0.4 was installed locally
  while the execution environment ships 1.1.0.

### Notes -- why PAH works here without weakening the cluster (#35)
- AAP 2.6's gateway proxies Hub **by path** at `/api/galaxy/`; there is no
  separate hub route. `ansible.hub`'s `ah_path_prefix` already defaults to
  `galaxy`, so nothing needs overriding.
- The `*.apps` certificate is issued by Google Trust Services and is publicly
  trusted, so the cluster pulls from PAH over TLS with **no**
  `insecureRegistries` and **no** `additionalTrustedCA` — both verified still
  empty after the change.
- Verified end to end: `skopeo inspect` against PAH returns
  `sha256:a6ee9e4b110bc12d47b222af93127f8fae9f8e3d02599dd8f1b35e3204d3559b`,
  byte-identical to the quay original, and both job templates ran to success on
  the PAH-sourced image.

### Added -- Phase 3: run playbooks from AAP, and against the VMs (#4)
- `playbooks/provision_vm.yml` — ported from `dc1.azure`. Asserts inputs, runs
  `terraform init`/`apply` against `terraform/ocpvirt/`, and registers the VMs
  into AAP (`linuxweb` with SSH vars, `windemo` with WinRM vars). The output
  shape is preserved field-for-field, so Phase 4 needs no adaptation.
- `terraform/ocpvirt/backend.tf` — state moves to the **kubernetes backend**.
  Local state is fatal from AAP: an execution-environment pod is ephemeral, so
  state would vanish with the job and teardown (#6) would have nothing to
  destroy from. State lives in a Secret in a long-lived namespace of its own,
  deliberately **not** the VM namespace — `oc delete project
  sales-demos-sandbox` is the obvious way to clean up a demo and must not take
  the state with it. `secret_suffix` keys `sandbox` and `demo` apart.
- `playbooks/check_vm.yml` and the `Sales Demos - Check VMs` job template —
  the proof that AAP can run playbooks *against* a VM, not merely create one.
- Config-as-code in `inventory/group_vars/aap/`: project, both inventories, the
  inventory source, credentials, and both job templates.

### Changed -- the vaulted secrets file moved (#4)
- `inventory/group_vars/aap/secrets.yml` → **`playbooks/group_vars/all/secrets.yml`**.
  Ansible loads `group_vars/` beside the playbook as well as beside the
  inventory, so playbooks resolve it identically. AAP does not: an SCM inventory
  source runs `ansible-inventory`, which parses every `group_vars` file next to
  the inventory. Verified against live AAP 2.6 — the vaulted file under
  `inventory/group_vars/` makes the sync die with `ERROR! Attempting to decrypt
  but no vault secrets found`; it cannot be given the password, because AAP
  rejects Vault credentials on SCM sources outright; and a custom credential
  type injecting `ANSIBLE_VAULT_PASSWORD_FILE` *would* work but is the wrong
  answer, since the sync would then write `env_secrets` and the SSH private key
  into AAP's inventory variables in plaintext. Moving it keeps secrets out of
  the inventory tree while `connection.yml` still syncs freely.
- `inventory/group_vars/{sandbox,demo}/connection.yml` — `demo_ssh_public_key`
  filled in. Both were empty, which made cloud-init emit `ssh_pwauth: true` with
  no authorized key *and* no password: the guest had no credentials at all and
  was unreachable by SSH, by `virtctl`, by anything.
- `inventory/group_vars/aap/controller_projects.yml` — `scm_branch` accepts a
  `sales_demos_branch` override. A job template validates its `playbook:`
  against the project's current checkout, so without this no config-as-code
  referencing a new playbook can be tested before merging.

### Fixed -- the private-key check never worked (#4)
- `utilities/check-no-secrets.sh` — the private-key pattern starts with
  `-----`, which `grep` parsed as an option bundle. `grep` errored, the error
  was swallowed by `2>/dev/null || true`, `hits` came back empty, and the check
  reported **pass** on files that plainly matched. Fixed with `-e`, and verified
  by planting a real key in a tracked file and watching the check fail. This is
  the guard that stops a private key reaching a public repo; it had been inert.
- `.ansible-lint` — `yaml[line-length]` moved to `warn_list`, matching what
  `.yamllint` already declared. An SSH public key is a single 575-character
  token that cannot be wrapped without risking silent base64 corruption.

### Notes -- how AAP reaches the VMs (#4)
- **No bastion and no `virtctl`.** AAP runs on the same cluster as the VMs, each
  VM has a headless Service giving stable in-cluster DNS, and there is no
  NetworkPolicy between the namespaces — so it is plain `ssh` to port 22 at the
  address `provision_vm.yml` already registers. `virtctl ssh` is the *laptop*
  path, because a laptop is outside the cluster; the execution environment does
  not ship the binary.
- The kubernetes backend will **not** accept a bare host + token despite
  advertising those keys — it builds its client through client-go's `clientcmd`,
  where they are only overrides on a base config. The playbook synthesises a
  kubeconfig and passes `config_path`; `insecure` must be passed separately
  because the backend ignores `insecure-skip-tls-verify` from the file.
- `ansible.controller` 4.8.0 has no `controller_oauthtoken`; the parameter is
  `aap_token`. A gateway token from `ansible.platform.token` returns 401 against
  `/api/controller/v2/` on AAP 2.6, so the playbook uses basic auth like
  `playbooks/config.yml` — and then has no token to leak or clean up.

### Added -- execution environment with terraform (#31)
- `execution-environment.yml` — the image AAP runs this repo's playbooks on,
  built on `ee-supported-rhel9` (AAP 2.6). It exists for one reason: Phase 3
  (#4) drives `terraform/ocpvirt/` through `ansible.builtin.command`, and no
  stock execution environment ships the terraform binary. Terraform 1.15.8 is
  downloaded and sha256-verified rather than installed from the HashiCorp yum
  repo — one pinned version, one checked artifact, no extra repo config on a UBI
  base with no subscription. `curl` and `unzip` are already in the base image.
- The base image is pinned by **digest, not tag**. `latest` moves, and the
  registry publishes no immutable tag matching what `latest` currently resolves
  to (its `version`/`release` labels are absent from `RepoTags`), so the digest
  is the only thing that names one build. This follows `aap_config`.
- `dependencies.exclude.python: [systemd-python]`. ansible-builder introspects
  every collection in the image, not just the ones requested. `ee-supported-rhel9`
  ships `ansible.eda`, whose `requirements.txt` lists `systemd-python` for its
  journald event source; no wheel is published, so pip builds from source and
  fails with `Cannot find libsystemd or libsystemd-journal` on a UBI base with no
  `systemd-devel`. Nothing here has a journald event source, so the dependency is
  pure collateral from the base image and is excluded rather than compiled.
  (`aap.lightspeed.patching` compiles it instead — correct there, because that EE
  is on `ee-minimal` where the dependency arrives through a collection in use.)
- `options.package_manager_path: /usr/bin/microdnf` — `ee-supported-rhel9` ships
  microdnf, not dnf, and ansible-builder defaults to `/usr/bin/dnf`.
- `utilities/build-ee.sh` — the build entry point. Stages `~/.ansible.cfg` into
  the gitignored `.ee-build/` so the galaxy stage can install certified
  collections, asserting first that it is a **real file**: ansible-builder's
  `COPY` does not follow symlinks, so a symlinked config silently yields an image
  with no Hub token. It is staged rather than referenced in place because an
  absolute `/home/<user>/` path is not portable and a tracked `ansible.cfg` at
  the repo root would shadow `~/.ansible.cfg` and break certified installs
  machine-wide. The token reaches the galaxy build stage only; the published
  image carries no credential.
- The script verifies the built image **as UID 1000**, which is who AAP runs a
  job as — `terraform version` must execute, and every collection pinned in
  `collections/requirements.yml` must be present at exactly that version. The
  in-Containerfile check cannot do this: ansible-builder emits `USER 1000` after
  every `append_final` step, so those steps all run as root.
- `inventory/group_vars/aap/controller_execution_environments.yml` — registers
  `quay.io/zigfreed/sales-demos-ee:v1.0.0` in AAP, applied by
  `playbooks/config.yml` via the dispatch role like every other object. It lives
  in `group_vars/` rather than `demos/ocpvirt/` because dispatch reads
  `group_vars` implicitly and nothing loads `demos/ocpvirt/` yet; it can move
  when #4 adds a loader. A **public** quay repository on purpose, so the cluster
  pulls it with no image pull secret and no AAP registry credential.
- `collections/requirements.yml` — `cloud.terraform` 4.0.0 pinned. The binary,
  not this collection, is the hard requirement for Phase 3, but pinning it keeps
  the module set identical on both entry points and lets `ansible-lint` resolve
  it locally.
- `.claude/skills/sales-demos-ee-build/` — build, verify, and publish the EE.
  No playbook, deliberately: like `collections-sync` it touches a laptop and a
  registry, never a demo environment, so it must never run from AAP. Carries the
  immutable-tag rule and the build gotchas.

### Added -- public SSH and HTTP access (#29)
- `terraform/ocpvirt/variables.tf` — `demo_ssh_public_key` variable. When set,
  cloud-init injects the key via `ssh_authorized_keys` and disables password-based
  SSH (`ssh_pwauth: false`). A public key is not a credential, so it lives in each
  environment's `connection.yml` beside `linux_admin_username`, not in the vault.
  The `accessCredentials` + `qemuGuestAgent` mechanism was tried first but the
  RHEL 9 cloud image's guest agent fails with "failed to create directory
  '/home/cloud-user/.ssh': File exists" — a QEMU guest agent `mkdir` bug —
  and the `guest-exec` fallback is disabled by RHEL 9's security policy.
  Cloud-init works reliably; the trade-off is that key rotation requires a VM
  restart rather than a live push.
- `terraform/ocpvirt/variables.tf` — `openshift_apps_domain` variable, the
  `*.apps` ingress domain used to construct Route hostnames at plan time.
  Required for HTTP access; without it the Route and web Service are skipped.
- `terraform/ocpvirt/main.tf` — `-web` ClusterIP Service (port 80) and
  `route.openshift.io/v1` Route per Linux VM. The headless Service is unchanged
  (in-cluster DNS for AAP inventory). The Route returns 503 until httpd is
  installed by the AAP demo content (#5); that is expected, not a bug.
- `terraform/ocpvirt/outputs.tf` — `web_url` (the Route URL, null when
  `openshift_apps_domain` is unset) and `ssh_command` (the `virtctl ssh` command
  for the current VM, null when `os_type` excludes linux).
- `inventory/group_vars/{sandbox,demo}/connection.yml` — `demo_ssh_public_key`
  and `openshift_apps_domain` fields added to both environments.

### Notes -- NodePort spike (#29)
- NodePort was spiked on the RHDP sandbox cluster and is **filtered**. The RHDP
  firewall blocks high ports — `ssh -p <nodePort> cloud-user@<public-ip>` returns
  "No route to host". SSH access uses `virtctl ssh` instead, which tunnels over
  the Kubernetes API (port 6443, confirmed open). The spike Service was created,
  tested, and deleted in a single session; no residue remains.

### Added
- `terraform/ocpvirt/` — Phase 1. Provisions Linux and Windows VMs sized by
  `sd1.*` cluster instance types, each with a headless Service giving a stable
  in-cluster DNS name, since an OpenShift Virt VM has no plan-time-knowable
  address. The `linux_inventory` / `windows_inventory` output shape is preserved
  field-for-field from `dc1.azure/terraform`, which Phases 3 and 4 consume. A
  precondition enforces the guest-memory budget so an over-budget request fails
  in `plan` rather than leaving a VM `Pending`. Verified on the sandbox: VM
  `Running` and `Ready` in 5m47s, PVC `Bound`, `terraform plan` clean. (#2)

### Fixed
- `terraform/ocpvirt/` — `terraform plan` could never come back clean, so the
  module could not be trusted to report real drift. Two independent causes, both
  cases of the cluster owning fields Terraform believed were its own:
  - The namespace drifted forever. OpenShift's SCC controller stamps every
    namespace with the UID/GID/MCS ranges it allocated plus the derived
    pod-security level; Terraform planned to strip all four on every run and the
    controller put them straight back. Applying it would also have handed the
    guests a different UID range than the one their pods were admitted under.
    Now ignored via `lifecycle`, as cluster-owned.
  - `spec.template.metadata` is `x-kubernetes-preserve-unknown-fields`, so the
    provider has no schema and infers the object type from the manifest — making
    the key set load-bearing. KubeVirt's webhook adds
    `kubevirt.io/pci-topology-version` and a null `creationTimestamp`, which the
    manifest never declared, so plan failed reading the refreshed object back and
    apply failed with "Provider produced inconsistent result". `computed_fields`
    does not help here: it can override a value but cannot add a missing
    attribute. Both keys are now declared, with `computed_fields` still covering
    their values.
- `playbooks/install_cnv.yml` — installs OpenShift Virtualization: namespace,
  OperatorGroup, `kubevirt-hyperconverged` Subscription on the `stable` channel,
  and the `HyperConverged` CR, then waits for the operator to report `Available`
  and the RHEL boot-source DataSource to be `Ready`. Idempotent, no prompts,
  every input via `extra_vars`. Discovers the cluster's default StorageClass at
  run time rather than hard-coding one, so it is not tied to a single catalog
  item. Deliberately does not enable hugepages, KSM, or workload partitioning —
  each writes a MachineConfig and reboots the node, and AAP is co-resident on
  the only node in this catalog item. (#1)
- `playbooks/setup.yml` — Phase 0 entry point; currently imports
  `install_cnv.yml`. The AAP bootstrap half of #1 imports here when it lands, so
  the skill, the README table, and the future job template never re-point.
- `.claude/skills/ocpvirt-setup/SKILL.md` — first in-repo skill. Preflight
  checks, a cluster-side check for whether CNV is already present, then invokes
  `playbooks/setup.yml`. No business logic, per the two-entry-point contract.
  Ends in a verification step that queries the cluster for the
  `kubevirt.io`/`cdi`/`hco`/`instancetype` API groups, the `u1` instance-type
  shapes the sizing tiers depend on, and `devices.kubevirt.io/kvm` on the node —
  a green Ansible recap is not treated as proof. (#1)
- `kubernetes.core.k8s` and `kubernetes.core.k8s_info` added to `.ansible-lint`
  `mock_modules` so the offline CI lint gate can resolve them.

- Initial repository skeleton for the two-axis layout: `demos/` by demo,
  `terraform/` by platform, `inventory/group_vars/` by environment.
- `docs/plan/ocpvirt-demo-plan.md` — environment research confirming the RHDP
  "Ansible Product Demo" catalog item supports OpenShift Virtualization, plus
  the phase-by-phase implementation plan.
- `ROADMAP.md` covering phases 0–4 and the t-shirt sizing tiers.
- Secrets convention: `inventory/group_vars/<env>/secrets.yml` as the single
  place every environment-specific value lives, with `secrets.yml.example` as
  the repo's only `.example` file.
- `.gitignore` as the first commit, so no environment-specific value can enter
  history.
- CI lint gate ported and adapted from `aap_config`: yamllint, ansible-lint,
  a secret-hygiene guard, and a portability check on in-repo skills.
- `utilities/check-no-secrets.sh` — enforces the pre-push audit automatically.
  Matches the shape of real credentials so docs and `.example` placeholders pass
  while genuine values fail the build.
- `.yamllint`, `.ansible-lint`, and pinned `collections/requirements.yml`.
- GitHub CODEOWNERS, PR template, issue templates, and security policy.
- `.claude/skills/collections-sync/SKILL.md` — pins, installs, and verifies the
  collections, failing loudly on drift. No playbook, deliberately: it touches
  the laptop's collection path, never a demo environment, so it must never run
  from AAP. (#8)

- Shared AAP configuration ported from `ericcames/aap_config` into
  `inventory/group_vars/aap/` — `aap_settings.yml`
  (`dispatch_include_wildcard_vars`, `aap_configuration_secure_logging`),
  `aap_organizations.yml`, `controller_settings.yml` (Automation Analytics and
  subscriptions), and `gateway_settings.yml` (the `custom_login_info` sign-in
  banner). Values verbatim; comments adapted to this repo, which has two
  environments and no export tooling. Every key was verified present on the
  live AAP 2.6 catalog item first, so the standing "aap_config targets 2.7, do
  not copy its settings verbatim" caution does not apply to these files.
  Collection pins already matched exactly. Nothing consumes these variables
  until the AAP bootstrap half of #1 lands. (#14)
- `vaulted_subscriptions_client_id` and `vaulted_subscriptions_client_secret`
  added to `secrets.yml.example`. `controller_settings.yml` requires both in
  every environment or the apply fails with an undefined-variable error. (#14)

### Added — first-time setup and run logging (#26)
- `.claude/skills/sales-demos-first-time/SKILL.md` — one-time setup for a new
  machine. Audits what exists, guides what is missing, and validates each step by
  exercising the real path (inventory resolution, the vault, and the Hub token
  lookup together) rather than checking files exist.
  - It is explicit that the vault password **cannot be created by a new user**.
    `group_vars/aap/secrets.yml` is committed but encrypted, so without
    `~/secrets/.vault_pass_sales_demos` nothing decrypts and every playbook fails.
    It has to be handed over; there is no derivation and no recovery.
- Run logs now go to **`~/ansible-logs/`, outside the repo**, via
  `ANSIBLE_LOG_PATH`. Documented in `README.md`, the `ocpvirt-setup` skill, and
  the first-time skill. Outside the repo on purpose: this repo is public, and
  keeping logs out entirely beats relying on an ignore rule. A defensive
  `logs/` + `*.log` rule is added anyway in case someone points
  `ANSIBLE_LOG_PATH` at the working tree.
  - **Not `tee`.** In a pipeline the exit status comes from `tee`, not from
    `ansible-playbook`, so a failed run reports success. This is recorded because
    it caused a real misread during Phase 0. `ANSIBLE_LOG_PATH` also works
    without an `ansible.cfg`, which matters since a project-local one is banned.

### Changed
- `CLAUDE.md` and `README.md` now state plainly that **this repo is
  self-contained**: every skill it needs lives in `.claude/skills/`, nothing
  depends on a plugin or another repo's skills, and nothing that does should be
  added. The skill-authoring guidance points at `ocpvirt-setup` as the in-repo
  example rather than at an external repo. (#26)

### Added — config-as-code apply and validate (#24)
- `playbooks/config.yml` applies the AAP objects defined in
  `inventory/group_vars/`; `playbooks/validate.yml` is the same play in check
  mode. Until now nothing in this repo ran `infra.aap_configuration.dispatch`, so
  the objects ported in #14 and the sign-in logos from #20 had never been executed
  against a real AAP.
- Both are thin — the work is `include_role: infra.aap_configuration.dispatch`,
  with variables arriving implicitly from `inventory/group_vars/`. Basic auth via
  `aap_username`/`aap_password`; no OAuth token is minted, so there is nothing to
  leak and nothing to clean up in an `always:` block.
- The environment guard from #16 moves to
  `playbooks/tasks/assert_target_environment.yml` rather than being copied a third
  time; `install_cnv.yml` adopts it and still runs at `changed=0`.
- Verified against the sandbox by running it: check mode `ok=36 changed=4`, then
  the apply `ok=37 changed=2`, then confirmed against the AAP API — organization
  created, banner set, and `custom_logo` byte-identical to the committed
  `docs/images/logo-sandbox.png.b64`.
- Documented check-mode caveat: some roles' "wait for the object to exist" tasks
  report `FAILED - RETRYING` under check mode because nothing was created for them
  to find. The play still succeeds; treat check mode as a strong signal, not a
  contract.

### Changed — what the vault actually holds (#22)
- **`automation_hub_token` is no longer stored in the vault.** Nothing consumed
  it — `ansible-galaxy collection install` reads `~/.ansible.cfg` itself, which
  is the authoritative copy of that token and is shared across every repo.
  `inventory/group_vars/aap/main.yml` now reads it with an `ansible.builtin.ini`
  lookup against `~/.ansible.cfg`, matching how `aap.as.code` and `aap-skills`
  already do it. A vaulted second copy would have gone stale silently on the
  next rotation, with nothing to detect the drift.
  - Reads `~/.ansible.cfg`, **not** `~/.ansible/ansible.cfg`. Both hold the same
    token today, but the latter is a frozen leftover from when the former was a
    symlink, and will drift. `aap-skills` still points at the stale path.
  - Known limitation, documented in the file: the lookup resolves on the
    controller, so it will not resolve inside an AAP execution environment. The
    only consumer is the AAP bootstrap, which is inherently laptop-side.
- **The Automation Analytics credentials are now real, not `CHANGEME`.**
  `vaulted_subscriptions_client_id` and `_client_secret` are required by
  `controller_settings.yml` for every environment (#14) but were seeded as
  placeholders. Copied from `aap_config`'s qa vault — the same Red Hat service
  account — by piping between `ansible-vault` invocations, so the values never
  touched a plaintext file or shell history.
  - Consequence recorded in the vault file's header: they now live in two vaults
    with no shared secret store, so rotating the service account means updating
    both.
- `secrets.yml.example` stays `CHANGEME` for the analytics keys — it is a
  template, not a value store — and now explains that the Hub token is not there.

### Added — per-environment sign-in logos (#20)
- `inventory/group_vars/<env>/gateway_settings.yml` sets the gateway's
  `custom_logo` to an environment-badged version of the AAP lockup, so the
  sign-in page shows which environment you are entering. Green for `sandbox`,
  red for `demo` — the environment you break, and the one you show customers,
  reusing `aap_config`'s severity convention.
- `utilities/make-env-logo.py`, ported from `aap_config` with this repo's two
  environments in place of its dev/qa/prod. Extends the official product lockup
  rather than replacing it, so Red Hat branding survives and only a badge is
  added. Needs Pillow, ImageMagick with the librsvg delegate, and Red Hat
  Display.
- `docs/images/` — `aap-logo-white.svg` plus the generated `logo-{sandbox,demo}.png`
  and their base64 sidecars, all committed so they render on GitHub and so a
  clone does not need ImageMagick to apply the config.
- `custom_logo` changes the **sign-in page only**, never the post-login masthead,
  which is a bundled UI asset rather than a setting. Confirmed on AAP 2.6: 44
  gateway settings exist and none of them mark the environment after login.
- Relies on `dispatch_include_wildcard_vars` merging `gateway_settings_all` with
  `gateway_settings_<env>`. The shared `custom_login_info` banner stays in
  `group_vars/aap/`, and the per-environment files set only `custom_logo` —
  verified disjoint, since merging is per-key and a scalar in both would mean the
  environment file wins rather than combines. The setting reaches a real gateway
  only once an AAP apply playbook exists (the open half of #1).

### Changed — secrets model (#18)
- **`secrets.yml` is now vault-encrypted and committed, not gitignored plaintext**,
  matching `aap_config`. One file at `inventory/group_vars/aap/secrets.yml`,
  vault-id `sales.demos`, loaded for every environment because it sits in the
  `aap` group directory. Replaces the per-environment gitignored files.
- **It holds credentials only.** Per-environment credentials are keyed under
  `env_secrets` by environment name; each `connection.yml` selects its slice with
  `env_secrets[aap_env_name]`, which is also what keeps `--limit demo` from
  reaching sandbox's credentials (#16).
- **`connection.yml` now carries the environment-specific non-secrets** in
  committed plaintext — `aap_hostname`, `openshift_api_url`, usernames,
  namespaces. It previously held structure only. A new RHDP environment is now a
  two-file edit: that `connection.yml` plus two keys in the vault.
- **RHDP URLs are no longer treated as sensitive.** `*.dyn.redhatworkshops.io`
  hostnames are ephemeral demo-platform addresses, not customer-identifying, and
  are committed in the clear on purpose — that is what lets the vaulted file hold
  credentials only. The RHDP-hostname pattern is removed from
  `utilities/check-no-secrets.sh`. This reverses a rule previously stated in
  `CLAUDE.md`, `CONTRIBUTING.md`, `README.md`, and the plan doc, all updated.
- **`utilities/check-no-secrets.sh` guard inverted.** The "no tracked
  `secrets.yml`" rule is replaced by "a tracked `secrets.yml` must begin with
  `$ANSIBLE_VAULT`", checked against the committed blob rather than the working
  tree. Since `secrets.yml` is no longer gitignored, this is the only thing
  preventing a plaintext credential file from being pushed. Every other pattern —
  bearer tokens, private keys, AWS and GitHub tokens, quay credentials — is
  unchanged. Verified by triggering it: a staged plaintext `secrets.yml` fails
  with exit 1.
- `.gitignore` drops the `inventory/group_vars/*/secrets.yml` rule and adds vault
  password patterns. The password itself lives outside the repo at
  `~/secrets/.vault_pass_sales_demos`, following the same convention as
  `aap_config`'s `.vault_pass_<env>` files.
- `.claude/skills/ocpvirt-setup/SKILL.md` — two real breakages fixed, not just
  wording. Its preflight asserted `git check-ignore` *succeeds* on `secrets.yml`,
  which is now exactly backwards; and its preflight and verification blocks
  `yaml.safe_load`ed the secrets file directly, which fails on ciphertext. Both
  now resolve credentials through `ansible … -m debug` with `--vault-id`, so the
  `--limit` selects the environment by the same path the playbook takes.

### Fixed
- **`--limit demo` silently targeted `sandbox`.** Both environment groups in
  `inventory/hosts.yml` pointed at the same host, `localhost`. `--limit` filters
  which hosts run, not which `group_vars` load, so a host in two environment
  groups loaded both environments' variables — and same-level groups resolve
  alphabetically with the later name winning, so `sandbox` always beat `demo`.
  Asking for `demo` returned sandbox's hostname and sandbox's bearer token with
  no warning, which meant the `demo` environment could not be targeted at all.
  Each environment now has its own host (`sandbox-local`, `demo-local`), so
  `group_vars` stop merging. Adding a `demo/secrets.yml` would not have fixed
  this; `sandbox` still won. (#16)
- Playbooks target `hosts: aap` and assert that exactly one environment is in
  scope, so a run without `--limit` fails closed instead of configuring both
  environments at once. An optional `-e target_env=<env>` makes the play verify
  the inventory resolved to the environment the caller intended. `--limit
  sandbox` and `--limit demo` are unchanged as invocations. (#16)

### Changed
- `aap_organization_name` in `inventory/group_vars/aap/main.yml` moved
  `Default` → `IT Service Automation`, matching the organization
  `aap_organizations.yml` declares, so the repo names one organization rather
  than two. A fresh RHDP environment ships `Default` and `Ansible Product Demos
  (APD)`, so the first apply creates it. (#14)
- **Every collection in `collections/requirements.yml` is now pinned to an exact
  version.** `ansible.platform` (2.7.20260604), `ansible.controller` (4.8.0),
  `kubernetes.core` (6.4.0), and `redhat.openshift_virtualization` (2.3.0) were
  floating, so two laptops could resolve different code. Pins record the
  versions Phase 0 was validated against, not the newest published. (#8)
- `infra.aap_configuration` pin moved 4.2.0 → 4.7.0 to match what is installed
  and used. Nothing in this repo consumes it yet; revisit when the AAP bootstrap
  half of #1 lands. (#8)
- `.gitignore` now covers `.ansible/`, ansible-lint's artifact directory.
  Collections install to `~/.ansible/collections` and are never vendored here.
  (#8)
- `inventory/hosts.yml` pins `ansible_python_interpreter` to
  `{{ ansible_playbook_python }}`. Interpreter discovery otherwise picks whatever
  `/usr/bin` python it finds first, which on Fedora can be an older minor version
  without the `kubernetes` client. Pinned in the inventory rather than an
  `ansible.cfg`, which would shadow `~/.ansible.cfg` and break certified
  collection installs. (#1)
- `docs/plan/ocpvirt-demo-plan.md` records the Phase 0 validation run. The
  original research stands — it correctly reported `kubevirt-hyperconverged` as
  *available in the operator catalog*, not installed — but the doc read as a
  plan with nothing confirming it had been executed. Now states outright that a
  freshly provisioned environment has no `kubevirt.io` API group, and adds the
  observed versions and timings, confirmation of the `u1` instance-type shapes
  the sizing tiers depend on, the decision to discover the default StorageClass
  rather than hard-code it, and a note that OpenShift version and cluster ID are
  per-environment samples rather than properties of the catalog item. (#9)

### Removed
- Three ansible-lint-generated module mocks that were tracked under
  `.ansible/collections/ansible_collections/`. They are regenerated from
  `.ansible-lint` `mock_modules` on every run, so tracking them only guaranteed
  they would go stale. (#8)

### Notes
- `aap_config`'s `deploy-{dev,qa,prod}` workflows were deliberately not ported
  and will not be (#7). CI is a PR gate only; nothing deploys from GitHub
  Actions. Deploys run via `ansible-playbook` — wrapped by a skill locally, or
  as an AAP job template — which keeps every environment-specific value in the
  gitignored `secrets.yml` with no second copy in GitHub Environment secrets.
