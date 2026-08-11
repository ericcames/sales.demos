# Demo: OpenShift Virtualization

**Start here.** A customer-facing demo showing a RHEL 9 virtual machine
provisioned by Terraform onto OpenShift Virtualization, registered, configured,
patched and published — one button, about nine minutes, and torn down on a
schedule that night.

| | |
|---|---|
| **Length** | 30 minutes (25 + 5 for questions) |
| **Audience** | Linux and platform sysadmins who want to run their estate with AAP |
| **Reader** | The Ansible pre-sales engineer presenting it |
| **Needs a live environment?** | **No** — every artifact is committed |
| **Status** | Ready to present |

---

## The four documents

| File | Read it when |
|---|---|
| [`run-sheet.md`](run-sheet.md) | **While presenting.** Minute markers, what is on screen, exact commands, recovery moves |
| [`talk-track.md`](talk-track.md) | **While rehearsing.** The narrative and the actual words, beat by beat, with the rendered assets embedded |
| [`architecture.md`](architecture.md) | **When asked "how does that work".** The workflow graph, the object inventory, the timing table |
| [`objections.md`](objections.md) | **Before you go in.** What this audience asks, answered from the code — including the honest "no" answers |

Present from the run sheet. Rehearse from the talk track. The other two are
reference.

---

## The 60-second version

A requester answers two questions — an operating system and a t-shirt size — and
a workflow in Ansible Automation Platform does the rest:

1. **Provision** — Terraform builds the VM on OpenShift Virtualization and
   registers it as a managed host in AAP. The public URL exists immediately and
   correctly returns 503, because there is no web server yet.
2. **Register** — waits for ssh, then attaches the guest to the Red Hat CDN.
   This has to happen before anything else: the boot image ships with no package
   repositories at all.
3. **Configure** — web server, firewall, Cockpit, the demo page, security
   patches. The URL turns 200.
4. **Check** — logs in, gathers facts, caches them in AAP, so the workflow ends
   by proving the machine is genuinely reachable rather than that the tasks ran.

That night, a scheduled teardown destroys the VM and deregisters it — while
deliberately preserving the expensive things.

**What the demo is actually about** is not speed. It is that provisioning,
configuration, patching and decommissioning are one artifact, in version
control, in public, that converges instead of merely running.

---

## Why it works without a cluster

Both guest-facing artifacts are Jinja templates, so they render on a laptop with
nothing running. `utilities/render-demo-assets.py` renders the demo page and
screenshots it with headless Chrome, and prints the two login banners and
`facts.json` as text:

```bash
python3 utilities/render-demo-assets.py
```

That writes [`docs/images/demo-page.png`](../../images/demo-page.png), which is
committed. **It is rendered from the template, not photographed from a live
run** — accurate, but say so if anyone asks.

The AAP interface cannot be rendered, so the workflow is a Mermaid graph and the
survey is a table in [`architecture.md`](architecture.md). The run sheet ends
with a short list of screenshots worth capturing next time an environment is up.

---

## If you want to run it live

Two things, in order:

```bash
/ocpvirt-new-env      # proves the environment is warm — builds and times a real VM
/ocpvirt-provision    # or launch "Sales Demos - Build Demo VM" in AAP
```

Then read [Running it live](run-sheet.md#running-it-live) in the run sheet — it
changes three beats and nothing else, and it tells you when to cut back to the
screenshot rather than debug with an audience.

New to this repo? Run `/sales-demos-first-time` first.

---

## Related

- [`../../plan/ocpvirt-demo-plan.md`](../../plan/ocpvirt-demo-plan.md) — why the
  automation is built this way: the research, the decisions, the reversals
- [`../../../ROADMAP.md`](../../../ROADMAP.md) — what is done and what is not
- [`../../../README.md`](../../../README.md) — the repo itself
