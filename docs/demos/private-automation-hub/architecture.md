# Architecture — Private Automation Hub

Reference for the "how does that actually work" questions. The narrative is in
[`talk-track.md`](talk-track.md).

---

## The three tokens

**This table is the single most useful thing in this document.** `ansible.hub`
and `ansible-galaxy` use the word "token" for three unrelated credentials, and
this is where people stall on day one.

| # | Token | Where you get it | Who talks to whom | Where it lives here | Why there |
|---|---|---|---|---|---|
| 1 | **Red Hat offline token** | `console.redhat.com/ansible/automation-hub/token` → *Load token* | **your hub → Red Hat**, to sync `rh-certified` and `validated` | `~/.ansible.cfg` under `[galaxy_server.rh_certified]`, and nowhere else | It is an SSO **refresh token** tied to your subscription entitlement, so it must never be plaintext in a public repo. `~/.ansible.cfg` already holds it for `ansible-galaxy`, and a second copy anywhere is one that silently rots at the next rotation |
| 2 | **Your hub's API token** | your PAH UI → *Collections → API token* | **a client → your hub**, to install collections from it | **nowhere — not stored** | Per-user and short-lived, so a stored copy is a guaranteed stale value. `ansible.hub` authenticates with a username and password instead, which this repo already has |
| 3 | **galaxy.ansible.com token** | `galaxy.ansible.com` | **you → public Galaxy**, to *publish* | **nowhere — you do not need one** | Reading public collections is anonymous. The `community` remote carries no credential at all |

Three practical consequences worth saying out loud:

- **The one that syncs your hub is not the one your users present to it.** Token
  1 points outward, token 2 points inward.
- **Token 1 fails quietly.** When it expires it does not return an auth error —
  it authenticates, returns zero collections, and leaves you a green run and an
  empty hub. Both `playbooks/sync_hub.yml` and
  `utilities/refresh-hub-requirements.py` assert on it for exactly this reason.
- **You never needed token 3.** Most people assume syncing community content
  requires a Galaxy account. It does not.

### Why not an AAP credential for token 1

AAP ships no credential type that carries a Red Hat offline token in the form
`ansible.hub.collection_remote` wants — you would define a custom credential type
injecting an environment variable. That is a perfectly good answer for a customer
who will not adopt a vault file, and worth offering in the room. It is simply a
second mechanism this repo does not need.

---

## Where the configuration lives

| File | What it holds |
|---|---|
| `inventory/group_vars/aap/hub_collection_remotes.yml` | The three remotes — URL, auth, which requirements file bounds each |
| `inventory/group_vars/aap/hub_collection_repositories.yml` | The three repositories, bound to their remotes, and the sync gates |
| `hub/certified-requirements.yml` | 214 collections, `>=` floor each — **generated** |
| `hub/validated-requirements.yml` | 47 collections, `>=` floor each — **generated** |
| `hub/community-requirements.yml` | 15 collections, exact version each — **generated** |
| `utilities/refresh-hub-requirements.py` | Regenerates all three from upstream |
| `playbooks/sync_hub.yml` | Applies, waits, then verifies against the hub |

`hub/` is its own directory on purpose. **`collections/requirements.yml` is what
your laptop and the execution environment install. `hub/*.yml` is what the hub
syncs from upstream.** Different direction, different lifecycle — and confusing
the two is the likeliest mistake in this whole design.

### It rides along on every environment build

`config.yml` — stage 2 of `setup.yml` — applies the same objects through the
`dispatch` role and *starts* a sync without waiting. So every environment gets a
configured hub as part of a normal build, and `setup.yml` stays at roughly ten
minutes. `sync_hub.yml` is the same objects with `hub_sync_wait: true`, for when
you want to watch it finish and prove it.

---

## The version window

**Pulp has no "keep the newest N versions" control.** A requirements entry of a
bare `namespace.name` syncs *every* published version, and some certified
collections have forty. That single fact shapes everything else.

`retain_repo_versions` is not that control and is routinely mistaken for it — it
prunes repository *snapshots*, not collection versions.

What works is a version floor per collection, computed at refresh time:

```yaml
  - name: kubernetes.core
    version: ">=6.3.0"      # 6.3.0, 6.4.0, 6.5.0 — the three newest
```

| Repository | Versions kept | Why |
|---|---|---|
| `rh-certified` | 3 newest | A customer playbook pinned to a slightly older certified version still has to resolve |
| `validated` | 3 newest | Same |
| `community` | current only | These are demo collections; nobody pins an old one |

Knobs on the refresh script: `--certified-versions`, `--validated-versions`,
`--community-versions`. `0` means all.

**The floor only ever widens.** Re-running the refresh raises it, so future syncs
pull less — but versions already synced stay in the repository until orphan
cleanup. The window caps what *arrives*, not what is already there.

---

## Dependency resolution is off everywhere

`sync_dependencies: false` on all three remotes, and this was learned the hard
way rather than designed in.

It was first set `true` for certified, on the reasoning that certified
collections only depend on each other so the walk could not escape the curated
set. The first real sync failed:

```
404 .../collections/index/containers/podman/
```

`containers.podman` is in neither generated list. A listed collection depends on
it, Pulp went to fetch it from console's `published` repo, and it is not there.
**One unresolvable dependency fails the entire sync task**, so the hub stays
empty.

With it off, the list is genuinely the boundary. The honest cost: a collection
whose dependencies are not themselves in the list will not install from this hub
alone.

---

## Timing

