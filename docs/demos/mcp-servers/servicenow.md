# ServiceNow MCP — what to do today

**Short version: wait for the upgrade, and do not let that stop the demo.**

The ServiceNow MCP server worth showing a customer is ServiceNow's own, and it
needs a platform version this repo's demo instance does not have yet. Until
then, the Ansible half of the story works without any MCP server at all.

ServiceNow is **not** one of the four servers this repo runs — see
[`server-inventory.md`](server-inventory.md) for those.

---

## Measure your instance first

Everything below turns on a version, so read it rather than assume it. On any
instance:

```
https://<your-instance>.service-now.com/stats.do
```

Read four fields: **build name**, **build tag**, **build date**, **offering**.
The build name is the release — Yokohama, Zurich, Australia — and it alone
decides which row of the table below is yours.

This is the same probe-before-designing pattern
[`network-mcp-plan.md`](../../plan/network-mcp-plan.md) records for the network
vendors: establish what the environment actually is before designing against it.

---

## The fork

| | **Native MCP Server Console** | **Build your own** |
|---|---|---|
| **Requires** | Zurich Patch 9+ or Australia Patch 2+, a Now Assist / AI Native SKU, and the `sn_mcp_server` plugin | Any version — you are talking to the REST API |
| **Runtime** | ServiceNow-hosted | Yours to host |
| **Governance** | AI Control Tower, managed OAuth, role-based tool packages, audit trail, observability, consumption metering | Whatever you build |
| **Surface** | Now Assist Skills, Knowledge Graph, subflows and actions, scripted REST — read *and* write | Exactly the tools you ship |
| **Auth** | OAuth 2.0 authorization code grant (PKCE for public clients) | Your choice |
| **Cost** | Consumes Assist currency **on every tool call** | Hosting only |

---

## The recommendation: the native console, once you can run it

When an instance reaches Zurich Patch 9+ (or Australia Patch 2+) with the
entitlement, that is the one to use — and the reason is the demo, not the
feature list.

**Governance stops being something you assert and becomes something you show.**
Every other option in this space leaves you saying "and of course you would
control what the agent can reach." The native console puts that control on
screen: a console listing which tools are published, to which clients, under
which roles, with the audit trail and the consumption metering beside it. For
an audience whose real question is *"who decided the AI could do that?"*, a
screen beats a sentence.

Two things to say honestly when you show it:

- **It is a ServiceNow-licensed control plane, not a Red Hat one.** That is fine
  — it is their platform — but it means the governance story here is
  ServiceNow's, and the Red Hat story is what happens on the write path.
- **Every tool call costs Assist currency.** An agent that polls is an agent
  that bills. Worth raising before a customer discovers it.

### This instance cannot run it

Measured from `/stats.do` on the Red Hat demo instance, **2026-09-02**:

| Field | Value |
|---|---|
| Build name | **Yokohama** |
| Build date | 2026-08-26 |
| Offering | enterprise |
| Instance state | ONLINE, fully operational |

**Yokohama is two releases behind Zurich**, so the native console is
unavailable regardless of entitlement — the platform version alone settles it.
There is nothing to request and nothing to check. Re-read `/stats.do` after any
upgrade; that is the only thing that changes this page.

Unaffiliated community ServiceNow MCP servers exist. They are deliberately not
evaluated or recommended here — the omission is a decision, not an oversight.

---

## Meanwhile, the demo still works — because the write path needs no MCP server

This is the part worth internalising: **the Red Hat half of the story has no
ServiceNow MCP dependency at all.**

`servicenow.itsm` is already pinned in this repo at
`hub/certified-requirements.yml:411` (`>=2.13.2`). A job template using it
creates the incident, writes the work note, and closes the record — governed,
versioned, auditable, and running today on an instance that cannot host an MCP
server of any kind.

What an MCP server would add is the *read* half: letting the agent pull the
incident, the affected CI and the change window as context before it acts. That
is genuinely useful and it is the smaller half. Losing it costs the demo a beat,
not its thesis.

The thesis is unchanged and does not depend on this page:
**the agent reads, Ansible writes.**

If you need the read half before the upgrade, build a server with only read
tools on it — [`building-a-server.md`](building-a-server.md) covers the
decision, the language, the transport and the packaging.

---

## Instance hygiene, if you do connect something

Both of these come from the same `/stats.do` reading, and they shape the design
more than they look:

- **The REST integration semaphore set (`API_INT`) has 4 concurrent slots.** A
  server that fans out parallel table queries per tool call can saturate it and
  slow the instance for everyone on it. **Paginate rather than parallelise, and
  cap in-flight requests.**
- **It is a shared demo instance.** Anything the demo creates must carry a
  recognisable prefix in `short_description` and have a teardown path. Leaving
  open incidents in a shared Red Hat instance makes them somebody else's
  problem.

---

## Where the pieces would live in this repo

Following the split every other environment value here follows:

| Value | Where | Why |
|---|---|---|
| Instance URL | each environment's `connection.yml` | Connection fact, not a credential |
| Integration username | each environment's `connection.yml` | Same |
| Password / secret | `env_secrets` in the vaulted `playbooks/group_vars/all/secrets.yml` | Credential |

**Instance identifiers stay out of the repo entirely.** The instance ID, node ID
and internal IP are **not** covered by the `*.dyn.redhatworkshops.io` exception
in `CLAUDE.md` — that exception is for ephemeral RHDP cluster addresses, and a
ServiceNow instance is not one.

---

## Related

- [`building-a-server.md`](building-a-server.md) — what to do when no server
  exists, or none you would ship
- [`server-inventory.md`](server-inventory.md) — the four servers this repo
  actually runs
- [`objections.md`](objections.md) — including what to say when someone asks
  about a platform with no MCP server
