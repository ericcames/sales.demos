# Run sheet — Private Automation Hub

**This is the page you hold while presenting.** The narrative behind each beat,
with the actual words, is in [`talk-track.md`](talk-track.md) — rehearse from
that, present from this. The full click-by-click for the ClickOps half is in
[`clickops.md`](clickops.md); keep it open in a second tab.

| | |
|---|---|
| **Length** | 30 minutes (26 + 4 for questions) |
| **Audience** | Systems administrators and automation leads. Assumes no Private Automation Hub experience |
| **Needs an environment?** | **Yes** for the live version. A populated PAH plus the repo. The offline version is in [`architecture.md`](architecture.md) |
| **Assets** | `hub/*-requirements.yml`, `inventory/group_vars/aap/hub_collection_*.yml`, `utilities/refresh-hub-requirements.py`, five images in [`docs/images/`](../../images/) |

---

## Before you start (5 minutes, offline)

Tabs, in order. **This is the slide deck.**

1. **PAH UI** — `https://<aap_hostname>/hub/` → *Collections → Repositories*
2. **PAH UI, second tab** — *Collections → Remotes*, on `community`, Edit dialog open
3. **Terminal**, in the repo, on `main`, clean tree
4. **`hub/community-requirements.yml`** open in an editor
5. **`inventory/group_vars/aap/hub_collection_remotes.yml`** open in an editor
6. [`clickops.md`](clickops.md) open for reference

Sanity check before anyone is watching:

```bash
python3 utilities/refresh-hub-requirements.py --check     # expect "No drift."
python3 utilities/refresh-hub-requirements.py --audit-pins
```

> **Rehearse beat 4.** Changing something in the UI and watching the re-run put
> it back is the beat that wins the room, and it is the only one that can fail
> live. Do it once beforehand.

---

## The arc

| Time | Beat | On screen |
|---|---|---|
| 0–3 | The hub you already own, and it is empty | PAH Repositories, all zeroes |
| 3–10 | **ClickOps.** Configure the community remote by hand | PAH Remotes → Edit |
| 10–14 | Four questions the UI cannot answer | Nothing. Talk to them |
| 14–22 | **As code.** Same result, from git | Editor, then terminal |
| 22–25 | What is actually in there, and what it cost | PAH Repositories, populated |
| 25–26 | **Removal: mirrors cannot, curated can** | Editor + terminal |
| 26–28 | The honest bits | Terminal |
| 28–30 | Landing it | Close |

---

## 0–3 · The hub you already own

**Show:** PAH → *Collections → Repositories*. `rh-certified`, `validated`,
`community`, all **Never synced**.

> "Every one of you with an AAP subscription already has this. It ships with the
> platform. And on nearly every install I see, it looks exactly like this."

Ask the room: **"who here is running a private hub today?"** Then: **"who here
installs collections straight from galaxy.ansible.com onto production boxes?"**

Land the stake before any tooling: *this is your supply chain.*

---

## 3–10 · ClickOps

**Show:** *Collections → Remotes* → `community` → **Edit**.

Do it live. Full field list is in [`clickops.md`](clickops.md).

1. **Requirements file** — paste the 15 collections
2. **Proxy / TLS / auth** — leave alone, *say* you are leaving them alone
3. **Download concurrency**, **rate limit** — set rate limit to `8`
4. **Save**
5. *Repositories* → `community` → **Sync**

**Count out loud.** One remote. Six fields. Two screens.

Then the turn:

> "That took four minutes. Now do it in your dev hub, your test hub, and the DR
> site. And do it the same way."

---

## 10–14 · Four questions

No screen. Just ask, and let them sit.

1. **What exactly did I change?** Not "the community remote" — which fields, from
   what, to what.
2. **Who approved it?**
3. **How do I put it back?**
4. **Is the DR hub the same as this one?**

> "None of these are hard questions. The UI just has no way to answer any of
> them, because nothing wrote down what I did."

**Do not say "ClickOps is bad."** They clicked; the platform shipped a UI. The
point is that the *record* is missing.

---

## 14–22 · As code

**Show:** `inventory/group_vars/aap/hub_collection_remotes.yml`.

> "Same three remotes. Same fields. This file *is* the dialog I just filled in."

Then `hub/community-requirements.yml` — 15 collections, one exact version each.

```bash
git log --oneline -3 -- hub/
git diff HEAD~1 -- hub/community-requirements.yml
```

> "There are your first two questions. What changed, and who approved it."

**Run it:**

