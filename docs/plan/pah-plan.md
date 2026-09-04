# Private Automation Hub as code — the repo's second use case

## Context

`sales.demos` shipped one use case (OpenShift Virtualization) and reserved a row
in `docs/demos/README.md` for a second: *Private Automation Hub — ClickOps vs.
configuration-as-code*. This is that work, tracked as
[#68](https://github.com/ericcames/sales.demos/issues/68).

Two questions were being answered at once. The demo question — *why should a
sysadmin who is happy clicking in a web UI care about config-as-code?* — and a
practical one: every RHDP environment ships a Private Automation Hub, and every
one of them was empty.

**Answer: yes to both, and they turn out to be the same work.** The thing that
makes the demo land is that the hub's contents are a reviewable artifact in git,
and the thing that makes the environments useful is the same file.

### What the platform actually gives you

Probed against the live sandbox before anything was written.

| Component | Finding |
|---|---|
| PAH deployment | Present on every environment. Five hub pods, `hub disabled=False` |
| Gateway routing | AAP 2.6 fronts Hub by **path**, at `/api/galaxy/`. No separate hub route; `ansible.hub`'s `ah_path_prefix` already defaults to `galaxy` |
| Stock remotes | `rh-certified`, `validated`, `community` all **already exist**. Every object this repo defines is an update, not a creation. `sync_hub.yml` re-checks this at run time rather than trusting the finding (#124) |
| Certified content | **214** collections upstream, not the ~130 estimated |
| Validated content | **47** collections upstream, not the ~30 estimated |
| `ansible.hub` | Already pinned at 1.1.0 and already in the EE. No new collection, no EE rebuild |
| Auth | `ansible.hub` uses `ah_username`/`ah_password`; the offline token is only for the remotes' upstream calls |

### Constraints that shape the design

1. **Pulp has no "keep N versions" control.** A requirements entry of a bare
   `namespace.name` syncs every published version. This is the single fact the
   whole design bends around.
2. **`retain_repo_versions` is not that control.** It prunes repository
   snapshots, not collection versions. Easy to mistake for the answer; it is not.
3. **`requirements` and `requirements_file` are mutually exclusive**, and
   `requirements` is a list of bare names with nowhere to put a version
   (`ansible/hub/plugins/modules/collection_remote.py:221-231`). Anything that
   bounds versions must go through `requirements_file`.
4. **The offline token is an SSO refresh token**, tied to a subscription
   entitlement, and expires after 30 days of non-use. It must never be plaintext
   in a public repo.
5. **An expired token does not error.** It authenticates and returns zero
   collections. Every failure mode here is quiet, so every check has to be
   explicit.
6. **An execution environment has no `~/.ansible.cfg`.** This is what makes PAH
   work laptop-only — see the decision below.

### Scope

Populate the hub. **Do not point AAP at it** — that is
[#69](https://github.com/ericcames/sales.demos/issues/69), deliberately deferred
behind gates.

---

## The three tokens

The deliverable, not a footnote. `ansible.hub` and `ansible-galaxy` use the word
"token" for three unrelated credentials, and this is where people stall on day
one.

| # | Token | Where you get it | Who talks to whom | Where it lives | Why there |
|---|---|---|---|---|---|
| 1 | **Red Hat offline token** | `console.redhat.com/ansible/automation-hub/token` → *Load token* | **your PAH → Red Hat**, to sync `rh-certified` and `validated` | `~/.ansible.cfg` under `[galaxy_server.rh_certified]`, and nowhere else | An SSO refresh token tied to your subscription entitlement. `~/.ansible.cfg` is already the authoritative copy shared across every one of Eric's repos (#22); a second copy anywhere means one that silently rots at the next rotation |
| 2 | **PAH API token** (your own hub) | your PAH UI → *Collections → API token* | **a client → your PAH**, to install from it | **nowhere — not stored** | Per-user and short-lived, so a stored copy is a guaranteed stale value. `ansible.hub` authenticates with `ah_username`/`ah_password`, already resolved from `connection.yml` plus the vault |
| 3 | **galaxy.ansible.com token** | `galaxy.ansible.com` | **you → public Galaxy**, to *publish* | **nowhere — you do not need one** | Reading public collections is anonymous. The community remote carries no credential at all |

**Why not an AAP credential for token 1.** AAP ships no credential type carrying
a Red Hat offline token in the form `collection_remote` wants; it would need a
custom credential type injecting an env var. That is a legitimate option for a
customer who will not adopt a vault file, and worth naming in the room — it is
just a second mechanism this repo does not need.

### ~~The token gets a vaulted fallback so the sync can run from AAP.~~

> **Superseded during implementation.** It was built and verified working in both
> directions — ini lookup on a laptop, vaulted key inside an EE. Then removed.
>
> It bought exactly one thing, a hub-sync job template, at the cost of a second
> copy of a rotating credential — the specific failure `main.yml`'s #22 comment
> exists to prevent. **PAH work is laptop-only instead**, which is where
> `config.yml` has always been: you cannot use AAP to bootstrap itself.
>
> The consequence is worth stating because it fails quietly: run any of this
> inside an EE and the token resolves to an empty string, the remotes are
> configured with no credential, and they sync nothing behind a green run.
> `playbooks/sync_hub.yml` asserts the token up front for exactly that reason.

---

## The version window

Certified and validated keep the **3 newest** versions of each collection;
community keeps **1**. Knobs: `--certified-versions`, `--validated-versions`,
`--community-versions` on the refresh script; `0` means all.

The mechanism is a floor per collection, computed at refresh time:

```yaml
  - name: kubernetes.core
    version: ">=6.3.0"      # 6.3.0, 6.4.0, 6.5.0 — the 3 newest
```

**Why 3 and not 1 for certified.** A customer playbook pinned to a slightly older
certified version has to still resolve. That is the whole reason to keep depth,
and it is the honest answer when someone asks why the hub is not just "latest of
everything".

**`>=` only ever widens.** Re-running the refresh raises the floor so future
syncs pull less, but versions already synced stay in the repository until orphan
cleanup. The window caps what *arrives*, not what is already there. Stated in
`objections.md` rather than buried in a comment.

---

## Layout

```
hub/                                  what PAH SYNCS — not what you install
├── certified-requirements.yml         214 collections, >= floors      generated
├── validated-requirements.yml          47 collections, >= floors      generated
└── community-requirements.yml          15 collections, exact pins     generated

utilities/refresh-hub-requirements.py  regenerates all three; --check, --audit-pins

inventory/group_vars/aap/
├── hub_collection_remotes.yml         three remotes, requirements_file each
├── hub_collection_repositories.yml    three repositories, sync gates
└── main.yml                           automation_hub_token (edited)

playbooks/sync_hub.yml                 blocking sync + verification. No job template.
.claude/skills/pah-sync/SKILL.md
docs/demos/private-automation-hub/     six documents, not five
```

**`hub/` is its own directory deliberately.** `collections/requirements.yml` is
what your laptop and the EE *install*. `hub/*.yml` is what PAH *syncs from
upstream*. Different direction, different lifecycle. Confusing the two is the
likeliest mistake in this whole use case, and every generated file says so in its
header.

### Why a script rather than a playbook

The refresh writes into the repo checkout, so it is laptop-only by nature and
must never run from AAP — the same reasoning that keeps `utilities/build-ee.sh`
out of a job template. It is also ~260 HTTP calls, which as sequential
`ansible.builtin.uri` tasks would take minutes and produce output nobody can
read. Concurrent in a script: **25 seconds** for all three lists.

---

## What was learned building it

### The async defaults are far too short, and misreport the failure

Every `infra.aap_configuration` role wraps its work in `async:` and polls with
`collect_async_status`. The defaults are 1000s of async budget and **50 retries
at 1s apart — about fifty seconds**. Fine for creating a job template; hopeless
for a sync that runs for minutes rather than seconds.

Left at the defaults the playbook fails with `attempts: 50` and, because
`aap_configuration_secure_logging: true`, a `censored` message that says nothing.
Meanwhile the sync is running perfectly well inside Pulp. Confirmed by querying
`/pulp/api/v3/tasks/` directly: state `running`, not `failed`. **A client-side
timeout misreported as a sync failure.**

`sync_hub.yml` sets 360 retries at 15s — 90 minutes — and narrows secure logging
off for the sync role alone, which carries repository names and no credentials.
The remote and repository roles keep it, because they carry the token.

### Check mode cannot validate content

`uri` does not run under `--check`, so every registered result comes back a bare
skip marker with no `json` key, and the first assertion dies on a missing
attribute rather than reporting anything about the hub. The verification block is
gated on `not ansible_check_mode`.

A related trap: **Ansible templates a `loop_control.label` even for items the
`when` skips**, so a label reaching into a skipped `uri` result fails the task
with an error unrelated to the assertion. Labels here reference `item.item` only.

### Pagination is anchored at the domain root

`links.next` comes back as `/api/automation-hub/v3/...`, not relative to the API
base. Joining it onto the base by hand yields
`/api/automation-hub/api/automation-hub/...` and a 404 on page two — which looks
exactly like a permissions problem and is not.

### A trailing newline made every remote report changed, forever

Pulp stores a remote's `requirements_file` with the trailing newline **stripped**.
Generate the file with one and the module compares what it would send against
what is stored, finds a one-character difference, and rewrites the remote on
every run. The sync still works and the run is still green — it simply never
reports `changed=0`, which is the exact claim the demo makes.

Fixed by `rstrip("\n")` in the generator plus a per-rule `.yamllint` exemption
scoped to `hub/`. Nothing else in the repo is exempt.

### Two remotes still report changed, and always will

`rh-certified` and `validated` carry a token; the API never returns it, so the
module cannot compare and rewrites them every run. `community`, which carries no
credential, correctly reports `changed=0`.

That is the platform refusing to hand back a secret — the same behaviour
`controller_settings.yml` already documents for `SUBSCRIPTIONS_CLIENT_SECRET`.
The talk track addresses it head-on rather than hoping nobody reads the recap.

### Check mode is not a no-op, and the fix needs two guards

`ansible.hub` 1.1.0's `collection_repository_sync` reads
`module.params.get("check_mode")`, but `check_mode` is not in its argument_spec.
It is therefore always `None`, the guarded early-exit never fires, and the sync
**runs for real under `--check`**. It should be `module.check_mode`.

Left alone, `validate.yml` — whose whole job is to report what *would* change,
and which prints "Nothing will be changed" — starts three live PAH syncs.

Two guards, because one does not cover both entry points:

| Guard | Covers |
|---|---|
| `sync:` carries `not ansible_check_mode` in group_vars | CLI `--check` |
| `validate.yml` sets `hub_sync_enabled: false` | its play-level `check_mode: true` |

**`ansible_check_mode` is only True for a CLI `--check`.** A play-level
`check_mode: true` leaves it False — verified both ways, which is the whole
reason the second guard exists. Confirmed by counting Pulp sync tasks either side
of a validate run: 13 before, 13 after.

### Approval does not gate synced content, and the content is signed

`GALAXY_REQUIRE_CONTENT_APPROVAL` is `true`, which sounds like it should hold
synced collections for review. It gates the **upload** pipeline only —
`staging` → `published`. Remote syncs land directly in their repository and are
installable immediately. Verified: `staging` empty after a full sync, artifact
downloads on request.

Separately, the synced Red Hat collections **arrive signed** (`signatures: 1`).
`signed_only: false` means this hub does not *require* a signature, not that the
content lacks one — a distinction the first draft of `objections.md` got wrong.

### A sync is additive — the requirements file cannot remove anything

Tested directly: dropped a collection from `hub/community-requirements.yml`,
re-synced, and the repository still held all 15. `ansible.hub` POSTs to
`{repo}/sync/` with no body, so no `mirror` flag is sent and Pulp defaults to
additive.

**The requirements files are an allowlist for what gets pulled in, not a
declaration of desired state.** Adding works; changing a version adds the new one
and keeps the old; removing does nothing. Same root cause as the `>=` floor only
widening.

This bounds what the second use case can honestly claim, and it is stated plainly
in `objections.md` rather than left for a customer to find.

**Solved in #70 by a curated repository** — see below. Not by relabelling a sync
repository.

### The curated repository (#70), built and verified

A fourth repository, `approved`, with **no remote**. Contents declared in
`hub/approved-collections.yml` and reconciled by `playbooks/curate_hub.yml`,
which adds *and removes*.

| | the three mirrors | `approved` |
|---|---|---|
| Populated by | a sync | copying content units in |
| Removing | does nothing | **works** |
| Point consumers at it? | no | yes |

**Seeded with what this repo depends on** — the nine pins from
`collections/requirements.yml`, at exact versions. Not arbitrary: it is what
makes #69 safe, and it sidesteps the version window (`approved` holds exactly one
version of `ansible.platform`; `rh-certified` holds four).

**Mechanics.** `ansible.hub` 1.1.0 has no repository-to-repository copy, so this
drives Pulp directly: `POST {repo_href}modify/` with `add_content_units` and
`remove_content_units` in one atomic call. **Not the `move/` endpoint** — a move
takes the collection *out* of the source, which would silently strip
`rh-certified`. Verified on a scratch repository (create, add 0→1, remove 1→0,
delete) before a line of the playbook was written.

Two things that cost time and are worth knowing:

- **`pulp_href` is a path, not a URL.** `uri` fails with `unknown url type` until
  the scheme and host are prepended.
- **The first real run failed correctly.** `ansible.platform 2.7.20260604` was
  not in the hub at all, being below the certified floor — the assert said so and
  named the fix. The generator now lowers a floor to any version this repo pins,
  which costs two extra versions across the whole hub and makes `--audit-pins`
  report *"Every pinned collection is inside its window."*

Verified: populate 0→9, idempotent re-run (`add 0, remove 0, changed=0`), removal
(delete a line → 9→8), and the `approved` distribution serving artifacts.

### Two pinned collections are already outside the window

`--audit-pins` compares `collections/requirements.yml` against the generated
floors, offline. Two of ten do not resolve from the hub:

- `ansible.controller` 4.8.0 — certified floor `>=4.8.2`
- `ansible.platform` 2.7.20260604 — certified floor `>=2.7.20260615`

**Nothing is broken today**, because no organization has a Galaxy credential.
This is precondition 2 of #69, found before it could bite. `ansible.platform`
publishes date-stamped versions frequently, so a 3-version window is unusually
narrow there.

---

## Verification

1. `yamllint .`, `ansible-lint`, `bash utilities/check-no-secrets.sh`, and the
   skills-frontmatter gate.
2. No token in any tracked file — the standard audit pattern plus a targeted grep
   for the `eyJ` JWT prefix.
3. `refresh-hub-requirements.py` twice; `git diff hub/` empty on the second run.
4. `validate.yml` against `sandbox` reports the remotes and repositories as
   changes and creates nothing.
5. `sync_hub.yml` against `sandbox` with the default `hub_sync_wait=true`.
6. Ask the hub: all three repositories non-empty, ~214 + ~47 + 15.
7. Ask the hub about the pins: every community collection at exactly its pinned
   version and **no other**. Presence alone proves nothing — a full-history sync
   passes an existence check.
8. Ask the hub about the window: a long-lived certified collection carries 3
   versions, not 30. **Without this there is no evidence the window did
   anything.**
9. Re-run: idempotent.
10. Change the community remote's rate limit in the UI, re-run, confirm it
    converges back. This is the demo's core claim — rehearse it before
    presenting it.
11. `Sales Demos - Provision VM` still green. This touches no Galaxy credential,
    so it should be, but confirm.
12. `demo` last, only after `sandbox` is clean end to end.

## Open items

- **#69 — point AAP projects at PAH.** Deferred behind six gates. Gate 2 already
  fails; see above.
- **No collection signing.** Not configured on this platform; `signed_only:
  false` on every remote. Requiring signatures would sync nothing while
  reporting success.
- **`sync_dependencies: false` on community.** Fifteen collections with
  dependencies resolved against all of Galaxy would pull in hundreds more and
  undo the curation. The cost: a community collection with an unmet dependency
  will not install from PAH alone.
- **Orphan cleanup is not automated.** The `>=` floor bounds new syncs; it does
  not reclaim what is already there.
