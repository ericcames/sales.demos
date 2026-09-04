---
name: sales-demos-verify-ee
description: "Run a playbook inside the execution environment AAP actually uses, instead of beside it on the laptop, so a local run verifies the dependency set production runs on. Wraps utilities/run-in-ee.sh (ansible-navigator + podman) and diffs the result against a laptop run. TRIGGER when: the user is about to merge a playbook change, asks to verify or test a playbook properly, asks whether something will work from AAP, hits a job template failure a laptop run will not reproduce, or sees 'couldn't resolve module/action' at runtime but not locally. SKIP: if the user wants to build or publish the EE image itself — that is sales-demos-ee-build — or just wants to run a phase against a cluster, which is that phase's own skill."
---

# sales-demos-verify-ee

Runs a playbook **inside** `sales-demos-ee`, the image AAP runs job templates on,
rather than beside it on the laptop.

## Why this exists

`ansible-playbook` on your laptop resolves `~/.ansible/collections` and the
system python. An AAP job template resolves whatever the EE baked in. **Those
are two dependency sets and only one of them is what production uses.**

Nothing else here can tell them apart. `README.md` says it outright: *"A green
CI run does not mean a playbook works — the lint gate cannot execute anything."*
So a local run is this repo's only pre-merge verification, and by default it
verifies the wrong one.

Three times now that gap has held a real defect:

| | What it was | What saw it |
|---|---|---|
| #122 | `python3-devel` repointed `/usr/bin/python3` from 3.12 to 3.9, whose site-packages has no `kubernetes` — every `kubernetes.core` task would fail at runtime on an image that built and pushed clean | nothing, until someone ran it in the image |
| #173 | `validate.yml` passes on the laptop, fails in the EE — `check mode and async cannot be used on same task`. Underneath it, `validate.yml` had never once exercised `infra.aap_configuration`'s check-mode paths, on either machine | this skill, first serious use |
| #120 | the gap itself | — |

## What is different, and it is not the collections

Every collection pin matches exactly, laptop and EE. `build-ee.sh` checks that
and is green. **The divergence is underneath them:**

| | ansible-core | python |
|---|---|---|
| Laptop | 2.18.18rc1 | 3.14.7 |
| `sales-demos-ee:v1.1.0` | 2.16.19 | 3.12.13 |

Two minor versions of core apart, and the laptop is on a release candidate.
Nothing in this repo pins or compares ansible-core — `collections/requirements.yml`
pins what sits *on top* of it. That is #173.

**Check this first, every time.** It is one line and it explains most surprises:

```bash
ansible --version | head -1
podman run --rm --user 1000 --entrypoint ansible \
  quay.io/zigfreed/sales-demos-ee:v1.1.0 --version | head -1
```

## Nothing is baked into the image — this is the answer for a customer

The EE is published to a public quay repository. It carries **no credential**,
and that is verifiable rather than asserted:

```bash
podman run --rm --entrypoint /bin/bash quay.io/zigfreed/sales-demos-ee:v1.1.0 \
  -c 'ls /etc/ansible 2>&1; ansible --version | grep "config file"'
# ls: cannot access '/etc/ansible': No such file or directory
#   config file = None

podman history --no-trunc quay.io/zigfreed/sales-demos-ee:v1.1.0 | grep ansible.cfg
# (no match — no layer in the final image copies a config in)
```

`execution-environment.yml` stages `~/.ansible.cfg` into the **galaxy build stage
only**. The final image is built `FROM base` and copies the installed collections
out, not that file. Guarding that in the build so it stays true is #172.

Everything the wrapper needs is therefore mounted at **run time**, read-only,
from your laptop, and nothing is persisted. A bind mount is the same single file
#22 and #68 made authoritative — not a second stored copy of a rotating
credential, which is the thing those issues refused.

## Preflight Check

```bash
# 1. The tools. A launcher can outlive its package — if this raises
#    ModuleNotFoundError, reinstall with: python3 -m pip install --user ansible-navigator
ansible-navigator --version && podman --version

# 2. The image AAP runs, and whether you have it
grep -n 'image:' inventory/group_vars/aap/controller_execution_environments.yml
podman images | grep sales-demos-ee || echo "not local — the wrapper will pull it"

# 3. The vault password, or nothing decrypts
test -s "${SALES_DEMOS_VAULT_PASS:-$HOME/secrets/.vault_pass_sales_demos}" \
  && echo "✅ vault password present" || echo "❌ vault password missing"

# 4. Is the environment up? (RHDP environments expire silently)
curl -sk -o /dev/null -w "API: %{http_code}\n" \
  "$(grep '^openshift_api_url' inventory/group_vars/sandbox/connection.yml | cut -d'"' -f2)/version"
```

## Run

**Take the `ansible-playbook` line out of any skill and put the wrapper in front
of it.** Everything after the playbook is passed through unchanged — same flags,
same `--vault-id`, same `~/` path. That equality is the design; if the two ever
have to be written differently, something is wrong.

```bash
utilities/run-in-ee.sh playbooks/probe_env.yml -i inventory --limit sandbox \
  -e target_env=sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

It prints the resolved image and every mount before it runs, so you can point at
that block and say "that is everything that crosses in".

### The canonical check is `probe_env.yml`

Strictly read-only, `changed=0`, and #100 gives a known-good expected output —
which makes it a **regression test**, not a smoke test. Run it both ways and
compare:

```bash
ansible-playbook playbooks/probe_env.yml -i inventory --limit sandbox \
  -e target_env=sandbox --vault-id sales.demos@~/secrets/.vault_pass_sales_demos

