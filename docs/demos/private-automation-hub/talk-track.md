# Talk track — Private Automation Hub

**Rehearse from this, present from [`run-sheet.md`](run-sheet.md).** This is the
narrative and the actual words; the run sheet is the scannable version.

The argument, in one line: **a hub's contents are a supply chain, and a supply
chain you cannot review is one you are trusting from memory.**

---

## Beat 1 · The hub you already own (0–3)

*On screen: PAH Repositories, all zeroes.*

> "Before I show you anything, I want to check something. Hands up — who here is
> running a private automation hub today?"

*Usually a few hands.*

> "Keep them up if it has content in it."
>
> "Right. So here is mine."

*Point at the zeroes.*

> "This is not a demo environment I broke on purpose. This ships with every AAP
> subscription, and this is what it looks like on nearly every install I walk
> into. You are all paying for this and most of you are not using it."

Then the stake, before any tooling:

> "Second question. Who here has run `ansible-galaxy install community.general`
> on a box that matters?"
>
> *(pause)*
>
> "So did I, for years. Think about what that actually does. It goes out to the
> internet, takes whatever is newest at that second, and puts it on your server.
> Nobody reviewed it. Nobody pinned it. You would never accept that for an RPM —
> you have had a package repository for twenty years precisely so somebody
> decides what is allowed. This is the same problem, and this is the same
> answer."

**Do not say "and it's faster."** True, forgettable, and it invites a
benchmarking argument you do not want.

---

## Beat 2 · ClickOps (3–10)

*On screen: Remotes → community → Edit.*

> "So let's fill it. I am going to do this the way the product expects — in the
> UI. And I want to be clear up front: there is nothing wrong with this. Red Hat
> shipped a web interface. Using it is not a character flaw."

Work through the dialog. Narrate the fields you *skip*, not just the ones you
fill:

> "Proxy URL — blank here, but most of you need it. That is three more fields.
> TLS validation, on. Client certificate, blank; if you were pointing at an
> internal mirror with mutual TLS it goes here."

At the requirements file, slow down:

> "Here is the interesting one. Fifteen collections, and every one has a version
> next to it. People always ask why I did not just list the names."
>
> "Because there is no 'give me the newest three' setting. There is no checkbox.
> Ask for a collection by name and Pulp gives you every version ever published —
> some of these have forty. The only way to bound it is to say which ones you
> want."

Set rate limit to `8` and flag it — you will come back to it:

> "Rate limit, eight. Remember that number."

Save. Sync. Then the count, out loud:

> "One remote. Six fields. Two screens. Four minutes. And honestly? That was
> fine."

*Beat.*

> "Now do it in dev. And test. And the DR site. Identically."

---

## Beat 3 · Four questions (10–14)

*Nothing on screen. This beat is you talking to them.*

> "I want to ask four questions about what I just did. None of them are hard."

Deliver these slowly, and **let each one sit**:

> "One. What exactly did I change? Not 'the community remote' — which fields,
> from what value, to what value."
>
> "Two. Who approved it?"
>
> "Three. It is nine months from now and something is broken. How do I put it
> back?"
>
> "Four. Is the DR hub the same as this one?"

*Pause properly here.*

> "I cannot answer any of those. Not because the UI is bad — because nothing
> wrote down what I did. The change happened, it worked, and it left no trace."

**The turn:**

> "That is the whole thing. It is not that clicking is slow. It is that clicking
> does not leave a record, and everything you actually need six months from now
> is in the record."

---

## Beat 4 · As code (14–22)

*On screen: `hub_collection_remotes.yml`.*

> "Same three remotes. Same fields — URL, auth, TLS, rate limit. This file is
> that dialog I just filled in."

*Then `hub/community-requirements.yml`.*

> "And this is the list. Fifteen collections, one version each."

```bash
git log --oneline -3 -- hub/
git diff HEAD~1 -- hub/community-requirements.yml
```

> "There is question one, and there is question two. What changed, and who
> approved it. It is a pull request. Somebody reviewed this."

Run it. While it runs, keep talking — do not narrate the scrollback.

### 4a · Run it again

> "Now watch this. I am going to run exactly the same thing again."

*Point at the `community` remote: `changed=false`.*

> "Nothing to do. And that is not a cache — it went and read the hub, compared it
> against the file, and found they already match. That is what idempotent means,
> and it is why you can run this on a schedule and stop thinking about it."

**Be precise here, because the recap says `changed=2`.** Do not gloss it —
somebody is reading the screen and you lose them if the number contradicts you:

> "You will notice two of the three do report a change. That is the certified and
> validated remotes, and it happens every single run. They carry a Red Hat token,
> and the API will not hand a token back to me — so the module has nothing to
> compare against and rewrites it every time."
>
> "That is the platform refusing to leak a secret, which is the behaviour you
> want. The community remote has no credential, and that one is genuinely
> unchanged."

*This is a better moment than it looks.* You have just been caught out by your
own screen and had an answer ready — and the answer is "the platform protects
credentials." Rooms remember that.

### 4b · Break it

