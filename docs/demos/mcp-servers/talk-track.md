# Talk track — MCP Servers

**Rehearse from this. Present from [`run-sheet.md`](run-sheet.md).**

Everything in this track works with a live environment. Without one, the status
tables in [`server-inventory.md`](server-inventory.md) and the architecture
diagram in [`architecture.md`](architecture.md) carry the argument — but the
live beats are what make it land.

---

## Who is in the room

**You are the pre-sales engineer.** Every document in this folder is written to
you.

**They are platform engineers and automation leads** — people who already
automate things and are now being asked "how does AI fit into our operations?"
They have heard the pitch before. They want to see governance, not novelty.

| They do not care about | They care intensely about |
|---|---|
| "AI is the future" | Who controls what the AI can do |
| How many tools the MCP server exposes | Where the audit trail is |
| The protocol specification | Whether this replaces their automation or sits on top of it |
| A polished demo page | Whether the configuration is in version control |

**Do not lead with the protocol.** MCP is plumbing. The audience cares about
what it enables — an AI that can read their infrastructure and is provably
unable to change it without going through their governed automation path.

**Do not compare to competitors.** This is a capability demo, not a bake-off.
If they ask how it compares, redirect to what they saw: "the read-only boundary
and the governed write path are what matter — the protocol underneath could
change and the story would be the same."

---

## Beat 1 · Cold open (0–3)

Open Claude Code in this repo. Type a natural-language question:

> *"What namespaces exist on the demo cluster?"*

The assistant calls `mcp__openshift-demo__namespaces_list` and returns real
data from a real cluster.

> **"That was not a script. I asked a question, the assistant asked the cluster,
> and that's what's actually there. The tool it called is on screen —
> `openshift-demo`, `namespaces_list`. The environment is in the name."**

**Why this beat exists.** It proves the mechanism is real. No slides, no canned
output. If it fails, you debug or cut — either way the audience knows it is
live.

**Transition:** *"Let me show you what it can and can't do."*

---

## Beat 2 · The four servers (3–6)

Switch to the status table. Show it on screen or recite from
[`server-inventory.md`](server-inventory.md):

| Server | Platform | Transport | Access | Tools |
|---|---|---|---|---|
| `openshift-sandbox` | OpenShift | stdio | read-write | 25 |
| `openshift-demo` | OpenShift | stdio | read-only | 16 |
| `aap-sandbox` | AAP | HTTP | read-write | ~140 |
| `aap-demo` | AAP | HTTP | read-only | ~95 |

> **"Four servers. Two platforms — OpenShift and Ansible Automation Platform.
> Two environments — sandbox, where I break things, and demo, where a customer
> watches. Demo is read-only on both. That's not a setting I toggled — it
> removes the tools. The server physically cannot accept a delete request."**

Point at 25 vs 16: nine mutating tools removed. The audience does not need the
list — they need to know the enforcement is structural, not advisory.

> **"The configuration is in a file called `.mcp.json`, committed to this
> public repository. You can read it right now. The access posture is auditable
> because it's in version control."**

**Why this beat exists.** It sets up the security argument before any write
path is shown. When the governed write comes in Beat 4, they already know the
alternative was removed, not just discouraged.

**Transition:** *"Let me show you what a read looks like."*

---

## Beat 3 · A live read (6–10)

Ask something investigative:

> *"What VMs are running in the sales-demos-demo namespace? Show me the guest
> OS details."*

The assistant calls `vm_guest_info` or `pods_list_in_namespace` on
`openshift-demo`. Walk through the result.

> **"Same data you'd get from `oc describe` or the console, without the flags.
> And this is the read-only server — the assistant cannot delete that VM,
> cannot exec into it, cannot scale it. Those tools don't exist on this
> server."**

If no VMs are running, substitute any meaningful query — the point is real data
from a real cluster, not a specific resource.

> **"This is the investigative layer. Every question the AI can answer about
> your infrastructure, it answers by asking the infrastructure. It doesn't
> hallucinate cluster state — it queries it."**

**Why this beat exists.** It demonstrates the value of the read path in
isolation. The audience sees that reading infrastructure is useful on its own,
before any write is introduced.

**Transition:** *"Reading is useful. But what happens when the AI needs to
change something?"*

---

## Beat 4 · The governed write path (10–15)

<!-- Phase 2: replace this placeholder with the live AAP MCP server beats.
     The flow:
     1. Ask the assistant to launch a job template through aap-sandbox
     2. The assistant calls job_templates_launch_create
     3. Show the job running in the AAP UI
     4. Show jobs_stdout_retrieve for the output
     5. Point at the audit trail in the controller -->

*This beat will use the AAP MCP server to launch a job template. Content is
pending the AAP MCP documentation (Phase 2).*

For now, describe the concept:

> **"The assistant can read both clusters freely. But when it needs to make a
> change — provision a VM, patch a host, update a configuration — it goes
> through Ansible Automation Platform. The same job templates, the same RBAC,
> the same survey, the same audit log your team already uses."**