utilities/run-in-ee.sh playbooks/probe_env.yml -i inventory --limit sandbox \
  -e target_env=sandbox --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

`RECOMMENDED available_memory_gb` and the recap must match. Verified 2026-09-04
on sandbox: `63` and `ok=31 changed=0 failed=0` both ways, every allocatable,
requested and free figure identical.

**Two differences are expected and are not defects.** `Free by LIVE USE` moves
between runs — it is live consumption, labelled informational. And the output is
formatted differently: your `~/.ansible.cfg` sets a `yaml` stdout callback, the
EE has no config file at all, so it uses the default. That second one is worth
knowing on its own — it is why AAP job output never looks like your terminal.

### Which playbooks need what

| Playbooks | Needs |
|---|---|
| `probe_env`, `prepare_env`, `install_cnv`, `mcp_server`, `install_ao` | nothing extra — auth is `K8S_AUTH_*` from vars |
| `portal` | nothing extra — its kubeconfig is repo-relative (`.kube/<env>.kubeconfig`) and the repo is mounted at its own host path |
| `provision_vm`, `teardown` | nothing extra, and **this is where it earns most** — the EE pins terraform 1.15.8 and your laptop probably does not |
| `register_vm`, `configure_vm`, `check_vm`, `run_demo` | nothing extra — navigator mounts `~/.ssh` itself |
| `config`, `validate`, `setup`, `sync_hub`, `curate_hub` | `--with-hub-token` |

The wrapper **refuses** rather than warns on that last row. Without the mount the
run does not quietly skip the token: it dies with `Invalid filename: 'None'` —
the `ini` lookup raises on a missing file, it does not return `''`.

```bash
utilities/run-in-ee.sh --with-hub-token playbooks/sync_hub.yml -i inventory \
  --limit sandbox -e target_env=sandbox \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

**A green `sync_hub.yml` here does not mean PAH can run from AAP.** It cannot,
and that has not changed (#68). AAP has no laptop to mount from. This changes the
laptop story only.

### The EE-side failure this skill found, and what fixing it changed (#173)

`validate.yml` used to fail in the EE at
`infra.aap_configuration.gateway_organizations` with *"check mode and async
cannot be used on same task"* while passing on the laptop. **Fixed** — but the
cause was not the one the symptom suggested, and the fix changes how you run it:

**`validate.yml` now requires `--check` and refuses without it.** A play-level
`check_mode: true` sets the *task's* check mode but leaves the
`ansible_check_mode` *variable* False, and every check-mode branch in
`infra.aap_configuration` is written against that variable. So for as long as
this playbook existed, eleven of the roles it runs were taking their non-check
path — asking for `async` while in check mode. Core dropped the guard that
rejects that in 2.17.0 (present through 2.16.19, gone from 2.17.0 on, measured
by unpacking the wheels), so the laptop's 2.18 forgave it and the EE's 2.16
did not.

Three shapes, three answers, and only the last costs anything:

| Roles | How they set `async` | Answer |
|---|---|---|
| 11 controller/gateway | `ansible_check_mode \| ternary(0, 1000)` | `--check`. No coverage lost. |
| 8 `hub_*` | a variable descending from `aap_configuration_async_timeout` | set the parent to `0`. No coverage lost. |
| 1 `gateway_organizations` | flat `async: 1000` — no knob, no guard | skip the role on core < 2.17, loudly. |

Measured after the fix, same commit, same cluster: EE `ok=57 changed=4 failed=0`
against laptop `ok=87 changed=4 failed=0` — identical task banners, identical
`changed`, and the `ok` gap is the organizations role iterating an empty list in
the EE, which the run says out loud.

## Verify against the target, not the recap

The recap tells you Ansible finished, not that the thing happened. After a run
that changes something, ask the cluster or AAP over MCP — `openshift-sandbox`,
`aap-sandbox` — exactly as that phase's own skill says to.

For the wrapper itself, the acceptance test is the `probe_env.yml` diff above.
If the two runs disagree on a measured figure, **the EE and your laptop genuinely
differ** and that is a finding, not noise. Start with the core versions.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `ModuleNotFoundError: No module named 'ansible_navigator'` | launcher in `~/.local/bin` outlived its package | `python3 -m pip install --user ansible-navigator` |
| `could not read the EE tag from inventory/...` | the `image:` line changed shape | fix that file, or set `EE_IMAGE` — the wrapper will not guess |
| `is not present locally and could not be pulled` | not built, or not logged in | `/sales-demos-ee-build`, or `podman login quay.io` |
| `Invalid filename: 'None'` | `~/.ansible.cfg` not mounted | add `--with-hub-token` |
| `Attempting to decrypt but no vault secrets found` | `--vault-id` missing | it is passed through, not supplied — add it to your command |
| Base64-looking noise in a redirected log | ansible-runner event markers; invisible in a terminal | harmless — strip with `sed 's/\x1b\[[0-9;]*[A-Za-z]//g'` when diffing |
| Testing an image you built but have not registered | — | `EE_IMAGE=quay.io/zigfreed/sales-demos-ee:v1.2.0 utilities/run-in-ee.sh ...` |
