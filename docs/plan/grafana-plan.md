# Grafana Cloud observability

Issue [#260](https://github.com/ericcames/sales.demos/issues/260), sibling of
[#99](https://github.com/ericcames/sales.demos/issues/99) (Dynatrace).

## Context

No observability infrastructure existed in this repo before this work. #99
tracks agentic observability via Dynatrace — application-level, OneAgent-based,
requiring an NFR SaaS tenant. This is the infrastructure-level complement:
cluster metrics, logs, AAP job telemetry — using Grafana Cloud's free tier.

**Why Grafana Cloud, not self-hosted:**

- Survives RHDP environment rebuilds. Both RHDP environments expired silently
  once (#101); anything deployed on the cluster died with them. An external SaaS
  instance does not.
- Free tier: 10k metrics series, 50 GB logs, 50 GB traces, 3 users, no credit
  card. Sufficient for two demo environments.
- No infrastructure to deploy, no operator to manage, no database to provision.
  Compare with Automation Orchestrator (#108/#141), which took CloudNativePG and
  three databases to get running.

**Why an MCP server:**

The same thesis as #102: stop paying a manual lookup every time the question is
"is the cluster healthy" or "how long did the last provision take." The official
`grafana/mcp-grafana` (3.4k stars, Apache-2.0, Grafana Labs) covers dashboards,
Prometheus queries, Loki log queries, alerting, incidents, annotations and more.
It runs as stdio, so it fits the same model as `kubernetes-mcp-server`.

## The MCP server

### `--scope local`, not `.mcp.json`

Follows the AAP MCP server pattern from
[`platform-addons-plan.md`](platform-addons-plan.md). Three reasons:

1. **The service account token is a standalone credential.** OpenShift
   kubeconfigs are derived artifacts — `make-kubeconfig.sh` generates them from
   vault contents, so `.mcp.json` references a gitignored path and the credential
   has an obvious refresh. A Grafana Cloud SA token is created in the UI with no
   vault-backed derivation step. It is the credential, not a cache of one.
2. **The URL is sensitive.** It contains the Grafana Cloud org slug. By the
   Dynatrace precedent (#99 S3), vendor-specific SaaS URLs are treated as
   credentials — the RHDP exception does not extend to other vendors.
3. **There is one instance.** OpenShift and AAP are per-environment (the
   environment is in the server's name, #16). Grafana Cloud is a single external
   service that spans both. One server named `grafana`, not two.

### Credentials

Both go in the vault (`playbooks/group_vars/all/secrets.yml`) as **top-level
keys**, not under `env_secrets`:

```yaml
grafana_cloud_url: "https://<org>.grafana.net"
grafana_cloud_sa_token: "glsa_..."
```

Top-level because they span both environments — the same reasoning that puts
`rhsm_org_id` and `vaulted_subscriptions_client_id` at the top level.

The service account is created with the **Viewer** role. Read-only, matching
the governance thesis: MCP reads, Ansible writes. Even with no Ansible write
path for Grafana yet, constraining the token from the start means the demo can
safely show that the agent reads but does not modify dashboards or alerts.

### Registration

`utilities/make-grafana-mcp.sh` reads from the vault and runs:

```bash
claude mcp add --transport stdio --scope local \
  -e GRAFANA_URL="$GRAFANA_URL" \
  -e GRAFANA_SERVICE_ACCOUNT_TOKEN="$GRAFANA_TOKEN" \
  grafana -- uvx mcp-grafana
```

Key differences from `make-aap-mcp.sh`:

- Takes no arguments (one instance, not per-environment)
- No kubeconfig dependency
- No token creation step (token is pre-created in the Grafana UI)
- `--transport stdio` (not `--transport http`)

### The token exception

Same exception as the AAP MCP token documented in
[`platform-addons-plan.md`](platform-addons-plan.md): an MCP client needs a
durable credential, so `CLAUDE.md`'s `always:` cleanup rule does not apply.
The token is created in the Grafana Cloud UI and revoked there.

### Allowlist

`.claude/settings.json` carries `mcp__grafana__*`, pointing at a server that
does not exist until `make-grafana-mcp.sh` runs. This is the same expected
state as the AAP servers — documented in the `sales-demos-mcp` skill.

## Grafana Cloud account setup

Manual, in a browser. Cannot be scripted.

1. Sign up at grafana.com (free tier, no credit card)
2. Note the instance URL (e.g., `https://<org>.grafana.net`)
3. Administration > Service Accounts > Add Service Account
4. Assign the **Viewer** role
5. Generate a service account token
6. Add both values to the vault:
   ```bash
   ansible-vault edit playbooks/group_vars/all/secrets.yml \
     --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
   ```

## Verification

1. `bash utilities/make-grafana-mcp.sh` completes without error
2. `claude mcp list` shows `grafana` alongside the existing servers
3. Restart Claude Code, then call a Grafana MCP tool (e.g.,
   `list_datasources` or `search_dashboards`) — it should connect and return
   data from the free-tier instance (even if empty on a fresh account)

## Future phases

**Phase 1 — Feed data in.** Deploy Grafana Alloy on the OpenShift clusters to
push metrics (Prometheus remote-write) and logs (Loki) to Grafana Cloud. A
playbook with push credentials from the vault. This is where observability
becomes useful rather than merely connected.

**Phase 2 — Demo story.** Pre-built dashboards showing VM provisioning times,
AAP job durations, cluster resource utilization. The agent queries Grafana via
MCP to answer "how long did the last provision take?" or "is the cluster
healthy enough for the next demo?" Pairs with Dynatrace (#99): Dynatrace for
application-level (OneAgent, Davis), Grafana for infrastructure-level.

**Phase 3 — Dashboard as code.** Grafana dashboards defined in the repo (JSON
or Terraform's Grafana provider), applied by a playbook. Matches the
config-as-code thesis running through every use case here.
