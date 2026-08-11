# Run sheet — OpenShift Virtualization

**This is the page you hold while presenting.** Thirty minutes, no cluster
required. The narrative behind each beat, with the actual words, is in
[`talk-track.md`](talk-track.md) — rehearse from that, present from this.

| | |
|---|---|
| **Length** | 30 minutes (25 + 5 for questions) |
| **Audience** | Linux/platform sysadmins who want to run their estate with AAP |
| **Needs an environment?** | **No.** Every artifact below is in this repo |
| **Assets** | [`demo-page.png`](../../images/demo-page.png), the two banners and `facts.json` in [`talk-track.md`](talk-track.md), the Mermaid graph in [`architecture.md`](architecture.md) |

---

## Before you start (5 minutes, offline)

1. Open these four in tabs, in this order — this **is** your slide deck:
   1. `docs/images/demo-page.png`
   2. `docs/demos/openshift-virtualization/architecture.md` (the workflow graph)
   3. `inventory/group_vars/aap/controller_workflows.yml`
   4. `https://github.com/ericcames/sales.demos`
2. Have `talk-track.md` open on a second screen if you have one.
3. Decide your close before you begin — see **Landing it** at the bottom.

If you *do* have a live environment, read **[Running it live](#running-it-live)**
first; it changes three beats and nothing else.

---

## The arc

| Time | Beat | On screen |
|---|---|---|
| 0–3 | Cold open — the destination | `demo-page.png` |
| 3–6 | The problem, in their words | nothing |
| 6–8 | The whole interface is two questions | the survey table below |
| 8–16 | What happens behind the button | the workflow graph |
| 16–22 | What you get | `demo-page.png`, MOTD, `facts.json` |
| 22–26 | Why a sysadmin should care | the repo |
| 26–28 | The honest bits | nothing |
| 28–30 | Close | the page footer |

---

## 0–3 · Cold open on the destination

**Show `demo-page.png` before you say anything about how it got there.**

Point at three things and nothing else:

- the hostname and the green dot — *"that's a RHEL 9 guest"*
- **Size tier** `small-1cpu-2gb → sd1.small` — *"somebody asked for 'small'"*
- the amber notice — *"and it deletes itself at 6 PM"*

> **"This machine did not exist nine minutes before that screenshot was taken.
> Nobody opened a hypervisor console, nobody allocated an IP, and nobody
> logged into it. Let me show you what did happen."**

Then **rewind**.

---

## 3–6 · The problem

No screen. Ask, then shut up and let them answer:

> **"Walk me through what happens today when a developer asks you for a VM."**

Their answer is your outline for the rest of the session. Listen for: the
ticket, the hand-off between teams, who owns the IP, when it gets patched,
and — the one nobody volunteers — **who deletes it afterwards**.

Reflect it back, then:

> **"Every one of those steps is somebody's judgment call, which is why no two
> of your machines are quite the same. The demo isn't 'we made VMs faster'. It's
> that the judgment calls got written down once."**

---

## 6–8 · The entire interface is two questions

Show the survey. This is the whole thing a requester sees:

| Question | Variable | Choices | Default |
|---|---|---|---|
| Operating system | `os_type` | `linux` · `windows` · `both` | `linux` |
| VM size tier | `vm_size_tier` | `small-1cpu-2gb` · `medium-1cpu-4gb` · `large-2cpu-6gb` | `small-1cpu-2gb` |

Source: `inventory/group_vars/aap/controller_workflows.yml:36-64`.

**Land the question that is deliberately missing.** There is no dropdown for
*which environment* — that is set per-controller from `connection.yml`:

> **"A dropdown for the target environment is one mis-click away from
> provisioning into the cluster you show customers. So it isn't a dropdown. The
> template in each controller is pointed at itself, and the playbook fails
> closed if the two ever disagree."**

That single design decision usually buys you more credibility with a sysadmin
than the rest of the demo combined.

---

## 8–16 · What happens behind the button

Show the workflow graph from [`architecture.md`](architecture.md). Four nodes,
chained on success:

```
Provision VM  →  Register VMs  →  Configure VMs  →  Check VMs
```

Walk them in order. **Three beats matter here; everything else is detail.**

### Beat 1 — the Route 503s, and that is correct

> **"The second Terraform finishes, the URL exists and returns 503. That is not
> a bug — there is no web server yet. Infrastructure and configuration are two
> different jobs with two different failure modes, and this demo keeps them
> visibly separate."**

```
curl -sI $(terraform output -raw web_url) | head -1
HTTP/1.1 503 Service Unavailable     # after provision
HTTP/1.1 200 OK                      # after configure
```

### Beat 2 — the ordering you would not guess

> **"Register has to run before configure. Not for tidiness — the RHEL 9 boot
> image that OpenShift Virtualization ships has no package repositories at all.
> Every single `dnf` task fails on an unregistered guest. That's a five-minute
> debugging session the first time, and it's the entire reason this is one
> workflow instead of three buttons somebody launches in the wrong order at
> 9 a.m. in front of a customer."**

Source: `controller_workflows.yml:10-14`.

### Beat 3 — three different definitions of "done"

Draw this out loud; it is the most senior-sounding thing in the deck:

| "Done" | When |
|---|---|
| `terraform apply` returns | ~10 s |
| VM reports `Running` | ~45 s |
| sshd actually accepts a connection | ~1 more minute |

> **"Three different answers to 'is it ready'. A human learns that by getting
> Connection refused twice. The workflow just waits — the gate lives in the
> playbook, so it protects the by-hand path too."**

**Whole workflow: about nine minutes.** Say the number. Do not round it down.

---

## 16–22 · What you get

Back to `demo-page.png`. Now walk the facts table and make the point that
**every value on that page came from the machine itself**:

- OS, kernel, vCPU/memory — gathered facts
- `small-1cpu-2gb → sd1.small` — the tier they asked for, resolved to the
  cluster instance type that served it
- **In-cluster address** — *"that's how AAP reached it. Plain ssh on 22, no
  bastion, no jump host, no agent."*

Then the three supporting artifacts, in this order:

**1. `facts.json`** — *"same data, curl-able, for the person who asks where the
page is getting it from."* (Full output in [`talk-track.md`](talk-track.md).)

**2. The login banners.** Show both, and make the contrast the point:

> **"Before you authenticate you get the legal notice — no branding, no product
> names, no URL, because you haven't proved who you are yet. After you
> authenticate you get this."**

Show the ASCII art. Let them enjoy the cow. Then:

> **"'This host is managed by AAP. Manual changes may be reverted.' That line is
> the whole operating model, printed where somebody about to do something manual
> will actually read it."**

**3. Cockpit** — installed and firewalled open on every guest. *"Because the
answer to 'what if I just need to look at the box' should be yes."*

---

## 22–26 · Why a sysadmin should care

Switch to the repo. Do not tour it — land four things:

1. **It is idempotent.** Re-running the CNV install reports `changed=0`. *"This
   is a converger, not a script that assumes it's going first."*
2. **The guardrails are in code, not in a wiki.** Ask for more memory than the
   node has and `terraform plan` **fails**. It does not leave you a `Pending` VM
   and a green checkmark. (`terraform/ocpvirt/locals.tf`)
3. **One implementation, two front doors.** The same playbook runs from a job
   template *and* from a laptop. The survey variable names, the skill's prompts,
   and the Terraform variables are literally the same strings — that is the
   contract.
4. **It cleans up after itself.** Nightly teardown at 6 PM America/Phoenix, on a
   schedule, and teardown deliberately *preserves* the expensive things —
   OpenShift Virtualization itself, the boot sources, the Terraform state.
   *"Cost control is a scheduled job, not a monthly reminder to go look."*

---

## 26–28 · The honest bits

Volunteer these. You will be asked anyway, and answering first is worth more
than answering well.

- **No live migration in this demo.** The lab cluster is a single node. CNV does
  live migration; this environment cannot show it. *"I'd rather tell you that
  than show you a slide about it."*
- **Windows is wired and does not boot yet.** Terraform builds the VM, the
  inventory group exists, WinRM is configured — but Red Hat cannot redistribute
  Windows media, so the golden image is a one-time build that has not been done.
  It is tracked in public as issue #3.
- **`config.yml` always reports `changed`.** AAP returns one setting as
  `$encrypted$` on every read, so Ansible can never see it as converged. Known,
  cosmetic, documented.

---

## 28–30 · Landing it

Point at the footer of the demo page.

> **"That link is on the page the demo just built. Everything you watched —
> the Terraform, the playbooks, the workflow, the survey, the design notes for
> why it's built this way — is in that repository, in public, right now. Nothing
> I showed you is behind a login."**

Then pick **one** close and ask it directly:

- *"What's the first thing in your estate you'd point this at?"*
- *"Who else needs to be in the room the second time we do this?"*
- *"Would it be more useful to see this run live against your requirements?"*

---

## Running it live

If you have a warm environment, three beats change:

| Beat | Live version |
|---|---|
| 0–3 cold open | Launch **`Sales Demos - Build Demo VM`** *first*, then do the cold open on the screenshot while it runs. It needs ~9 minutes and you are about to spend 13 talking |
| 8–16 | Cut to the running job's output instead of the graph. Narrate the node that is actually executing |
| 16–22 | `curl -sI` the real URL, then open it. The 503 → 200 transition live is worth more than any slide |

**Prove the environment before you rely on it.** `/ocpvirt-new-env` builds and
times a real VM in about a minute and fails loudly if the cluster is cold.

**Keep the screenshot open in a tab regardless.** If the run stalls, do not
debug in front of them:

> **"That's a lab cluster doing lab cluster things — here's the run I did
> earlier."**

Cut to the tab and carry on. You lose nothing: the whole talk track is built to
work from the artifacts.

### Recovery moves

| Symptom | Move |
|---|---|
| Job fails on `Error acquiring the state lock` | A cancelled run left a Lease held. Do not debug live — cut to the screenshot. The fix is in `playbooks/tasks/terraform_lock_check.yml` |
| Job fails with a 401, or times out then 401s | The RHDP token expired. Not fixable mid-demo. Cut to the screenshot |
| Register node runs long | Normal — it is 4–5 minutes of the nine. Fill with the "three definitions of done" beat |
| URL still 503 after configure | Check the guest firewall beat: firewalld on the VM is separate from the Route |

---

## Screenshots still worth capturing

The guest-facing artifacts render without a cluster and are committed. The AAP
UI cannot be rendered — grab these next time an environment is up, and this run
sheet stops needing a live cluster for *any* beat:

- [ ] The workflow visualizer showing all four nodes green
- [ ] The survey modal as a requester sees it
- [ ] A completed `Sales Demos - Build Demo VM` job, output pane visible
- [ ] The host detail page in AAP showing cached facts
- [ ] `oc get vm,vmi -n sales-demos-demo` mid-build

Commit them to `docs/images/` and link them here.