**This is the beat that wins the room. Rehearse it.**

> "But you are all thinking the same thing, which is: fine, until somebody goes
> into the UI at 2am."

*Switch to the UI. Set the community remote's rate limit to `99`. Save. Show it
saved.*

> "So somebody did. Maybe they were debugging. Maybe they had a reason. They
> definitely did not tell anyone."

*Re-run the playbook. Go back to the UI. Refresh.*

> "Eight."

*Let that land before you explain it.*

**Point at the recap while it is still on screen.** Community moved from
`changed=false` a minute ago to `changed=true` on this run:

> "And look — that third remote reported a change this time, when it did not
> before. That number is not decoration. It is telling you something drifted and
> got put back."

> "Nobody had to notice. Nobody had to remember what it used to be. The file is
> what it is supposed to be, and running it makes reality match. That is question
> three and question four, and it is the same answer to both."

---

## Beat 5 · What is in there (22–26)

*On screen: Repositories, populated.*

> "Certified: two hundred and fourteen collections — that is everything Red Hat
> ships you. Validated: forty-seven. Community: fifteen, and those fifteen are
> ones I chose."

On the window:

> "Certified and validated keep the three newest versions of each. Not one —
> three. Because one of you has a playbook pinned to a slightly older certified
> version, and it still has to install."

```bash
python3 utilities/refresh-hub-requirements.py
git diff hub/
```

> "That takes twenty-five seconds and it re-reads every version from Red Hat and
> Galaxy. And that diff right there is a month of upstream releases, as a pull
> request you can actually review before it lands in your hub."

---

## Beat 6 · The honest bits (26–28)

**Volunteer every one of these. Do not wait to be asked.** This is consistently
the highest-value ninety seconds in the session.

> "Four things that are not great, and you should hear them from me."
>
> "One — the sync is not instant. Four and a half minutes for all 276
> collections, and longer on a cold cluster or a slow link. I still run it the
> day before, because four minutes of progress bar is four minutes you are not
> talking."
>
> "Two — that Red Hat token expires, and it fails *quietly*. It does not throw an
> auth error. It authenticates, returns zero collections, and leaves you a green
> run and an empty hub. I know that because it expired on me while I was building
> this. That is why the playbook now refuses to start without checking it."
>
> "Three — the version window only ever tightens going forward. It bounds what
> arrives; it does not go back and delete what is already there."
>
> "Four — dependency resolution is off. If a collection needs something that is
> not in my list, it will not install from this hub alone. That was not a design
> choice I am proud of — I turned it on, and the first sync died on a 404 for a
> collection that was not in the list. One bad dependency fails the whole sync."

Then the one they will ask anyway, so get ahead of it:

> "And the big one — AAP is not pulling its collections from this hub yet. On
> purpose. The moment you attach a Galaxy credential to the organization, every
> project sync depends on that hub being complete, and if one collection is
> missing every job template breaks."
>
> "I already know mine is incomplete. Two of the ten collections this repo pins
> are below the version window. I found that by writing a check that runs
> offline, not by having it blow up in front of you."

---

## Beat 7 · Landing it (28–30)

> "You already own a private automation hub. That was never the question. The
> question is whether what is in it is something you can review, or something
> somebody has to remember."

*Then hand it to them:*

> "So — where does the record of your last hub change live right now?"

**Stop talking.** The answer is usually "a person", and they will say it
themselves.

---

## If you only get ten minutes

Beat 1 (90 seconds, cut the second question), then Beat 2 abbreviated — open the
dialog, do not fill it — then **Beat 4b in full**. The UI change and the re-run
that undoes it is the entire argument compressed into two minutes. Close with
Beat 7.

Cut Beat 5 first. The content inventory is the least portable part.

---

## Where the words come from

| Claim | Backed by |
|---|---|
| "Ships with every AAP subscription" | `hub_ee_registries.yml` header — PAH verified deployed on this platform |
| "No 'newest three' setting" | `utilities/refresh-hub-requirements.py` docstring; `collection_remote.py:221-231` |
| "`retain_repo_versions` is not that control" | `hub_collection_repositories.yml` header |
| "214 certified, 47 validated, 15 community" | `hub/*-requirements.yml`, generated from upstream |
| "Three newest, because a pinned playbook must still resolve" | `docs/plan/pah-plan.md` — the version window |
| "Idempotent, and converges after a UI change" | `playbooks/sync_hub.yml`; verification steps 9–10 |
| "Exactly one version each, and no other" | `sync_hub.yml`'s community pin assert — **verified 15/15 live** |
| "The token fails quietly" | `sync_hub.yml`'s token assert; `invalid_grant` observed during the build |
| "One bad dependency fails the whole sync" | `hub_collection_remotes.yml` — the `containers.podman` 404 |
| "AAP is not pointed at the hub" | No `galaxy_credentials` in `aap_organizations.yml`; [#69](https://github.com/ericcames/sales.demos/issues/69) |
| "Two pinned collections are below the window" | `refresh-hub-requirements.py --audit-pins` |