| Step | Measured |
|---|---|
| `refresh-hub-requirements.py`, all three lists | **25 seconds** (~260 HTTP calls, concurrent) |
| `--audit-pins` | instant, no network |
| Applying remotes and repositories | seconds |
| `community` sync, 15 collections | under a minute |
| **All three repositories, certified and validated starting empty** | **264 seconds (4.4 minutes)**, measured on sandbox |

The 4.4 minutes is the version window paying for itself — without it the same
sync is every version ever published of all 276 collections. Treat it as a floor
rather than a promise: that run followed earlier failed attempts so Pulp may have
had artifacts cached, and a cold cluster on a slow link will take longer. The
playbook allows ninety minutes.

### The async defaults will bite you

Every `infra.aap_configuration` role wraps its work in `async:` and polls with
`collect_async_status`. The defaults are **50 retries one second apart — about
fifty seconds**. Fine for creating a job template; hopeless for a sync running
for minutes, not seconds.

Left at the defaults the playbook fails with `attempts: 50` and, because secure
logging is on, a `censored` message that says nothing — while the sync runs
happily inside Pulp. Confirmed by querying `/pulp/api/v3/tasks/` directly: state
`running`, not `failed`. **A client-side timeout misreported as a sync failure.**

`sync_hub.yml` sets 360 retries at 15 seconds — 90 minutes — and turns secure
logging off for the sync role alone, which carries repository names and no
credentials.

---

## What the verification actually asserts

A green run proves nothing about content, so `sync_hub.yml` asks the hub:

1. **Every repository is non-empty.** Catches the expired-token case.
2. **Every community collection is present at exactly its pinned version and no
   other.** Presence alone proves nothing — a full-history sync passes an
   existence check too. This is what makes "most current version only" a claim
   rather than a hope. *Verified: 15/15.*
3. **A sample of long-lived certified collections carries no more versions than
   the window allows.** **Without this there is no evidence the window did
   anything**, because an unwindowed sync produces an equally green run and an
   equally populated hub.

Check mode cannot do any of this: `uri` does not run under `--check`, so the
verification block is skipped there entirely. Check mode validates the
*configuration*; only a real run validates the *content*.

**Measured against the live sandbox:** `rh-certified` 214, `validated` 47,
`community` 15. `kubernetes.core` carries exactly `6.3.0, 6.4.0, 6.5.0` — the
window, on a real collection. Community pins: 15/15 exact.

### Two kinds of repository

The hub holds four repositories this repo manages, and they are not the same
kind of thing:

| | `rh-certified`, `validated`, `community` | `approved` |
|---|---|---|
| Remote | yes — console.redhat.com / galaxy | **none** |
| Populated by | a sync, bounded by a requirements file | copying content units in |
| Adding | works | works |
| **Removing** | **does nothing — a sync is additive** | **works** |
| Declared in | `hub/{certified,validated,community}-requirements.yml` | `hub/approved-collections.yml` |
| Reconciled by | `playbooks/sync_hub.yml` | `playbooks/curate_hub.yml` |
| Point consumers at it? | no | **yes** |

`approved` is seeded with the nine collections in `collections/requirements.yml`
at their exact pinned versions — what this repo itself depends on. That is not
arbitrary: it is what makes #69 safe, because AAP would be pointed at a
repository containing precisely what a project sync needs.

It also sidesteps the version window entirely. `ansible.platform` is pinned at
`2.7.20260604`, and `approved` holds **exactly that one version** while
`rh-certified` carries four.

**Mechanics.** `ansible.hub` 1.1.0 has no repository-to-repository copy —
`ah_collection` only uploads an artifact from a local path. So `curate_hub.yml`
drives Pulp directly:

```
POST {repo_href}modify/   {"add_content_units": [...], "remove_content_units": [...]}
```

Both lists in one atomic call, so the repository is never briefly in a state that
is neither the old contents nor the new.

**Not the `move/` endpoint**, which is the obvious wrong turn:
`/v3/collections/{ns}/{name}/versions/{v}/move/{src}/{dst}/` exists, but a *move*
takes the collection out of the source — curating into `approved` would silently
strip `rh-certified`.

Verified: idempotent re-run reports `To add: 0, To remove: 0, changed=0`; removing
a line took the repository 9 → 8; the `approved` distribution serves artifacts.

### Approval does not gate synced content

`GALAXY_REQUIRE_CONTENT_APPROVAL` is `true` on this hub, which sounds like it
should hold everything for review. It does not, and the distinction matters:

- **Uploads** — a collection published to your own namespace lands in `staging`
  and waits for approval into `published`.
- **Remote syncs** — content goes straight into the remote's repository and is
  installable immediately.

Verified: `staging` holds zero collections after a full sync, every repository
has a distribution, and a certified artifact downloads on request.

So approval is your control over content you *author*; the requirements file is
your control over content you *consume*. Different problems, handled in
different places.

Worth knowing: the synced Red Hat collections **arrive signed** —
`signatures: 1` on both sampled collections. `signed_only: false` means this hub
does not *require* a signature, not that the content lacks one.

---

## What this deliberately does not do

**AAP is not pointed at this hub.** No organization has a Galaxy credential, so
no project sync resolves from PAH. That is [#69](https://github.com/ericcames/sales.demos/issues/69),
held behind gates because a Galaxy credential on the organization makes *every*
project sync depend on the hub being complete.

It is already known to be incomplete. `--audit-pins` compares
`collections/requirements.yml` against the generated floors, offline:

```
BELOW  ansible.controller  — pinned 4.8.0,          certified floor is >=4.8.2
BELOW  ansible.platform    — pinned 2.7.20260604,   certified floor is >=2.7.20260615
```

Two of ten would not resolve. Nothing is broken today; it would break the day a
credential is attached. That is the entire reason the two are separate issues.
