# Objections and questions — MCP Servers

Rules for using this:

- **Answer the question that was asked**, then stop. A long answer to a short
  question reads as evasion.
- **If the answer is "it doesn't do that", say so first**, then say what it does
  do. Never lead with the workaround.
- Everything here is checkable in a public repository. If you are not sure, say
  "let me check" and check — you can, live, in front of them.

---

## "Who controls what the AI can do?"

Two independent gates.

> **"First, the server. Read-only removes nine mutating tools from the OpenShift
> server — they do not exist, so the agent cannot call them. That's structural,
> not a policy that can be overridden. Second, the bearer token. It inherits the
> creating user's RBAC in AAP — so the scope is whatever that user has, and the
> environment's `allow_write_operations` flag is a second gate on the server
> side."**

Source: `.mcp.json` (`--read-only`), `inventory/group_vars/demo/mcp.yml`,
`CLAUDE.md`.

---

## "Is this secure? The repo is public."

**Yes. No credential is committed.**

> **"The server definitions are in `.mcp.json` — committed, public, auditable.
> But the kubeconfig is gitignored and generated per machine. The AAP bearer
> token is registered with `claude mcp add --scope local`, which writes to your
> local Claude config, not to any tracked file. The vault-encrypted secrets file
> is not tracked either — untracking it is what makes the repo reusable."**

Source: `.mcp.json`, `.gitignore` (`.kube/`), `CLAUDE.md` (secrets
architecture).

---

## "What if it hallucinates?"

**It cannot hallucinate about cluster state.**

> **"Every piece of infrastructure data you saw came from a live query —
> `namespaces_list`, `vm_guest_info`, `pods_list`. The assistant did not
> summarise from memory, it asked the cluster. If the cluster is down, the call
> fails — visibly, in the terminal. It does not fill in what it thinks should
> be there."**

> **"On the write side, the governed path goes through AAP — same survey, same
> RBAC, same audit log. The assistant cannot bypass that to push a change
> directly."**

---

## "Why not just use `oc` and `curl`?"

**You can. The value is velocity, not capability.**

> **"An MCP tool call replaces the sequence: look up the hostname in
> `connection.yml`, decrypt the token from the vault, construct the `curl` or
> `oc` command, parse the JSON result. That costs a few minutes per question.
> The tool call costs a sentence. Same data, same source of truth, less
> ceremony."**

Source: `docs/plan/platform-addons-plan.md` — "stop paying a `curl` + vault
read + JSON parse every time we need to ask a cluster a question."

---

## "What about MCP and networking devices?"

**Not yet. Options brief is written, decisions are pending.**

> **"We've researched Cisco, Palo Alto and Aruba. Only Cisco has official MCP
> servers — DevNet Content Search, Meraki, Catalyst Center. Palo Alto's
> official server covers Cortex, not PAN-OS firewalls. Aruba's is explicitly
> unsupported by the vendor. Every vendor server is stdio-only with no container
> image, so putting one on OpenShift is a real project — containerise, adapt
> the transport, expose a Route, inject credentials from the vault."**

Source: `docs/plan/network-mcp-plan.md`,
[#94](https://github.com/ericcames/sales.demos/issues/94).

---

## "What happens when the token expires?"

**Silent failure, then 401.**

> **"The kubeconfig and the AAP bearer token both expire. When they do, tool
> calls start failing with 401 — no graceful degradation, no warning. The fix
> is to re-run the generator: `make-kubeconfig.sh` for OpenShift,
> `make-aap-mcp.sh` for AAP. The whole `/sales-demos-mcp` skill does both."**

The RHDP environment itself can expire, which takes the token with it — both
environments were dead on 2026-09-02 (#101). Check reachability before trusting
a committed cluster name.

---

## "Can I have it?"

> **"Yes. The `.mcp.json` file is committed and public — you can read it right
> now. `kubernetes-mcp-server` is Apache-2.0, from the `containers` org on
> GitHub. The AAP MCP server ships with Ansible Automation Platform 2.5 and
> later. The deployment guide is in Red Hat's documentation."**

Source: `.mcp.json`, [kubernetes-mcp-server](https://github.com/containers/kubernetes-mcp-server),
[AAP MCP Server docs](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.5/html/using_ansible_automation_platform/extend-assembly_deploying_ansible_mcp_server).

---

## "Is this just for Claude?"

**No. MCP is an open protocol.**

> **"The Model Context Protocol is an open specification — any client that speaks
> MCP can use these servers. We use Claude Code because it supports MCP natively,
> but the servers themselves are not Claude-specific. The same
> `kubernetes-mcp-server` works with any MCP client."**

Source: [modelcontextprotocol.io](https://modelcontextprotocol.io/).

---

## "How much does this cost to run?"

> **"The OpenShift MCP servers cost nothing to run — they are local processes on
> your laptop, no cluster resources. The AAP MCP server is a single pod in the
> cluster. On our environment it requested about 1 GiB of memory. The personal
> access token is free to create."**

Source: `inventory/group_vars/aap/probe_workloads.yml` (resource estimates).

---

## Questions to ask *them*

**After Beat 3 (live read):**
- "What's the most common question your team asks about your clusters that
  currently requires logging into the console or running `oc`?"

**After Beat 4 (governed write):**
- "What would your change-control board need to see before they'd approve an
  AI-initiated change?"

**Before the close:**
- "Is the barrier to trying this technical, or is it organizational?" — the one
  that reveals whether the next conversation is an architecture session or a
  stakeholder alignment meeting. They are very different meetings.

---

## Things not to say

- "MCP is the future of AI tooling" — they do not care about the protocol, and
  futures are claims you cannot back with a file in the repo
- "This replaces your runbooks" — it reads infrastructure and launches job
  templates, it does not replace operational procedures
- "The AI is always right" — it queries live data so it does not hallucinate
  cluster state, but it can still misinterpret what it reads. Say "it asks the
  cluster" not "it knows"
- Any promise of a date for network MCP servers (#94) — the options brief has
  three open decisions
