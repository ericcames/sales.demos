# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
