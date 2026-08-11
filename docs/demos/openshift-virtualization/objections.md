# Objections and questions — OpenShift Virtualization

What this audience actually asks, and answers grounded in what the repo really
does. **Including the questions where the honest answer is "no".**

Rules for using this:

- **Answer the question that was asked**, then stop. A sysadmin reads a long
  answer to a short question as evasion.
- **If the answer is "it doesn't do that", say so first**, then say what it does
  do. Never lead with the workaround.
- Everything here is checkable in a public repository. If you are not sure, say
  "let me check" and check — you can, live, in front of them.

---

## "We already run VMware. Why would we move?"

**Do not take the bait, and do not disparage the incumbent.**

> **"I'm not here to tell you to rip out your hypervisor. What I showed you
> isn't really a hypervisor demo — the interesting part is that provisioning,
> configuration, patching and decommissioning are one artifact under version
> control. You could aim most of that at what you have today. Where OpenShift
> Virtualization comes in is if you're already running containers and would
> rather not operate two platforms."**

If they press on migration specifically, be honest that it is a separate
conversation with its own tooling, and offer to bring the right person.

---

## "What about live migration and HA?"

**Answer the limitation first.**

> **"Not in what I showed you — the lab cluster is a single node, so it
> physically can't. OpenShift Virtualization does live migration and it's a real
> feature; this environment just can't demonstrate it, and I'd rather tell you
> that than show you a slide."**

Then offer the real next step: a multi-node environment where it can be shown.
The single-node constraint is recorded in
[`docs/plan/ocpvirt-demo-plan.md`](../../plan/ocpvirt-demo-plan.md) → Constraints.

---

## "Does this do Windows?"

> **"It's wired and it doesn't boot yet. Terraform builds the VM, the inventory
> group's there, WinRM's configured — but Red Hat can't redistribute Windows
> media, so somebody has to do a one-time golden image build, and I haven't done
> it. It's tracked in public as issue #3."**

If they ask what the build involves: import the ISO, install the virtio drivers
and guest agent, enable WinRM, sysprep, snapshot it, publish it to a private
registry. About forty-five minutes, once. After that Windows guests provision on
the same t-shirt sizes as Linux.

**Do not promise a date.** It is on the roadmap as Not started.

---

## "Where are the credentials? That repo is public."

This one deserves a careful, specific answer — it is the question that decides
whether they trust the whole thing.

> **"There's exactly one secrets file and it's encrypted with Ansible Vault. It
> is committed — deliberately — because an encrypted file in git is easier to
> keep in step across machines than a file everybody has a slightly different
> copy of. The password isn't in the repo; it lives outside it on the operator's
> machine. And at run time the platform supplies it through a Vault credential,
> so the job can decrypt it and nobody has to have it on their laptop."**
>
> **"Anything that isn't a credential — hostnames, usernames, namespaces — is in
> plaintext on purpose, so you can read the configuration without decrypting
> anything."**

If they push on the demo-platform hostnames being visible: those are ephemeral
lab addresses that expire, not customer infrastructure, and keeping them
readable is what lets the encrypted file hold credentials only.

Worth adding, because it is a genuinely good design story:

> **"There's a check in CI that fails the build if that file is ever committed
> unencrypted. It's tracked rather than ignored, so the check is what protects
> it — a `.gitignore` rule would just hide the file instead of verifying it."**

---

## "Is it really idempotent, or does it just say it is?"

> **"Re-run the platform install and it reports zero changes. It's a converger —
> you can point it at a half-built environment and it finishes the job rather
> than falling over."**

**Then volunteer the exception before they find it:**

> **"One honest caveat: the AAP configuration job always reports 'changed', even
> when nothing did. The platform returns one setting as `$encrypted$` on every
> read, so Ansible can never see it as settled. It's cosmetic, it's known, and
> it's written down in the repo."**

Volunteering this is worth more than the idempotence claim itself.

---

## "What happens when it breaks?"

