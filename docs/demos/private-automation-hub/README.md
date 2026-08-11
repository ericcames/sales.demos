# Demo: Private Automation Hub — ClickOps vs. configuration-as-code

**Start here.** A customer watches a Private Automation Hub get configured twice —
once by hand in the web UI, once from a file in git — and sees what the second
one can do that the first cannot: show a diff, survive a re-run, and put itself
back when somebody changes it.

| | |
|---|---|
| **Length** | 30 minutes (26 + 4 for questions) |
| **Audience** | Systems administrators and automation leads. Assumes no Private Automation Hub experience whatsoever |
| **Reader** | The Ansible pre-sales engineer presenting it |
| **Needs a live environment?** | **Yes** for the full version. The `git diff` half and every artifact are committed, so a degraded version runs offline |
| **Status** | Draft — community half verified live; certified and validated blocked on a token (see below) |

---

## The five documents

| File | Read it when |
|---|---|
| [`run-sheet.md`](run-sheet.md) | **While presenting.** Minute markers, what is on screen, exact commands, recovery moves |
| [`talk-track.md`](talk-track.md) | **While rehearsing.** The narrative and the actual words, beat by beat |
| [`clickops.md`](clickops.md) | **Before presenting.** The full click-by-click for the manual half, every field value |
| [`architecture.md`](architecture.md) | **When asked "how does that work".** The three tokens, the object inventory, the timing |
| [`objections.md`](objections.md) | **Before you go in.** What this audience asks, answered from the code |

Present from the run sheet. Rehearse from the talk track. The other three are
reference.

> **Six files, not the template's five.** `clickops.md` is a deliberate addition.
> The run sheet has to stay scannable by someone standing up mid-sentence, and a
> thirty-click UI walkthrough with every field value would swamp it. `clickops.md`
> is reference the run sheet cites — the same relationship `architecture.md`
> already has to it.

---

## The 60-second version

1. Open a Private Automation Hub that ships with every AAP subscription. It is
   **empty**, which is how nearly every install looks.
2. Configure the `community` remote **by hand in the UI**. Six fields, two
   screens, four minutes. Then: *"now do that in your other three hubs."*
3. Ask four questions the UI cannot answer — what changed, who approved it, how
   do I revert, is DR the same?
4. Show the same three remotes as **a file in git**, and the collection list as a
   second file. Run one playbook. Same result.
5. **Run it again** — `changed=0`. **Change it in the UI and run again** — it
   converges back.
6. Show what landed: 214 certified and 47 validated collections at three versions
   each, 15 community collections at exactly one.

**What the demo is actually about** is not automation and not speed. It is that
a hub's contents are a *supply chain*, and a supply chain you cannot review is
one you are trusting from memory. The re-run that silently undoes a UI change is
the argument; everything else is setup.

---

## Why it needs an environment, and what survives without one

The committed artifacts — `hub/certified-requirements.yml`,
`hub/validated-requirements.yml`, `hub/community-requirements.yml`, and the two
`inventory/group_vars/aap/hub_collection_*.yml` files — carry the whole
config-as-code half. `git log` and `git diff` over `hub/` work on a plane.

**What genuinely needs a cluster** is the contrast: the UI dialog, the populated
repository counts, and the convergence beat. Without one, present from
[`architecture.md`](architecture.md) and say plainly that you are describing
rather than showing.

---

## If you want to run it live

```bash
# Preflight, then populate. Measured 4.4 minutes on sandbox.
ansible-playbook playbooks/sync_hub.yml -i inventory --limit sandbox \
  -e target_env=sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

Or use the [`pah-sync`](../../../.claude/skills/pah-sync/SKILL.md) skill, which
runs the preflight checks first and then verifies against the hub.

**Sync the day before.** The demo shows a populated hub and a re-run; nobody
wants to watch a cold sync.

### Verified against the live sandbox

| Repository | Collections | Assertion |
|---|---|---|
| `rh-certified` | **214** | version window applied — sampled collections carry 3 versions, not 30 |
| `validated` | **47** | same |
| `community` | **15** | **15/15 at exactly their pinned version and no other** |

`ok=56, changed=6, failed=0`. All three repositories populated in **264 seconds**.

Two things went wrong on the way, and both are now demo material rather than
defects:

- **The offline token expired mid-build** (`invalid_grant: Offline user session
  not found`) — the exact quiet failure the honest-bits beat describes.
- **Dependency resolution failed the whole sync** on a 404 for a collection in
  neither list. `sync_dependencies` is now off everywhere.

What is still missing before this moves from Draft to Ready: **screenshots**
(`docs/images/pah-*.png`) and one rehearsal of the convergence beat.

---

## Related

- [`docs/plan/pah-plan.md`](../../plan/pah-plan.md) — why it is built this way
- [#68](https://github.com/ericcames/sales.demos/issues/68) — this use case
- [#69](https://github.com/ericcames/sales.demos/issues/69) — pointing AAP *at*
  the hub, deliberately deferred
