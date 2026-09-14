---
name: sales-demos-first-time
description: "First-time setup for the sales.demos repo on a new machine. Checks and guides every local prerequisite — Automation Hub token, the vault password and the secrets file you build from the example, pinned collections, the python kubernetes client, the CLI tools (oc, terraform, virtctl, helm), the run-log directory, and the environment's passwords — then validates each one. TRIGGER when: the user is new to this repo, asks how to get started, says prerequisites are missing, or hits errors about vault decryption, a missing vault password, `couldn't resolve module/action`, or an undefined connection variable. SKIP: if setup is already done and the user wants to point at a new environment — that is sales-demos-bootstrap — or run a phase, which is that phase's own skill."
---

# sales-demos-first-time

Walks a new machine through every local prerequisite for this repo, then
validates them. Run once per machine; after that point it at an RHDP cluster
with [`/sales-demos-bootstrap`](https://github.com/ericcames/sales.demos/blob/main/.claude/skills/sales-demos-bootstrap/SKILL.md).

**This repo is self-contained.** Every skill it needs lives in
`.claude/skills/` and is discovered natively — no marketplace, no plugin. Do not
send the user to a skill from another repo or plugin; if something is missing
here, add it here. The `sales-demos-` prefix keeps these unambiguous when other
skills happen to be loaded on the same machine.

## Orientation

Print this once at the start. Do not repeat it on later steps.

```
Setting up sales.demos on this machine. About 10 minutes, once.

  1. Automation Hub token          ~/.ansible.cfg
  2. Vault password                ~/secrets/.vault_pass_sales_demos
  3. Pinned collections            via /sales-demos-collections-sync
  4. Python kubernetes client
  4.5 CLI tools                    oc, terraform, virtctl, helm (+ optional)
  5. Run-log directory             ~/ansible-logs/
  6. Your environment's values     local.yml + set-env-passwords.sh + derived API token

Nothing here has to be asked of anyone. Since #130 you create the vault
password and the secrets file yourself — step 2, case A.
```

Confirm the working directory first. Everything below assumes the repo root:

```bash
test -f playbooks/setup.yml && test -d inventory/group_vars/aap \
  && echo "✅ in the sales.demos repo" \
  || echo "❌ wrong directory — cd into the sales.demos clone and re-run"
```

If that fails, stop:

```
❌ Run this from inside the sales.demos repo.

  git clone https://github.com/ericcames/sales.demos.git
  cd sales.demos
  claude .
```

## Step 0 — Audit what already exists

Read-only. Run it all, then work only on what is missing.

```bash
test -f ~/.ansible.cfg && grep -q 'galaxy_server.rh_certified' ~/.ansible.cfg \
  && echo "EXISTS   Hub token in ~/.ansible.cfg" || echo "MISSING  Hub token"
test -s "${SALES_DEMOS_VAULT_PASS:-$HOME/secrets/.vault_pass_sales_demos}" \
  && echo "EXISTS   vault password" || echo "MISSING  vault password  <-- blocker"
test -f playbooks/group_vars/all/secrets.yml \
  && echo "EXISTS   secrets.yml" || echo "MISSING  secrets.yml  <-- blocker, build it from the .example"
test -f ansible.cfg \
  && echo "PROBLEM  project-local ansible.cfg present" || echo "OK       no project-local ansible.cfg"
ansible-galaxy collection list kubernetes.core 2>/dev/null | grep -q kubernetes.core \
  && echo "EXISTS   collections" || echo "MISSING  collections"
python3 -c "import kubernetes" 2>/dev/null \
  && echo "EXISTS   python kubernetes client" || echo "MISSING  python kubernetes client"
test -d ~/ansible-logs \
  && echo "EXISTS   ~/ansible-logs" || echo "MISSING  ~/ansible-logs"
for tool in oc terraform virtctl helm; do
  command -v "$tool" >/dev/null \
    && echo "EXISTS   $tool" || echo "MISSING  $tool"
done
ls inventory/group_vars/*/local.yml >/dev/null 2>&1 \
  && echo "EXISTS   local.yml override(s) — you have repointed at least one env" \
  || echo "NONE     no local.yml — you will run against the committed clusters"
```

## Step 1 — Automation Hub token

`~/.ansible.cfg` needs three galaxy server stanzas — certified, validated, and
community. The `rh_certified` token does two jobs here: it is what
`ansible-galaxy` uses to install Red Hat certified collections, **and** it is
read at run time as `automation_hub_token` via an `ini` lookup, so there is no
second copy in the vault to go stale. The same token authenticates both
`rh_certified` and `rh_validated`.

```bash
grep -A3 'galaxy_server.rh_certified' ~/.ansible.cfg | grep -qE '^token=.+' \
  && echo "✅ token present" || echo "❌ no token"
```

If missing, load one at https://console.redhat.com/ansible/automation-hub/token,
then add these stanzas to `~/.ansible.cfg`:

```ini
[galaxy]
server_list = rh_certified, rh_validated, community

[galaxy_server.rh_certified]
url=https://console.redhat.com/api/automation-hub/content/published/
auth_url=https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token
token=<your token>

[galaxy_server.rh_validated]
url=https://console.redhat.com/api/automation-hub/content/validated/
auth_url=https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token
token=<your token>

[galaxy_server.community]
url=https://galaxy.ansible.com/
```

Use `~/.ansible.cfg`, **not** `~/.ansible/ansible.cfg`. The latter is a stale
leftover on some machines; this repo reads the former.

**Never create a project-local `ansible.cfg`.** Ansible picks one cfg file and
does not merge, so a local one shadows `~/.ansible.cfg` and breaks certified
installs. Set options via CLI flags or environment variables instead.

## Step 2 — Vault password and the secrets file

`playbooks/group_vars/all/secrets.yml` is **not in this repo**. It is
gitignored (#130), because this repo is public and shipping one person's
encrypted credentials would hand everyone else a blob they cannot decrypt and
cannot replace without diverging from upstream. Without this file, every
playbook fails at the first templated credential.

There are two situations. Work out which one you are in first:

```bash
test -f playbooks/group_vars/all/secrets.yml \
  && echo "file present — you need the password that matches it (case B)" \
  || echo "no file — you are building one (case A)"
```

### Case A — a fresh machine, no file

You create both, and **you choose the password**. There is nothing to ask
anyone for.

```bash
mkdir -p ~/secrets && chmod 700 ~/secrets
printf '%s\n' '<a long random passphrase>' > ~/secrets/.vault_pass_sales_demos
chmod 600 ~/secrets/.vault_pass_sales_demos

cp playbooks/group_vars/all/secrets.yml.example \
   playbooks/group_vars/all/secrets.yml
```

Now fill in real values. `secrets.yml.example` documents every key and where to
get it, and CI keeps it honest — `utilities/check-secrets-example.py` fails the
build if the code reads a key the example does not declare (#128). Not every
key is needed on day one — tell the user which ones matter now:

| Keys | Needed |
|---|---|
| `vaulted_subscriptions_client_id`, `vaulted_subscriptions_client_secret` | Before `config.yml`. Must be **present** — `CHANGEME` lets the apply succeed, blank breaks it |
| `env_secrets.<env>.aap_password`, `.kubeadmin_password` | Before touching an environment — step 6 |
| `env_secrets.<env>.openshift_api_token` | Never typed. Leave the placeholder; step 6 derives it |
| `rhsm_org_id`, `rhsm_activation_key` | Before a Linux guest registers (Phase 4) — step 7 checks them |
| `demo_ssh_private_key`, `.linux_admin_password`, `.windows_admin_password` | Before provisioning demo VMs. Windows needs 14+ characters |
| `quay_username`, `quay_password` | Windows golden image only |
| `grafana_cloud_*` | Grafana Cloud only |

Then encrypt:

```bash
ansible-vault encrypt playbooks/group_vars/all/secrets.yml \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

**The `sales.demos` vault-id label is not cosmetic.** It is baked into the
file's header, and `inventory/group_vars/aap/controller_credentials.yml` builds
the AAP Vault credential against that exact label. Encrypt with a different
label and AAP will not use the credential.

### Case B — someone shared their environment with you

You need **both** the file and the password; the password alone is no longer
enough, because the file is not in git. Get them over a private channel — never
in an issue, a PR, or this repo.

### Either way, verify — do not assume

```bash
ansible-vault view playbooks/group_vars/all/secrets.yml \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos >/dev/null 2>&1 \
  && echo "✅ vault password works" \
  || echo "❌ decryption failed — wrong password, or the file was encrypted with a different vault-id"
```

**Back up both the file and the password.** Since #130 neither is in git, so
nothing can restore them. Losing the password makes the file unrecoverable;
losing the file loses both environments' credentials.

**Keeping vault passwords somewhere else?** Export `SALES_DEMOS_VAULT_PASS` with
the full path. Every script that reads the vault (`make-kubeconfig.sh`,
`derive-ocp-token.sh`, `set-env-passwords.sh` and the rest of `utilities/`) and
the AAP Vault credential built by `inventory/group_vars/aap/main.yml` honour that
one variable, so they cannot end up disagreeing (#131).
The default stays `~/secrets/.vault_pass_sales_demos`, and every command below
spells that path out because it is still the convention.

## Step 3 — Collections

Do not hand-install. Use the skill that already owns this, which pins, installs,
and verifies that what is installed matches what is pinned:

```
/sales-demos-collections-sync
```

Collections install to `~/.ansible/collections` and are **never** vendored into
the repo.

## Step 4 — Python kubernetes client

`kubernetes.core` needs it, and Ansible must find it under the *same* interpreter
that runs `ansible-playbook`:

```bash
python3 -c "import kubernetes, sys; print('✅', sys.executable)" \
  || pip install --user kubernetes
```

The inventory pins `ansible_python_interpreter` to `{{ ansible_playbook_python }}`
precisely so discovery cannot pick a different interpreter that lacks this.

## Step 4.5 — Command-line tools the playbooks shell out to

Ansible collections are not enough. Four binaries became hard requirements as
the phases landed, and a machine without them completes every other step here
and still cannot set up an environment or provision a VM.

```bash
# oc — the OpenShift CLI. prepare_env.yml, probe_env.yml and the make-*-mcp.sh
# credential scripts shell out to it. (The API token is NOT fetched with oc —
# derive-ocp-token.sh does that with curl in step 6.)
command -v oc >/dev/null && echo "✅ $(oc version --client 2>/dev/null | head -1)" \
  || echo "❌ oc missing — download it from the OpenShift console's CLI tools page"

# terraform — provision_vm.yml and teardown.yml invoke it directly.
command -v terraform >/dev/null && echo "✅ $(terraform version | head -1)" \
  || echo "❌ terraform missing — https://developer.hashicorp.com/terraform/install"

# virtctl — the ONLY way to SSH a demo VM from a laptop. AAP does not need it
# (it reaches VMs over in-cluster DNS) which is why the execution environment
# deliberately does not ship it. You are outside the cluster; you do.
command -v virtctl >/dev/null && echo "✅ virtctl" \
  || echo "❌ virtctl missing — download it from the OpenShift console's CLI tools page"

# helm — portal.yml (the self-service portal stage of setup.yml) drives
# kubernetes.core.helm, which wraps the binary. The EE has it since #324; a
# laptop run needs its own.
command -v helm >/dev/null && echo "✅ helm $(helm version --short)" \
  || echo "❌ helm missing — https://helm.sh/docs/intro/install/"

# podman — only needed to BUILD the execution environment (/sales-demos-ee-build).
# Skip if you never rebuild it.
command -v podman >/dev/null && echo "✅ $(podman --version)" || echo "⚠️  podman missing (only needed to build the EE)"
command -v ansible-builder >/dev/null && echo "✅ ansible-builder" || echo "⚠️  ansible-builder missing (only needed to build the EE)"

# node/npx — only needed for the MCP servers (/sales-demos-mcp): the OpenShift
# servers launch kubernetes-mcp-server, and the AAP and portal bridges
# (utilities/*-mcp-stdio.sh) run `npx supergateway`. Nothing else uses Node.
# Upstream publishes a standalone kubernetes-mcp-server binary
# (https://github.com/containers/kubernetes-mcp-server/releases), but that does
# not cover the supergateway bridges.
command -v npx >/dev/null && echo "✅ npx ($(node --version))" \
  || echo "⚠️  npx missing (only needed for /sales-demos-mcp)"

# registry.redhat.io login — needed to pull the EE base image when building.
podman login --get-login registry.redhat.io >/dev/null 2>&1 \
  && echo "✅ logged in to registry.redhat.io" \
  || echo "⚠️  not logged in — run: podman login registry.redhat.io"
```

`oc`, `terraform`, `virtctl` and `helm` are the four that block real work. The podman pair only
matter if you are rebuilding the execution environment, which is rare — it is
published to quay and mirrored into each environment's Private Automation Hub.
`npx` matters only for the MCP servers, and is the one prerequisite here that is
not Python, Ansible or a Red Hat tool — worth knowing before it surprises you.

## Step 5 — Run-log directory

`setup.yml` takes 25–30 minutes. If it fails and the terminal is gone, so is the
evidence.

```bash
mkdir -p ~/ansible-logs && echo "✅ ~/ansible-logs"
```

Logs live **outside the repo** on purpose — this repo is public, and keeping them
out entirely beats relying on an ignore rule. Every run should set:

```bash
export ANSIBLE_LOG_PATH=~/ansible-logs/sales-demos-$(date +%F).log
```

**Do not pipe through `tee`.** In a pipeline the exit status comes from `tee`,
not from `ansible-playbook`, so a failed run can report success. That is not
hypothetical — it caused a real misread during Phase 0.

## Step 6 — Your environment's values

Two places, by design. Non-secrets are committed; only credentials are vaulted.

```bash
ENV=${ENV:-sandbox}
ansible -i inventory --limit "$ENV" aap -m debug \
  -a 'msg={{ aap_hostname }}' 2>/dev/null | grep msg
```

**That prints the value actually in effect, which is the only one worth
checking.** `connection.yml` is committed with a working RHDP cluster — there
are no `cluster-<id>` placeholders to look for, so grepping the file tells you
nothing about whether it is *yours*.

If the hostname is not your environment, create a gitignored `local.yml`
overlay beside `connection.yml`, holding **only the keys that differ** — not a
copy of the file; everything else keeps coming from upstream. If the user has
an AAP URL, `/sales-demos-bootstrap` writes this for them; by hand:

```bash
cat > inventory/group_vars/$ENV/local.yml <<'YAML'
---
aap_hostname: "aap-aap.apps.cluster-<id>.dyn.redhatworkshops.io"
openshift_api_url: "https://api.cluster-<id>.dyn.redhatworkshops.io:6443"
openshift_apps_domain: "apps.cluster-<id>.dyn.redhatworkshops.io"
YAML
```

Re-run the command above; it must now print your hostname. **The filename must
be `local.yml`** — files in a `group_vars/` directory load in sorted order and
the last wins, and `connection.local.yml` sorts *before* `connection.yml`, so it
would be silently ignored and leave you pointed at the committed cluster.

**The same `local.yml` serves AAP job templates** — do not tell the user to
commit `connection.yml` for AAP. Gitignored files are not in AAP's SCM checkout,
but `config.yml` runs on the laptop, resolves the effective values and writes
them into the AAP inventory as host variables (#528), which job templates read.
Committing `connection.yml` (`utilities/update-connection.sh`) only refreshes
the upstream reference for fresh clones. This replaced #166's rule. A **fork**
still repoints `sales_demos_scm_url`, but that is about whose code AAP syncs,
not which cluster it targets.

Then the two passwords from the RHDP environment page. **Never ask the user to
paste a password into the conversation.** Tell them to run this in a terminal
in the repo — the prompts hide input, so it needs a real terminal, and Enter
keeps an existing value:

```bash
bash utilities/set-env-passwords.sh "$ENV"
```

Now derive `openshift_api_token` automatically from `kubeadmin_password` (it
logs in to the cluster `local.yml` points at):

```bash
bash utilities/derive-ocp-token.sh "$ENV" --update-vault
```

This OAuth-authenticates with `kubeadmin_password`, reads (or creates) a
long-lived ServiceAccount token from the cluster, and writes it to
`env_secrets.<env>.openshift_api_token` in the vault (#559). No manual
copy-paste needed — the old flow was unreliable because the RHDP portal
renders em dashes instead of hyphens, corrupting the JWT.

## Step 7 — Validate everything

Do not declare success until both of these pass. Together they exercise the real
path: inventory resolution, the vault, and the ini lookup.

**It takes two commands, and that is not an accident.** The two kinds of value
live in two different directories, and only one of them is reachable from an
ad-hoc `ansible` call:

- `aap_env_name`, `aap_hostname`, `automation_hub_token` come from
  `inventory/group_vars/`, which sits beside the inventory.
- `aap_password`, `kubeadmin_password` and `openshift_api_token` come from `env_secrets` in
  `playbooks/group_vars/all/secrets.yml`, which sits beside the **playbooks**.

Ansible loads a `group_vars/` directory adjacent to the inventory or adjacent to
a playbook. An ad-hoc `ansible` command has no playbook, so it never loads the
second one and any reference to it dies with `'env_secrets' is undefined`. That
is by design — see `CLAUDE.md` → *Secrets: exactly one mechanism* — and this
step used to try to read all five in one call, so it could never pass on any
machine (#86).

```bash
ENV=${ENV:-sandbox}
VAULT_ID="sales.demos@$HOME/secrets/.vault_pass_sales_demos"

# 1. Inventory-resolved values, plus the ini lookup into ~/.ansible.cfg.
ansible -i inventory --limit "$ENV" aap -m debug --vault-id "$VAULT_ID" \
  -a 'msg="env={{ aap_env_name }} host_set={{ aap_hostname is defined }} hub_set={{ automation_hub_token | length > 20 }}"'
```

`env` must match what you asked for and both `_set` values must be `True`. If
`env` is wrong, your `--limit` is wrong — the environments are deliberately
isolated so one cannot borrow another's credentials.

```bash
# 2. Vaulted credentials, read through the vault rather than the inventory.
ansible-vault view playbooks/group_vars/all/secrets.yml --vault-id "$VAULT_ID" \
  | ENV="$ENV" python3 -c '
import sys, yaml, os
env = os.environ["ENV"]
doc = yaml.safe_load(sys.stdin) or {}
e = (doc.get("env_secrets") or {}).get(env, {})
def filled(v):
    return bool(v) and "CHANGEME" not in str(v)
pw = e.get("aap_password", "")
tok = e.get("openshift_api_token", "")
pw_set = filled(pw)
kube_set = filled(e.get("kubeadmin_password", ""))
token_ok = tok.startswith("sha256~") or (tok.startswith("eyJ") and "." in tok)
rhsm_ok = filled(doc.get("rhsm_org_id")) and filled(doc.get("rhsm_activation_key"))
print("env=%s pw_set=%s kube_set=%s token_ok=%s rhsm_ok=%s" % (env, pw_set, kube_set, token_ok, rhsm_ok))
'
```

All four must be `True`. `token_ok` is only true once step 6's derivation has
run, and it checks the shape rather than mere presence: a
value that is non-empty but not a recognised token form will fail later as a
confusing `401`, which is exactly how #86 hid for as long as it did. Both
`sha256~` OAuth tokens and `eyJ` ServiceAccount JWTs are accepted; an Ansible
error string (the #86 failure mode) contains spaces and starts with neither
prefix, so it is still rejected.

**`rhsm_ok` is checked here because it fails LATE and far from its cause.**
`rhsm_org_id` and `rhsm_activation_key` are top-level keys, not per-environment
ones, and nothing needs them until Phase 4 registers a guest against the Red Hat
CDN — where `playbooks/roles/linux_register` asserts them and stops. They were
missing from `secrets.yml.example` entirely, so a secrets file built from it
passed every preflight and then died there (#128). Get them from
https://console.redhat.com/insights/connector/activation-keys.

## When it all passes

Tell the user setup is complete and point them at the
[New environment quick start](https://ericcames.github.io/sales.demos-docs/reference/new-environment/#quick-start) — `set-env-passwords.sh`, then
[`/sales-demos-bootstrap`](https://github.com/ericcames/sales.demos/blob/main/.claude/skills/sales-demos-bootstrap/SKILL.md) with their AAP
URL. `/sales-demos-setup` re-runs only the cluster setup on an environment that
is already pointed at; `/sales-demos-collections-sync` if they only wanted
collections.

## If something fails

| Symptom | Cause | Fix |
|---|---|---|
| `Decryption failed` | Wrong vault password | Re-check with the verify command in step 2 |
| `Attempting to decrypt but no vault secrets found` | `--vault-id` missing | Add it to the command |
| `couldn't resolve module/action` | Collections not installed | `/sales-demos-collections-sync` |
| `Failed to import the required Python library (kubernetes)` | Wrong interpreter or missing client | Step 4 |
| Certified collection install 401s | Hub token missing or stale | Step 1 |
| `env=` is not what you asked for | Wrong `--limit` | Use `--limit sandbox`, `--limit demo` or `--limit edge` |
| `derive-ocp-token.sh` reports a 401 | `kubeadmin_password` is the previous environment's | `bash utilities/set-env-passwords.sh <env>` in a terminal, then derive again |
