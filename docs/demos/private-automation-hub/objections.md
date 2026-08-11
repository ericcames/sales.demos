# Objections — Private Automation Hub

What this audience actually asks, answered from the code. Including the answers
that are "no".

---

## "We already install collections straight from Galaxy. Why would we run a hub?"

You already run one — it ships with your AAP subscription. The question is
whether it is populated.

The real argument is not caching. It is that `ansible-galaxy install
community.general` on a production box resolves whatever is newest at that
moment, from the internet, unreviewed. Nobody would accept that for RPMs. A hub
is the same thing package repositories have been for twenty years: a place where
somebody decided what is allowed.

**Do not lead with "it's faster."** It is, but that is the least durable claim
you can make and they will discount it.

---

## "What is wrong with configuring it in the UI? It worked."

Nothing is wrong with it, and that is worth saying plainly — they clicked because
Red Hat shipped a UI.

The gap is the *record*. After the UI change, four questions have no answer:
what exactly changed, who approved it, how do I put it back, and is the DR hub
the same. None of those are hard questions; there is simply nothing that wrote
down what happened.

Then the practical version: **"how do you make your dev, test, and DR hubs
match?"** In the UI the answer is a person being careful three more times.

---

## "Where are the credentials? That repo is public."

Not in it. Three different things get called "token" here and none of them are
committed:

- The **Red Hat offline token** that syncs certified content lives in
  `~/.ansible.cfg` on the laptop, and nowhere else.
- **Your hub's own API token** is not stored at all — the automation
  authenticates with a username and password that come from the vault.
- A **galaxy.ansible.com token** is not needed; reading public collections is
  anonymous.

CI fails the build on a private key, an AWS key, a GitHub token, or a
`secrets.yml` that is not vault-encrypted. See `utilities/check-no-secrets.sh`.

---

## "How long does the sync take?"

**Measured 4.4 minutes** for all three repositories — 214 certified, 47
validated, 15 community — on a sandbox where certified and validated started
empty.

That is the version window paying for itself. Without it you are pulling every
version ever published of all 276, which is the half-hour-plus answer people
expect. Treat 4.4 as a floor rather than a promise: a genuinely cold cluster on a
slow link will take longer, which is why the playbook allows ninety minutes
before it gives up.

**Sync the day before a demo.** Nobody wants to watch a progress bar, and the
interesting parts — the re-run and the convergence — need a *populated* hub, not
a syncing one.

---

## "What happens when that Red Hat token expires?"

It fails quietly, which is worse than failing loudly, so it is worth knowing the
signature: the sync **authenticates fine and returns zero collections**. Green
run, empty hub.

Offline tokens die after 30 days of non-use and are invalidated the moment you
regenerate one on the portal. The error, when you dig it out of Pulp, is
`invalid_grant: Offline user session not found`.

**This happened during the build of this demo**, which is why both the playbook
and the refresh script assert on the token before doing anything, and why the
refusal message names the console URL.

---

## "If I delete a line from that file, does the collection leave the hub?"

**No, and this is the most important limitation to be straight about.** A Pulp
sync is *additive*. It pulls what the requirements file asks for; it never removes
what is already in the repository.

Tested directly: dropped a collection from the community requirements file,
re-synced, and the repository still held all 15.

So the file is an **allowlist for what gets pulled in**, not a full declaration of
desired state. Adding to it works. Changing a version adds the new one and keeps
the old. Removing from it does nothing at all.

The same root cause explains why the `>=` version floor only ever widens — a sync
never subtracts.

**But there is a fourth repository, and in that one it does work.** `approved`
has no remote at all. Its contents are put there by copying collection versions
in, so they can be copied out again — delete a line from
`hub/approved-collections.yml`, run `playbooks/curate_hub.yml`, and the
collection leaves.

Demonstrated live: dropped `cloud.terraform`, re-ran, repository went 9 → 8.

So the honest framing is that the hub holds two *kinds* of repository:

| | The three mirrors | The curated repository |
|---|---|---|
| Contents decided by | upstream, filtered by a requirements file | you |
| Adding | works | works |
| **Removing** | **does nothing** | **works** |
| What it is for | having the content | governing it |
| Point your teams at it? | no | **yes** |

> "These three are mirrors — Red Hat and the community decide what is in them,
> and I filter. That one is mine. It contains what we approved, and when we
> un-approve something it actually leaves."

---

## "Should the community repo be in the approved pipeline?"

No — and none of the three sync repositories are, on a stock install. Only
`published` carries `pipeline: approved`, with `staging` and `rejected` carrying
theirs.

Relabelling `community` as approved would not do the thing people are reaching
for. It does not give you removal, and it makes a repository whose contents a
*sync* manages into a destination for *upload* approvals — two different
lifecycles landing in one bucket.

`published` is not the answer either. That is where `ansible-galaxy publish`
sends collections you author, and where the staging approval workflow puts them.
Mirrored upstream content does not belong in it.

What this hub does instead is a **separate `approved` repository with no remote**,
reconciled from `hub/approved-collections.yml`. See the answer above — that is
the one that gives you removal.

---

## "Can I keep every version of everything?"

Yes — `--certified-versions 0` — and you probably do not want to. Some certified
collections have forty published versions; the full history is a lot of sync time
and a lot of disk for versions nobody will install.