```bash
ansible-playbook playbooks/sync_hub.yml -i inventory --limit sandbox \
  -e target_env=sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

While it runs, walk the file. **Then the two moves that matter:**

**Run it again.** The `community` remote reports `changed=false`.

> "That is not caching. It read the hub, compared it to the file, and found they
> already match."

⚠️ **The recap says `changed=2`, not 0. Say why before anyone asks** — certified
and validated carry a token, the API never returns a token, so the module has
nothing to compare and rewrites those two every run. *"The platform refusing to
leak a secret."* Community has no credential and is genuinely unchanged.

**Break it.** In the UI, set the community remote's rate limit to `99`. Save.
Re-run. Open the UI: back to `8`.

> "Nobody had to notice. That is question three, and question four."

---

## 22–26 · What is in there

**Show:** PAH → Repositories, populated.

| Repository | Collections | Versions each |
|---|---|---|
| `rh-certified` | 214 | 3 newest |
| `validated` | 47 | 3 newest |
| `community` | 15 | current only |

> "Certified and validated is everything Red Hat ships. Community is fifteen
> collections I chose."

**The version window is the part worth dwelling on.**

> "Pulp has no 'keep the newest three' setting. Ask for a collection by name and
> you get every version ever published — some of these have forty. So the file
> carries a floor per collection, and a script regenerates it."

```bash
python3 utilities/refresh-hub-requirements.py
git diff hub/
```

> "That diff is a month of Red Hat releases, as a pull request."

---

## 25–26 · The part a mirror cannot do

**Rehearse this one too.** It looks like a failure for about five seconds, which
is the point.

```bash
# 1. delete any line from hub/community-requirements.yml, then:
ansible-playbook playbooks/sync_hub.yml -i inventory --limit sandbox \
  -e target_env=sandbox --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

Count is **still 15**. Say why before anyone thinks it is broken:

> "A sync is additive. It never removes. These three files are an allowlist for
> what comes in, not a description of what is in there."

Then the fourth repository:

```bash
# 2. delete a line from hub/approved-collections.yml, then:
ansible-playbook playbooks/curate_hub.yml -i inventory --limit sandbox \
  -e target_env=sandbox --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

**9 → 8.** Gone.

> "Mirrors: you control what comes in. Curated: you control what is in. Your
> teams point at the second one."

---

## 26–28 · The honest bits

Volunteer all of it. Do not wait to be asked.

- **The sync is not instant.** 4.4 minutes measured for all 276 collections; longer on a cold cluster.
- **The token expires** after 30 days of non-use — and it fails *quietly*. It
  authenticates and returns zero collections. Green run, empty hub.
- **The window only widens.** Re-running raises the floor for future syncs; it
  does not remove what is already there.
- **No signing.** `signed_only: false`. Configurable, not configured here.
- **AAP is not pointed at this hub yet** — deliberately, and two of the nine
  collections this repo pins are already outside the window. `--audit-pins`
  finds it offline, before it breaks anything.

> "That last one I found by writing the check, not by having it blow up in a
> demo."

---

## 28–30 · Landing it

> "You already own a private hub. The question was never whether to run one — it
> is whether its contents are something you can review, or something you have to
> remember."

Ask: **"where does the record of your last hub change live right now?"**

---

## Running it live

```bash
# Populate an environment (measured 4.4 min on sandbox)
ansible-playbook playbooks/sync_hub.yml -i inventory --limit sandbox \
  -e target_env=sandbox --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

Or use the [`pah-sync`](../../../.claude/skills/pah-sync/SKILL.md) skill, which
runs the preflight first.

**Sync the day before, not on the day.** The demo shows a *populated* hub and a
*re-run*; nobody wants to watch a cold sync.

### Recovery moves

| It breaks | Do this |
|---|---|
| Sync is slow / still running | Skip to beat 4's re-run. The `changed=0` and convergence moves need no sync |
| Hub empty, run green | The offline token expired. Say so out loud — it is on your honest-bits list anyway |
| Re-run shows unexpected `changed` | Someone edited the UI. **This is the demo.** Show it converging |
| No environment at all | Present from [`architecture.md`](architecture.md) and the committed `hub/` files. The `git diff` half needs no cluster |

---

## Screenshots

Captured from the live sandbox and demo environments, committed in `docs/images/`:

1. `docs/images/pah-repositories-empty.png` — Repositories, never synced (demo env)
2. `docs/images/pah-repositories-populated.png` — Repositories, populated with `approved` (sandbox env)
3. `docs/images/pah-remote-community.png` — Edit community remote dialog
4. `docs/images/pah-remote-certified.png` — Edit rh-certified remote dialog
5. `docs/images/pah-remote-validated.png` — Edit validated remote dialog
