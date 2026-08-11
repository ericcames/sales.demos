# Demo documentation

Talk tracks for the demos in this repo. One directory per use case, each with
the same five documents.

**These are written for the pre-sales engineer presenting**, not for the person
building the automation. For *why* something is built the way it is, read
[`docs/plan/`](../plan/). Different readers, different lifecycles.

---

## Use cases

| Use case | Audience | Length | Status |
|---|---|---|---|
| [OpenShift Virtualization](openshift-virtualization/) | Linux / platform sysadmins | 30 min | **Ready** |
| Private Automation Hub — ClickOps vs. configuration-as-code | Sysadmins and automation leads | TBD | Not written |

---

## What a use-case directory contains

Copy [`_template/`](_template/) and fill it in. Five files, each with one job:

| File | Layer | Job |
|---|---|---|
| `README.md` | — | What the demo proves, who it is for, the 60-second version, links to the rest |
| `run-sheet.md` | **live** | The page you hold while presenting. Minute markers, what is on screen, exact commands, recovery moves |
| `talk-track.md` | **rehearsal** | The narrative: the actual words per beat, the framing, the transitions |
| `architecture.md` | reference | The moving parts, the timing table, the object inventory |
| `objections.md` | reference | What this audience asks, answered from the code — including the honest "no" answers |

**Two layers on purpose.** The run sheet is scannable under pressure with an
audience waiting. The talk track is prose you read once the week before. Trying
to make one document do both produces something too long to present from and too
terse to learn from.

---

## The rules these follow

**Every claim must be checkable in this repo.** Each talk track ends with a
table mapping its claims to the files that back them. If you cannot source a
sentence, cut it.

**Volunteer what does not work.** Every talk track has a beat near the end for
the limitations, delivered before anyone asks. It is consistently the
highest-value ninety seconds in a session — a sysadmin who has sat through demos
where the hard parts were skipped will trust the working parts more once you
have been straight about the broken ones.

**Assume no environment.** A demo cluster expires, a slot moves, a colleague
reads this on a plane. Anything the demo produces that can be rendered without
infrastructure should be rendered and committed — see
`utilities/render-demo-assets.py` for how the OpenShift Virtualization page and
login banners are generated from the same templates the guests serve.

**Name the personas separately.** The *reader* is the pre-sales engineer; the
*audience* is the customer. They want different things from the same demo, and
saying which is which at the top keeps the writing pointed at one of them.

**This repo is public.** No customer names, ever — not in a talk track, not in
an example, not in a screenshot. Demo-platform hostnames are the documented
exception; see [`CLAUDE.md`](../../CLAUDE.md).

---

## Adding a use case

1. `cp -r docs/demos/_template docs/demos/<use-case>`
2. Write `run-sheet.md` first — it forces the arc into a shape that fits the
   slot. Everything else is easier afterwards.
3. Add a row to the table above.
4. If the demo produces an artifact that can be rendered offline, render it and
   commit it to `docs/images/` alongside the script that regenerates it.