Be specific. Vagueness here undoes everything.

> **"Three things actually break in practice, and all three are documented."**
>
> **"A cancelled run leaves the Terraform state lock held. The next run fails
> with the lock ID, who holds it, and the exact command to release it — and it
> deliberately never auto-releases, because auto-releasing a lock somebody else
> is legitimately holding is how you corrupt state."**
>
> **"Lab environment tokens expire. You get timeouts and then a 401. The fix is
> to refresh the token in the encrypted file."**
>
> **"And if the guest hasn't finished booting, ssh refuses. The playbook waits
> for the connection before it does anything, so that one's handled."**

The general point behind the specifics:

> **"The failures have names and documented fixes. That's the difference between
> automation you can operate and automation you have to file a ticket about."**

---

## "How is this different from a shell script?"

> **"Three ways that matter. It converges instead of running — re-run it and it
> reports zero changes rather than doing everything twice. The guardrails are
> enforced rather than documented: ask for more memory than the node has and the
> plan fails, it doesn't build you something that sits in Pending while
> reporting success. And it runs identically from the platform and from a
> laptop, because it's the same file both times, not a reimplementation."**

---

## "Who can launch this? Can a developer self-serve?"

> **"The survey is the interface — two questions, and no credentials in sight.
> That's a job template you can hand to whoever should have it, with the
> platform's own RBAC deciding who. The person launching it never sees the
> token, the ssh key or the vault password."**

Then the point they will appreciate:

> **"And notice there's no dropdown for which environment to build in. That's
> deliberate — it'd be one mis-click away from provisioning into the cluster you
> show customers."**

---

## "What does this cost us to run?"

> **"The VMs delete themselves at 6 PM on a schedule. That's the answer to cost
> control — it's a scheduled job, not a monthly reminder to go look at what's
> still running."**
>
> **"And teardown is selective: it destroys the guests but keeps the
> virtualization layer, the boot images and the Terraform state, because
> rebuilding those is forty-five minutes you don't want to spend every morning."**

---

## "How long did this take to build?"

Answer honestly; the honest answer is a good one.

> **"It's phased, and it's all in the open — the plan document records the
> research, the decisions, and the ones that got reversed. Including two bugs
> that shipped through completely green CI, and the lesson written next to them:
> the lint gate can't tell you a playbook works. Every phase gets run against a
> sandbox environment and verified on the cluster before it merges."**

Sysadmins recognize the difference between a demo built for a demo and a demo
built like an operational thing. This is a chance to show it is the second.

---

## "Can I have it?"

The best question you will get. Answer immediately and without conditions:

> **"Yes — it's public. `github.com/ericcames/sales.demos`. That's the link in
> the footer of the page the demo built."**

Then the useful follow-up:

> **"The design notes are worth more than the code, honestly. They record why
> each choice was made rather than just what to do — including the things that
> were tried and abandoned."**

---

## Questions to ask *them*

The session should not be one-directional. Good moments to turn it around:

**After Beat 2 (their current process):**
- *"Where in that does it usually stall?"*
- *"How do you know today what's running that shouldn't be?"*

**After Beat 4 (the workflow):**
- *"How much of that sequence is written down somewhere in your shop?"*
- *"If the person who knows the order left, what would happen?"*

**Before the close:**
- *"Is the blocker here tooling, or getting agreement on what standard looks
  like?"* — the answer tells you whether the next conversation is technical or
  organizational, and they are very different meetings.

---

## Things not to say

- **"It just works."** They have heard it. Use "here's what breaks and here's
  the fix" instead.
- **"Minutes instead of weeks."** Invites an argument about the number rather
  than attention to the mechanism. "About nine minutes" is a fact and lands
  better.
- **Anything comparative about VMware.** You do not need it, and it makes you
  sound like you came to sell rather than to show.
- **Any promise of a date** for Windows or anything else marked Not started.
- **A claim you cannot point at in the repo.** Everything in the talk track can
  be sourced — keep it that way.
