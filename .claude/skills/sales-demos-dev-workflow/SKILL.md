---
name: sales-demos-dev-workflow
description: "The end-to-end development and testing cycle for this repo — branch, PR, merge, then config.yml to push AAP config, then launch the Build Demo VM workflow to prove the change works from AAP. TRIGGER when: the user asks how to test a change, wants to push code to AAP, asks about the dev process, says 'how do we work in this repo', or is about to launch individual job templates after a merge instead of the workflow. SKIP: if the user wants first-time machine setup — that is sales-demos-first-time — or EE verification specifically, which is sales-demos-verify-ee."
---

# sales-demos-dev-workflow

Every code change in this repo follows the same three-step cycle. None of the
steps can be skipped, and the order matters.

```
  merge to main ──► config.yml --limit <env> ──► Build Demo VM workflow
       │                    │                            │
  code lands          AAP config updated           full pipeline runs
                      project synced               from AAP, in the EE
```

**Why all three?** `scm_update_on_launch` is `false` on the AAP project, so
launching a workflow after a merge runs whatever revision was last synced.
`config.yml` is the sync. Skip it and you are testing old code and wondering
why your change had no effect.

## Step 1 — Branch, PR, merge

1. **Open a GitHub issue first.** Document before fixing. Label it — run
   `gh label list --repo ericcames/sales.demos` and apply every label that fits.

2. **Branch from `main`:**
   ```bash
   git checkout -b <type>-<issue>-<slug>
   # examples: fix-86-preflight-vault-lookup, docs-191-dev-workflow-skill
   ```
   `<type>` is `fix`, `docs`, or the area. `<slug>` is 2–4 words describing the
   change, not the file. The issue number links the branch back to the decision.

3. **Make changes, commit, push:**
   ```bash
   git push -u origin <branch>
   ```

4. **Open a PR.** Eight CI checks are required:
   `yamllint`, `ansible-lint`, `secret-guard`, `secrets-example-sync`,
   `generated-files`, `skills-frontmatter`, `docs-artifacts-current`,
   `renderer-matches-role`.

5. **Merge.** Claude has standing authorization to merge green PRs in this repo
   without asking. `main` is protected — a PR is always required, even for the
   repo owner.

6. **Delete the local branch after merge:**
   ```bash
   git checkout main && git pull && git branch -d <branch>
   ```
   The remote branch deletes itself (`delete_branch_on_merge` is enabled).
   Pull `main` first so `-d` checks something real.

## Step 2 — `config.yml`

Pushes AAP configuration (credential types, credentials, job templates,
schedules, execution environments) **and syncs the project** to the latest
`main`. This is the only thing that updates what AAP runs.

```bash
mkdir -p ~/ansible-logs
LOGFILE=~/ansible-logs/config-sandbox-$(date +%F-%H%M).log

python3 -c "
import subprocess, sys
r = subprocess.run(
    ['ansible-playbook', 'playbooks/config.yml',
     '-i', 'inventory', '--limit', 'sandbox',
     '-e', 'target_env=sandbox',
     '--vault-id', 'sales.demos@$HOME/secrets/.vault_pass_sales_demos'],
    cwd='$(pwd)')
sys.exit(r.returncode)
" 2>&1 | tee "$LOGFILE"
echo "Log: $LOGFILE"
```

**Why `python3 -c` instead of `ansible-playbook` directly?** Ansible's blocking
IO detection fails under some terminal multiplexers. Wrapping in
`subprocess.run()` avoids `Non-blocking file handles detected`.

**`--limit` is mandatory.** Without it the play matches both environments and
fails an assertion. `target_env` is belt-and-suspenders — it verifies the
inventory resolved to the environment you meant.

**Always log output** to `~/ansible-logs/` with a descriptive filename. The log
is the only evidence if something fails — especially credential type errors,
which are hidden by `no_log: true`.

## Step 3 — Launch the Build Demo VM workflow

**Sales Demos - Build Demo VM** is the four-node workflow that proves everything
works end-to-end:

```
provision ──► register ──► configure ──► check
```

Launch it from AAP — the UI, or via MCP:

```
mcp__aap-sandbox__workflow_job_templates_launch_create
```

All four nodes are idempotent. A second run converges rather than rebuilding.

### Verify

Do not report success on the workflow recap alone — ask the target:

```bash
cd terraform/ocpvirt
curl -sI "$(terraform output -raw web_url)" | head -1
# Expect: HTTP/1.1 200 OK

curl -sI "$(terraform output -raw cockpit_url)" | head -1
# Expect: HTTP/1.1 200 OK
```

SSH into the guest and check the MOTD renders with both URLs.

## Gotchas

| Symptom | Cause | Fix |
|---|---|---|
| `config.yml` fails with a censored error on credential types | AAP rejects `inputs` modifications on credential types that have credentials attached | Delete the credential (API DELETE), then the credential type, then re-run `config.yml` — it recreates both. This is a one-time manual step per schema change. |
| Workflow runs but changes have no effect | `scm_update_on_launch: false` — the project is still on the old revision | Run `config.yml` first. It syncs the project. |
| `ansible-playbook` fails with `Non-blocking file handles detected` | Terminal multiplexer / Claude Code IO interaction | Wrap in `python3 -c "import subprocess; ..."` as shown above |
| MOTD or job template missing a new variable | Project revision lags — read the project update output (`Repository Version <sha>`), not the project's `scm_revision` field | Confirm the sync completed, then re-launch the workflow |

## What this does NOT replace

This skill documents the **development cycle**, not the operational skills that
do the actual work:

| To do this | Use this skill |
|---|---|
| Set up a bare RHDP environment | `/ocpvirt-setup` |
| Provision or rebuild VMs | `/ocpvirt-provision` |
| Tear down VMs | `/ocpvirt-teardown` |
| Run the demo content standalone | `/ocpvirt-demo` |
| Verify a playbook in the EE | `/sales-demos-verify-ee` |
| First-time machine setup | `/sales-demos-first-time` |
