# Run sheet — MCP Servers

**This is the page you hold while presenting.** The narrative behind each beat,
with the actual words, is in [`talk-track.md`](talk-track.md) — rehearse from
that, present from this.

| | |
|---|---|
| **Length** | 20 minutes (15 + 5 for questions) |
| **Audience** | Platform engineers and automation leads |
| **Needs an environment?** | Yes — the whole demo is live queries against a real cluster |
| **Assets** | [`server-inventory.md`](server-inventory.md), [`architecture.md`](architecture.md), this repo |

---

## Before you start (5 minutes, offline)

1. Confirm the MCP servers are working: `claude mcp list` — all four should
   appear
2. Open a Claude Code terminal in this repo
3. Have these tabs ready:
   - This run sheet
   - [`server-inventory.md`](server-inventory.md) (the status table)
   - [`.mcp.json`](../../../.mcp.json) in the repo (shows what is committed)
   - The AAP controller UI, logged in (for the job template beat)

If the servers are not working, run `/sales-demos-mcp` — it takes about two
minutes. Do not debug in front of an audience.

---

## The arc

| Time | Beat | On screen |
|---|---|---|
| 0–3 | Cold open — ask the cluster a question | Claude Code terminal |
| 3–6 | The four servers | Status table from `server-inventory.md` |
| 6–10 | A live read on the demo environment | `pods_list`, `vm_guest_info` on `openshift-demo` |
| 10–15 | The governed write path | AAP job template launch through `aap-sandbox` |
| 15–18 | Why this is not an ungoverned agent | The repo, `.mcp.json`, `CLAUDE.md` |
| 18–20 | The honest bits and close | — |

---

## 0–3 · Cold open

Open Claude Code. Type a natural-language question:

> *"What namespaces exist on the demo cluster?"*

The assistant calls `mcp__openshift-demo__namespaces_list`. The result is real
data from a real cluster, returned in the terminal.

> **"That was not a script. The assistant asked the cluster directly, through a
> read-only MCP server, and got back what is actually there."**

Point at the tool name in the output — `mcp__openshift-demo__namespaces_list`.
The environment (`demo`) and the access posture (`read-only`) are in the name.

---

## 3–6 · The four servers

Switch to the status table in [`server-inventory.md`](server-inventory.md).

| Server | Platform | Transport | Access | Tools |
|---|---|---|---|---|
| `openshift-sandbox` | OpenShift | stdio | read-write | 25 |
| `openshift-demo` | OpenShift | stdio | read-only | 16 |
| `aap-sandbox` | AAP | HTTP | read-write | ~140 |
| `aap-demo` | AAP | HTTP | read-only | ~95 |

> **"Four servers. Two platforms, two environments. Demo is read-only — that's
> the environment a customer would watch. Sandbox is read-write — that's the
> one I break for velocity."**

Point at the tool count difference: 25 vs 16. Nine mutating tools are removed
by `--read-only` — see [`server-inventory.md`](server-inventory.md#the-nine-tools---read-only-removes)
for the list.

---

## 6–10 · A live read

Still in Claude Code. Ask something that shows real investigative value:

> *"What VMs are running in the sales-demos-demo namespace?"*

The assistant calls `mcp__openshift-demo__pods_list_in_namespace` or
`mcp__openshift-demo__vm_guest_info`. Walk through the result — OS version,
resource allocation, state.

> **"Same data you'd get from `oc` or the console, without remembering the
> flags. And read-only — the assistant physically cannot delete that VM through
> this server."**

If no VMs are running, ask about pods instead — the point is real data, not a
specific resource.

---

## 10–15 · The governed write path

<!-- Phase 2: fill in the AAP MCP server beats with specific job template
     launch examples. The flow is:
     1. Ask the assistant to launch a job template through aap-sandbox
     2. The assistant calls job_templates_launch_create
     3. Show the job running in the AAP UI
     4. Show jobs_stdout_retrieve for the output -->

*This beat will use the AAP MCP server to launch a job template — demonstrating
that writes go through AAP's governed path, not directly to the cluster.
Content for this beat is pending the AAP MCP documentation (Phase 2).*

For now, show the concept:

> **"The assistant can read both clusters. But when it needs to change
> something, it goes through Ansible Automation Platform — the same job
> templates, the same RBAC, the same audit log your team already uses."**

---

## 15–18 · Why this is not an ungoverned agent

Switch to the repo. Show three things:

1. **`.mcp.json`** — committed, public. The server definitions are in version
   control.
2. **`CLAUDE.md`** — the directive: "Ask the cluster over MCP; shell out only
   when no tool covers it."
3. **`.claude/settings.json`** — the allowlist. Per-server wildcards, not
   per-tool lists that go stale.

> **"The servers are defined in the repo. The access posture is enforced at
> the server — read-only is not a suggestion, it removes the tools. And the
> configuration is auditable because it is committed alongside the automation
> it governs."**

---

## 18–20 · The honest bits and close

> **"Three things I'd rather you hear from me."**
>
> **"One — the agent inherits the creating user's permissions. The bearer token
> for the AAP MCP server was created as admin, so the agent has admin access.
> That's a known scope, not a default."**
>
> **"Two — the MCP client token for AAP does not clean itself up. Every other
> token in this repo is deleted in an always block. This one is durable by
> design, and retiring it is manual."**
>
> **"Three — read-only removes nine specific tools. It does not remove all
> investigative tools that could have side effects — `vm_troubleshoot` survives,
> and `pods_exec` does not. The server's author made that call, not us."**

Then **one** question:

- *"What's the first thing in your operations you'd want the AI to read?"*
- *"Who else needs to see this before you'd be comfortable with a proof of
  concept?"*

---

## Running it live

Every beat is already live — the demo is inherently a live-environment demo.

| Beat | What can go wrong |
|---|---|
| 0–3 Cold open | MCP server not connected. Fall back to the status table |
| 6–10 Live read | Cluster unreachable. Show the committed tool listing instead |
| 10–15 Governed write | AAP MCP returns 503. Wait, or describe the flow verbally |

**Keep [`server-inventory.md`](server-inventory.md) open in a tab regardless.**
If a live query fails, cut to the status tables and tool listings — they are
the same information, documented.

### Recovery moves

| Symptom | Move |
|---|---|
| MCP server shows "failed" | Say "the cluster expired" and show architecture.md instead |
| Tool call returns 401 | Token is stale — do not debug live; cut to the status table |
| AAP returns 503 | Pod is starting — wait 30 seconds; if it persists, describe the flow |
| No VMs running | Ask about pods or namespaces instead — the point is real data |
| Audience asks about a tool not in the listing | Open `server-inventory.md` and show the full list |

---

## Screenshots still worth capturing

- [ ] A cold open query with `namespaces_list` returning real data
- [ ] The tool name visible in the Claude Code output (`mcp__openshift-demo__namespaces_list`)
- [ ] A `vm_guest_info` result showing OS version and resource allocation
- [ ] An AAP job template launch through `aap-sandbox` (Phase 2)