> **"The AI doesn't get a separate path. It uses the governed path you already
> trust. That's the whole design — not a new way to change things, but the
> existing way, accessible from natural language."**

**Why this beat exists.** The read path is table stakes. The governed write
path — where the AI can request a change but only through your automation
platform — is the argument. The audience should leave thinking "reads
everything, changes nothing except through Ansible."

**Transition:** *"You might be wondering how we keep that boundary in place."*

---

## Beat 5 · Why this is not an ungoverned agent (15–18)

Show three files in the repo:

1. **`.mcp.json`** — the server definitions, committed, public
2. **`CLAUDE.md`** — the directive: "Ask the cluster over MCP; shell out only
   when no tool covers it"
3. **`.claude/settings.json`** — the tool allowlist, per-server wildcards

> **"The servers are defined in the repository. The behaviour directive is in
> the repository. The access policy is in the repository. Everything that
> governs what the AI can and cannot do is version-controlled, reviewable,
> and auditable — the same way you'd govern a playbook or a Terraform
> module."**

> **"Read-only is enforced at the server. The allowlist says which servers the
> agent can call, not which tools — because a per-tool list goes stale the
> moment a server gains a new tool, and a stale allowlist is a false
> guarantee."**

**Why this beat exists.** It answers the implicit question: "who is in charge?"
The answer is the repository, not the AI, and the proof is that the
configuration is committed and public.

**Transition:** *"Before questions, let me tell you what this doesn't do."*

---

## Beat 6 · The honest bits (18–19)

**Do not cut this beat.** It is the highest-value ninety seconds in the session.

> **"Three things I'd rather you hear from me."**
>
> **"One — the agent inherits the creating user's permissions. The bearer token
> for AAP was created by an admin account, so the agent has admin access to
> AAP. That's a scope decision, and it's documented, but it's not least
> privilege."**
>
> **"Two — the AAP client token doesn't clean itself up. Every other token in
> this repo is deleted automatically when the playbook finishes. This one is
> durable by design — an MCP client needs a persistent credential. Retiring it
> is manual, and the steps are documented."**
>
> **"Three — read-only removes nine tools from the OpenShift server. It doesn't
> remove everything that could theoretically have side effects.
> `vm_troubleshoot` survives because the server's author classified it as
> diagnostic. The line was drawn by the upstream project, not by us."**

**Why this works.** You are not confessing weaknesses — you are demonstrating
that the documentation is honest. A platform engineer who has sat through demos
where the hard parts were skipped will trust the working parts more once you
have been straight about the limitations.

---

## Beat 7 · Close (19–20)

> **"Everything I showed you — the server definitions, the access posture, the
> tool listings, the automation underneath — is in a public repository. The
> design notes for why it's built this way are there too, alongside the things
> that don't work yet. Nothing is behind a login."**

Then **one** question. Pick the one that fits what you heard earlier:

- *"What's the first thing in your operations you'd want the AI to read?"*
- *"Who else needs to see this before you'd be comfortable with a proof of
  concept?"*
- *"Is the barrier to trying this technical, or is it organizational?"*

**Do not offer all three.** Pick one. A presenter who offers three questions
gets no answer to any of them.

---

## If you only get ten minutes

Keep Beats 1, 2, 4 and 6 — the live query, the four servers with the access
posture, the governed write path, and the honest bits. Drop the rest.

That is still a complete argument: reads everything, changes nothing except
through Ansible, and here is what it does not do.

---

## Where the words come from

Every claim in this track is checkable in the repo:

| Claim | Source |
|---|---|
| Four servers, two platforms, two environments | `.mcp.json`, `SKILL.md` lines 19–26 |
| Demo is read-only, sandbox is read-write | `.mcp.json` line 21 (`--read-only`), `inventory/group_vars/demo/mcp.yml` |
| Nine mutating tools removed by `--read-only` | [`server-inventory.md`](server-inventory.md#the-nine-tools---read-only-removes) |
| 25 tools on sandbox, 16 on demo | Measured 2026-09-03, [`server-inventory.md`](server-inventory.md) |
| ~140 tools on AAP sandbox | Measured 2026-09-03, `SKILL.md` line 208 |
| One server per environment, #16 precedent | `SKILL.md` lines 28–33, `CLAUDE.md` |
| Token inherits creating user's permissions | `CLAUDE.md`, Red Hat AAP token documentation |
| MCP client token does not self-clean | `CLAUDE.md`, `SKILL.md` lines 61–64 |
| `vm_troubleshoot` survives read-only | [`server-inventory.md`](server-inventory.md#openshift-demo--16-tools-read-only) |
| Server definitions committed in `.mcp.json` | `.mcp.json` |
| Directive in `CLAUDE.md` | `CLAUDE.md` — "Ask the cluster over MCP" |
| Allowlist in `.claude/settings.json` | `.claude/settings.json` |
