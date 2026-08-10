---
name: sales-demos-first-time
description: "First-time setup for the sales.demos repo on a new machine. Checks and guides every local prerequisite — Automation Hub token, the vault password that decrypts the committed secrets, pinned collections, the python kubernetes client, and the run-log directory — then validates each one. TRIGGER when: the user is new to this repo, asks how to get started, says prerequisites are missing, or hits errors about vault decryption, a missing vault password, `couldn't resolve module/action`, or an undefined connection variable. SKIP: if setup is already done and the user wants to run a phase — that is ocpvirt-setup."
---

# sales-demos-first-time

Walks a new machine through every local prerequisite for this repo, then
validates them. Run once per machine; after that go straight to
`/ocpvirt-setup`.

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
  3. Pinned collections            via /collections-sync
  4. Python kubernetes client
  5. Run-log directory             ~/ansible-logs/
  6. Your environment's values     connection.yml + the vault

One of these you cannot create yourself — see step 2.
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
test -s ~/secrets/.vault_pass_sales_demos \
  && echo "EXISTS   vault password" || echo "MISSING  vault password  <-- blocker"
test -f ansible.cfg \
  && echo "PROBLEM  project-local ansible.cfg present" || echo "OK       no project-local ansible.cfg"
ansible-galaxy collection list kubernetes.core 2>/dev/null | grep -q kubernetes.core \
  && echo "EXISTS   collections" || echo "MISSING  collections"
python3 -c "import kubernetes" 2>/dev/null \
  && echo "EXISTS   python kubernetes client" || echo "MISSING  python kubernetes client"
test -d ~/ansible-logs \
  && echo "EXISTS   ~/ansible-logs" || echo "MISSING  ~/ansible-logs"
```

## Step 1 — Automation Hub token

`~/.ansible.cfg` needs an `rh_certified` token. It does two jobs here: it is what
`ansible-galaxy` uses to install Red Hat certified collections, **and** it is
read at run time as `automation_hub_token` via an `ini` lookup, so there is no
second copy in the vault to go stale.

```bash
grep -A3 'galaxy_server.rh_certified' ~/.ansible.cfg | grep -qE '^token=.+' \
  && echo "✅ token present" || echo "❌ no token"
```

If missing, get one from **console.redhat.com → Automation Hub → Connect to Hub →
Load token**, then add to `~/.ansible.cfg`:

```ini
[galaxy_server.rh_certified]
url=https://console.redhat.com/api/automation-hub/content/published/
auth_url=https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token
token=<your token>
```

Use `~/.ansible.cfg`, **not** `~/.ansible/ansible.cfg`. The latter is a stale
leftover on some machines; this repo reads the former.

**Never create a project-local `ansible.cfg`.** Ansible picks one cfg file and
does not merge, so a local one shadows `~/.ansible.cfg` and breaks certified
installs. Set options via CLI flags or environment variables instead.

## Step 2 — Vault password (the one you cannot create)

`playbooks/group_vars/all/secrets.yml` is committed to this public repo
**vault-encrypted**. Without the password, every playbook fails at the first
templated credential.

**A new user cannot generate this.** There is no derivation and no recovery —
the file is only as recoverable as the password someone hands you. Ask Eric for
it. Do not invent one, and do not re-encrypt the file with a new password unless
you intend to lock out everyone else.

Once you have it:

```bash
mkdir -p ~/secrets && chmod 700 ~/secrets
printf '%s\n' '<the password>' > ~/secrets/.vault_pass_sales_demos
chmod 600 ~/secrets/.vault_pass_sales_demos
```

Verify it actually decrypts — do not assume:

```bash
ansible-vault view playbooks/group_vars/all/secrets.yml \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos >/dev/null 2>&1 \
  && echo "✅ vault password works" \
  || echo "❌ wrong password — decryption failed"