The default keeps the three newest of each. Three rather than one because a
customer playbook pinned to a slightly older certified version still has to
resolve.

**Be straight about the limitation:** the floor only ever *widens*. Re-running
the refresh raises it so future syncs pull less, but versions already in the
repository stay there until orphan cleanup. The window caps what arrives, not
what is already there.

---

## "Why isn't there a 'keep 3 versions' checkbox?"

Because Pulp does not have one. Ask for a collection by name and you get every
version ever published.

`retain_repo_versions` looks like the answer and is not — it prunes repository
snapshots, not collection versions. The window has to be expressed as a version
floor per collection, which is why there is a generated file rather than a
setting.

---

## "Will collections install from the hub with their dependencies?"

Only if the dependencies are also in your lists. `sync_dependencies` is off on
all three remotes.

That is a real limitation and it was not a free choice. With dependency
resolution on, the certified sync failed outright on a 404 for
`containers.podman` — a collection that is in neither list, pulled in by
something that depends on it, and not present in the repository Pulp went looking
in. **One unresolvable dependency fails the whole sync**, so the hub stays empty.

Off, the list is genuinely the boundary. If you need a dependency, add it.

---

## "Are the collections signed?"

**The Red Hat ones arrive signed, yes.** Checked directly against the hub:
`kubernetes.core` and `infra.aap_configuration` both report `signatures: 1`. Red
Hat signs certified and validated content and the signature comes across with the
sync.

What is *not* switched on here is three separate things, and it is worth keeping
them apart:

| Setting | State | What it would do |
|---|---|---|
| `signed_only` on each remote | `false` | Refuse to sync anything unsigned |
| `GALAXY_REQUIRE_SIGNATURE_FOR_APPROVAL` | `false` | Refuse to approve unsigned uploads |
| `GALAXY_AUTO_SIGN_COLLECTIONS` | `false` | Sign collections *you* publish, with your own key |

So the honest answer is "Red Hat's content is signed and you are getting those
signatures; this hub does not yet *enforce* signing, and it cannot sign your own
content because no signing key is configured."

Turning `signed_only` on without thinking is the trap — anything unsigned then
silently stops syncing, and the run still reports success. For a customer's
security team this is a real conversation, not a gap to paper over.

---

## "Doesn't synced content need approving first?"

**No.** This surprises people, because `GALAXY_REQUIRE_CONTENT_APPROVAL` is `true`
on this hub and that sounds like it should gate everything.

It gates the **upload** pipeline: a collection you publish to your own namespace
lands in `staging` and waits for someone to approve it into `published`. Content
pulled by a *remote* goes straight into that remote's repository —
`rh-certified`, `validated`, `community` — and is installable immediately.

Verified: `staging` holds zero collections after a full sync, and a certified
artifact downloads on request.

The distinction is worth drawing out, because it is the interesting half of the
governance story: **approval is for content you author; the requirements file is
your control over content you consume.** They are different problems and the hub
treats them differently.

---

## "So AAP now installs its collections from your hub?"

**Not yet, and deliberately — but the blocker is gone.** No organization has a
Galaxy credential, so nothing in AAP resolves from this hub today.

The reason for the caution is worth giving in full. A Galaxy credential on the
organization makes *every* project sync depend on the hub being complete, and if
one collection is missing every job template breaks.

It genuinely was incomplete. Two of the nine collections this repo pins sat
*below* the certified 3-version window, so they were not in the hub at all:

```
BELOW  ansible.controller  — pinned 4.8.0,        floor >=4.8.2
BELOW  ansible.platform    — pinned 2.7.20260604, floor >=2.7.20260615
```

Found by writing an offline check (`--audit-pins`), not by having it fail in
front of a customer — and then found *again*, for real, when the first attempt
to build the curated repository refused to proceed because that exact version
was missing.

The fix: the generator now lowers a version floor to any version this repo has
pinned. Cost, two extra versions across the whole hub. `--audit-pins` now reports
**"Every pinned collection is inside its window."**

**And this is what the curated repository is for.** When AAP is pointed at a hub,
it should be pointed at `approved` — nine collections at exactly the versions
this repo declares — not at a mirror whose contents Red Hat and the community
control. Tracked as [#69](https://github.com/ericcames/sales.demos/issues/69).

**This answer lands better than a yes would.** It shows the failure mode was
found deliberately, twice, and closed.

---

## "Could we do this for our container images too?"

Yes, and this repo already does — the execution environment is mirrored into the
same hub from quay.io. See `inventory/group_vars/aap/hub_ee_registries.yml` and
`hub_ee_repositories.yml`. Same idea, different object type.

---

## Questions to ask *them*

- **"Where does the record of your last hub change live right now?"** The
  strongest question in the deck. Usually the answer is a person.
- "How do you know your DR hub matches production?"
- "If someone installed a collection from Galaxy onto a production box this
  morning, would you know?"
- "Who decides which community collections are allowed?"
- "What happens when the person who set up your hub leaves?"

---

## Things not to say

- **"ClickOps is bad."** They clicked because there is a UI. The point is the
  missing record, not their judgement.
- **"This is faster."** True and forgettable. Reviewability is the argument.
- **"You get all of Galaxy."** You get exactly what is in the file — that is the
  feature.
- **Anything implying AAP is already pulling from the hub.** It is not, and the
  reason it is not is a better story than the claim.
- **"It just works."** It expired mid-build. Say that instead.
