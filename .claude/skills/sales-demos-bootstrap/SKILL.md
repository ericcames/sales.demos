---
name: sales-demos-bootstrap
description: >-
  Full environment bootstrap from a single AAP URL — repoint local.yml,
  verify vault, run setup.yml (all 14 stages with timing including probe),
  set up MCP servers, and verify everything.
  TRIGGER when: user provides a new RHDP environment URL and wants it fully
  set up, or says "bootstrap", "new environment", "fresh cluster".
  SKIP: if only one component needs updating — use the specific skill instead.
---

# sales-demos-bootstrap

Takes a single AAP URL and drives every step needed to bring a new RHDP
environment from bare to demo-ready, including the post-setup tasks that
`setup.yml` cannot do (MCP server registration, cluster probing, settings
updates).

**This skill orchestrates other skills and playbooks.** It contains no
playbook logic of its own — it calls `setup.yml`, invokes
[`/sales-demos-mcp`](https://github.com/ericcames/sales.demos/blob/main/.claude/skills/sales-demos-mcp/SKILL.md),
runs `probe_env.yml`, and updates gitignored local files. The playbooks do the
work; this skill sequences them.

## Quick start

A new RHDP environment needs three inputs from its RHDP page: the **AAP URL**,
the **AAP admin password**, and the **kubeadmin password**. The passwords go
into the vault with `utilities/set-env-passwords.sh`; the URL goes in the
prompt. The copy-paste commands live in one place, the
[New environment quick start](https://ericcames.github.io/sales.demos-docs/reference/new-environment/#quick-start) — do not duplicate them here.

## When to use this vs the pieces

| Situation | Use |
|---|---|
| Brand new RHDP environment, want everything | **This skill** |
| Only AAP config changed (edited group_vars) | [`/sales-demos-config`](https://github.com/ericcames/sales.demos/blob/main/.claude/skills/sales-demos-config/SKILL.md) |
| Only the portal needs redeploying | [`/sales-demos-portal`](https://github.com/ericcames/sales.demos/blob/main/.claude/skills/sales-demos-portal/SKILL.md) |
| MCP servers need reconnecting | [`/sales-demos-mcp`](https://github.com/ericcames/sales.demos/blob/main/.claude/skills/sales-demos-mcp/SKILL.md) |
| Cluster already set up, just verify | [`/sales-demos-verify-env`](https://github.com/ericcames/sales.demos/blob/main/.claude/skills/sales-demos-verify-env/SKILL.md) |
| First time on this machine | [`/sales-demos-first-time`](https://github.com/ericcames/sales.demos/blob/main/.claude/skills/sales-demos-first-time/SKILL.md) |

## Step 1 — Parse the AAP URL

Extract the cluster ID from the URL the user provides. The pattern is:

```
aap-aap.apps.cluster-<id>.dyn.redhatworkshops.io
```

Derive:
- `aap_hostname`: `aap-aap.apps.cluster-<id>.dyn.redhatworkshops.io`
- `openshift_api_url`: `https://api.cluster-<id>.dyn.redhatworkshops.io:6443`
- `openshift_apps_domain`: `apps.cluster-<id>.dyn.redhatworkshops.io`

## Step 2 — Which environment

If the prompt names one (`/sales-demos-bootstrap sandbox <url>`), use it.
Otherwise ask: **sandbox, demo, or edge?** Default to `sandbox` if the user
does not specify.

Edge is different — it is a persistent bare-metal SNO, not an RHDP
provisioning. If the user says edge, confirm they mean the NUC at
`192.168.0.253` and not a new RHDP environment.

## Step 3 — Update local.yml

Write the three identity values to `inventory/group_vars/<env>/local.yml`.
This file is gitignored — it overrides `connection.yml` without touching a
tracked file.

```bash
ENV=sandbox  # or demo

cat > inventory/group_vars/"$ENV"/local.yml <<YAML
---
# Repointed by /sales-demos-bootstrap on $(date +%F)
aap_hostname: "aap-aap.apps.cluster-<id>.dyn.redhatworkshops.io"
openshift_api_url: "https://api.cluster-<id>.dyn.redhatworkshops.io:6443"
openshift_apps_domain: "apps.cluster-<id>.dyn.redhatworkshops.io"
YAML
```

If `local.yml` already exists, read it first and preserve any extra keys
(like `available_memory_gb` or SSH key overrides).

## Step 4 — Verify vault credentials and derive the API token

The vault must already contain `aap_password` and `kubeadmin_password` for this
environment. `openshift_api_token` is **derived automatically** from
`kubeadmin_password` — it is never pasted manually (#559).

First, verify the two manual credentials are present:

```bash
VAULT_ID="sales.demos@$HOME/secrets/.vault_pass_sales_demos"

ansible-vault view playbooks/group_vars/all/secrets.yml \
  --vault-id "$VAULT_ID" 2>/dev/null \
  | ENV="$ENV" python3 -c '
import sys, yaml, os
env = os.environ["ENV"]
data = yaml.safe_load(sys.stdin)
secrets = data.get("env_secrets", {}).get(env, {})
for key in ["aap_password", "kubeadmin_password"]:
    status = "present" if secrets.get(key) else "MISSING"
    print(f"  {key}: {status}")
'
```

If either is missing, **stop** and tell the user to run this in a terminal
in the repo (the prompts hide input, so they need a real terminal):

```bash
bash utilities/set-env-passwords.sh <env>
```

Never ask the user to paste a password into the conversation. If the secrets
file itself does not exist, that is
[`/sales-demos-first-time`](https://github.com/ericcames/sales.demos/blob/main/.claude/skills/sales-demos-first-time/SKILL.md)
instead.

This check sees only *presence*. A password left over from the previous
environment reads as present — the token derivation below is what catches it.

Then derive a fresh `openshift_api_token` and store it in the vault:

```bash
bash utilities/derive-ocp-token.sh "$ENV" --update-vault
```

This OAuth-authenticates with `kubeadmin_password`, reads (or creates) a
long-lived ServiceAccount token from the cluster, and writes it to
`env_secrets.<env>.openshift_api_token` in the vault. If it fails, the cluster
is unreachable or the kubeadmin password is wrong — stop and tell the user.
A stale `kubeadmin_password` from the old environment is the usual cause; the
fix is `bash utilities/set-env-passwords.sh <env>`, then re-run this step.

## Step 5 — Run preflight

```bash
./utilities/preflight.sh "${ENV}" --k8s
```

If any check fails, stop and tell the user which one failed and the fix.

## Step 6 — Test cluster reachability

Resolve the API URL and token, then confirm the cluster answers:

```bash
VAULT_ID="sales.demos@$HOME/secrets/.vault_pass_sales_demos"

OCP_URL=$(ansible -i inventory --limit "$ENV" aap -m debug --vault-id "$VAULT_ID" \
  -a 'msg={{ openshift_api_url }}' 2>/dev/null \
  | sed -n 's/.*"msg": "\(.*\)"/\1/p')

OCP_TOKEN=$(ansible-vault view playbooks/group_vars/all/secrets.yml \
  --vault-id "$VAULT_ID" 2>/dev/null \
  | ENV="$ENV" python3 -c \
    'import sys,yaml,os; print(yaml.safe_load(sys.stdin)["env_secrets"][os.environ["ENV"]]["openshift_api_token"])')

python3 - <<'PY'
import os, ssl, json, urllib.request
ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
req = urllib.request.Request(os.environ["OCP_URL"].rstrip("/") + "/apis",
                             headers={"Authorization": "Bearer " + os.environ["OCP_TOKEN"]})
resp = json.load(urllib.request.urlopen(req, context=ctx, timeout=20))
print(f"Cluster is reachable — {len(resp['groups'])} API groups")
PY
```

If the cluster does not answer, stop. Re-run `derive-ocp-token.sh` to get a
fresh token, or check `kubeadmin_password` in the vault.

## Step 7 — Run setup.yml

This is the main event. All 14 stages, ~40-50 minutes (stage 1 reboots the node).

```bash
mkdir -p ~/ansible-logs
export ANSIBLE_LOG_PATH=~/ansible-logs/sales-demos-bootstrap-${ENV}-$(date +%F-%H%M).log

./utilities/run-ansible.sh playbooks/setup.yml \
  -i inventory --limit "$ENV" \
  -e target_env="$ENV" \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

Tell the user this takes ~40-50 minutes — stage 1 tunes kubelet disk management and reboots the node, which is why it runs first. The timing summary at the end shows
per-stage elapsed times.

If it fails, check the log at `$ANSIBLE_LOG_PATH` and see the failure table
in
[`/sales-demos-setup`](https://github.com/ericcames/sales.demos/blob/main/.claude/skills/sales-demos-setup/SKILL.md).

## Step 8 — Set up MCP servers

Invoke
[`/sales-demos-mcp`](https://github.com/ericcames/sales.demos/blob/main/.claude/skills/sales-demos-mcp/SKILL.md)
to generate kubeconfigs, AAP bearer tokens, and register all MCP servers for
the new cluster.

## Step 9 — Update local.yml with probe results

`setup.yml` stage 10 already ran `probe_env.yml` and printed the recommended
`available_memory_gb`. Update `local.yml` with that value so Terraform uses the
real capacity, not a hardcoded guess.

## Step 10 — Verify env-urls

`setup.yml` stage 9 already generated the env-urls file. Verify it exists and
references the new cluster:

```bash
grep "$ENV" env-urls.yml 2>/dev/null || echo "env-urls.yml missing or does not reference $ENV"
```

## Step 11 — Update settings.local.json

Check `~/.claude/settings.local.json` (or `.claude/settings.local.json` in
the repo) for WebFetch domain allowlists referencing old cluster IDs. If
found, update them to the new cluster's domain. This is a local file and is
not committed.

## Step 12 — Final verification

Before the restart, confirm every MCP credential points at the new cluster
**and that nothing will shadow them**:

```bash
bash utilities/check-mcp-staleness.sh "$ENV"
```

Fix anything it reports first. A restart cannot repair a local-scope
registration left over from before #515: it outranks `.mcp.json`, so the
server keeps dialling the old cluster however fresh `.aap/` is (#603).

The MCP servers need a Claude Code restart to take effect. Tell the user:

> Restart Claude Code to pick up the new MCP servers, then verify with
> lightweight calls:
>
> - `mcp__openshift-<env>__namespaces_list` (fieldSelector=metadata.name=default)
> - `mcp__aap-<env>__me_list`
>
> Report **Live** if data comes back, **Dead** if it errors.

## Step 13 — Print summary

**Do not type product hostnames into the summary. Take them from `env-urls.yml`**,
the file Step 10 verified, and prove each one answers before listing it. A
hardcoded host here once printed `https://ao-eda.<apps_domain>` for Automation
Orchestrator, a Route that does not exist (#596).

`env-urls.yml` builds each host from a fixed Route prefix plus the apps domain.
It does not ask the cluster, so the curl is what proves the link. The block
reads only the URL lines. The `credentials:` section of the same file is never
printed:

```bash
awk -v env="$ENV:" '$0==env{p=1;next} /^[^ #]/{p=0} p && /^  [a-z_]+: "https:\/\//' env-urls.yml \
  | sed -E 's/^  ([a-z_]+): "([^"]+)"/\1 \2/' \
  | while read -r name url; do
      printf '%-12s %s %s\n' "$name" "$(curl -sk -m 15 -o /dev/null -w '%{http_code}' "$url")" "$url"
    done
```

Print a final summary covering:

- The timing summary from setup.yml (per-stage and total)
- Every URL from the block above with its status. List a `200`/`302` as ready.
  **`ocp_oauth` returns `403` on a healthy cluster**, because the OAuth server's
  root refuses anonymous requests (measured on sandbox), so treat its `403` as
  ready too. Report anything else, such as a `503` for a Route with no backend or
  `ao` when `install_ao=false`, as **not answering**, never as a working link.
- MCP: deployed in-cluster
- `available_memory_gb` from the probe
- What is ready and what needs a restart

## What this does NOT do

- **Does not commit `connection.yml`.** Uses `local.yml` (gitignored) so there
  is nothing to push. Committing `connection.yml` (`utilities/update-connection.sh`)
  is a separate step for when the environment is stable; it refreshes the
  upstream reference for fresh clones.
- **Does not commit anything.** All changes are to gitignored files (`local.yml`,
  kubeconfigs, bearer tokens, `settings.local.json`).
- **Does not create the vault from scratch.** That is
  [`/sales-demos-first-time`](https://github.com/ericcames/sales.demos/blob/main/.claude/skills/sales-demos-first-time/SKILL.md).
  Run it first if the secrets file does not exist. Per-environment passwords
  go in with `utilities/set-env-passwords.sh`; `openshift_api_token` is derived
  automatically in step 4.
- **Does not need a commit for AAP to see the new cluster.** `setup.yml` runs
  `config.yml`, which resolves `local.yml` on the laptop and writes the
  effective values into the AAP inventory as host variables. Job templates
  read those, not `connection.yml` from the SCM checkout.
- **Does not run link_hub.yml.** Attaching the Galaxy credential to the
  organization is opt-in and separate — see
  [`/pah-link-aap`](https://github.com/ericcames/sales.demos/blob/main/.claude/skills/pah-link-aap/SKILL.md).

## If it fails

Most failures are in the `setup.yml` run (step 7). See the failure table in
[`/sales-demos-setup`](https://github.com/ericcames/sales.demos/blob/main/.claude/skills/sales-demos-setup/SKILL.md).

| Symptom | Cause | Fix |
|---|---|---|
| Vault credentials missing (step 4) | New environment, vault not updated | `bash utilities/set-env-passwords.sh <env>` in a terminal |
| Secrets file does not exist (step 4) | Machine never set up | Run [`/sales-demos-first-time`](https://github.com/ericcames/sales.demos/blob/main/.claude/skills/sales-demos-first-time/SKILL.md) |
| Token derivation fails (step 4) | kubeadmin_password stale from the old environment, or cluster unreachable | `bash utilities/set-env-passwords.sh <env>`; verify cluster DNS resolves |
| Cluster unreachable (step 6) | Environment expired or not provisioned | Check RHDP environment status; re-run `derive-ocp-token.sh` |
| `setup.yml` fails (step 7) | See the setup skill's failure table | Check `$ANSIBLE_LOG_PATH` |
| MCP servers fail (step 8) | Kubeconfig or token stale | Re-run [`/sales-demos-mcp`](https://github.com/ericcames/sales.demos/blob/main/.claude/skills/sales-demos-mcp/SKILL.md) |
| `aap-<env>` still dials the old cluster after a restart (step 12) | A pre-#515 local-scope registration outranks `.mcp.json` (#603) | `claude mcp remove aap-<env> -s local` from the main checkout, then restart — `check-mcp-staleness.sh` names it |

Never paste a live cluster hostname or token into a commit message, issue, or
PR. This repo is public — see `CLAUDE.md`.