```

This directory also holds `.vault_pass_azure` and `.vault_pass_qa` for
`aap_config`. Same convention, one file per vault ID.

## Step 3 — Collections

Do not hand-install. Use the skill that already owns this, which pins, installs,
and verifies that what is installed matches what is pinned:

```
/collections-sync
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

Ansible collections are not enough. Three binaries became hard requirements as
Phases 1–3 landed, and a machine without them completes every other step here
and still cannot provision a VM.

```bash
# terraform — provision_vm.yml and teardown.yml invoke it directly.
command -v terraform >/dev/null && echo "✅ $(terraform version | head -1)" \
  || echo "❌ terraform missing — https://developer.hashicorp.com/terraform/install"

# virtctl — the ONLY way to SSH a demo VM from a laptop. AAP does not need it
# (it reaches VMs over in-cluster DNS) which is why the execution environment
# deliberately does not ship it. You are outside the cluster; you do.
command -v virtctl >/dev/null && echo "✅ virtctl" \
  || echo "❌ virtctl missing — download it from the OpenShift console's CLI tools page"

# podman — only needed to BUILD the execution environment (/sales-demos-ee-build).
# Skip if you never rebuild it.
command -v podman >/dev/null && echo "✅ $(podman --version)" || echo "⚠️  podman missing (only needed to build the EE)"
command -v ansible-builder >/dev/null && echo "✅ ansible-builder" || echo "⚠️  ansible-builder missing (only needed to build the EE)"

# registry.redhat.io login — needed to pull the EE base image when building.
podman login --get-login registry.redhat.io >/dev/null 2>&1 \
  && echo "✅ logged in to registry.redhat.io" \
  || echo "⚠️  not logged in — run: podman login registry.redhat.io"
```

`terraform` and `virtctl` are the two that block real work. The podman pair only
matter if you are rebuilding the execution environment, which is rare — it is
published to quay and mirrored into each environment's Private Automation Hub.

## Step 5 — Run-log directory

Phase 0 takes 10–20 minutes. If it fails and the terminal is gone, so is the
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
grep -E '^(aap_hostname|openshift_api_url):' inventory/group_vars/$ENV/connection.yml
```

If those still show `cluster-<id>`, paste the real values from your RHDP
provisioning email. Then add that environment's credentials to the vault:

```bash
ansible-vault edit playbooks/group_vars/all/secrets.yml \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
# set env_secrets.<env>.aap_password and .openshift_api_token
```

RHDP bearer tokens are short-lived — expect to refresh
`openshift_api_token` far more often than anything else here.

## Step 7 — Validate everything

Do not declare success until this passes. It exercises the real path: inventory
resolution, the vault, and the ini lookup together.

```bash
ENV=${ENV:-sandbox}
ansible -i inventory --limit "$ENV" aap -m debug \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos \
  -a 'msg="env={{ aap_env_name }} host_set={{ aap_hostname is defined }} pw_set={{ aap_password | length > 0 }} token_set={{ openshift_api_token | length > 0 }} hub_set={{ automation_hub_token | length > 20 }}"'
```

Every value must be `True` and `env` must match what you asked for. If `env` is
wrong, your `--limit` is wrong — the environments are deliberately isolated so
one cannot borrow another's credentials.

## When it all passes

Tell the user setup is complete and point them at `/ocpvirt-setup` to install
OpenShift Virtualization, or `/collections-sync` if they only wanted collections.

## If something fails

| Symptom | Cause | Fix |
|---|---|---|
| `Decryption failed` | Wrong vault password | Re-check with the verify command in step 2 |
| `Attempting to decrypt but no vault secrets found` | `--vault-id` missing | Add it to the command |
| `couldn't resolve module/action` | Collections not installed | `/collections-sync` |
| `Failed to import the required Python library (kubernetes)` | Wrong interpreter or missing client | Step 4 |
| Certified collection install 401s | Hub token missing or stale | Step 1 |
| `env=` is not what you asked for | Wrong `--limit` | Use `--limit sandbox` or `--limit demo` |
