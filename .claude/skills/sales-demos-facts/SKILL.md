---
name: sales-demos-facts
description: "Gather, cache and publish a demo guest's Ansible facts — a curated summary in the job log, the full set in AAP's database, and a report at <web_url>/facts.html. Launches Linux Day 2 - Gather Facts or Windows Day 2 - Gather Facts in AAP, or the Day 1 step 5 that does the same work as part of a build. TRIGGER when: the user asks to gather or refresh facts, wants to show AAP's fact cache or a host's Facts tab, asks what AAP knows about a VM, says the Facts tab is empty or stale, wants the fact report republished, or asks about issue #647 or #648. SKIP: if the user wants to build a VM from nothing — that is sales-demos-provision — or wants the CIS compliance report, which is sales-demos-ocpvirt-demo."
---

# sales-demos-facts

Make AAP's fact cache visible. The full `ansible_facts` set lands in AAP's
database, a curated summary prints in the job log, and the same summary is
published as a page on the guest — so the Facts tab and the artifact a customer
can curl say the same thing.

**This skill contains no logic.** The work is in
[`playbooks/roles/demo_facts`](../../../playbooks/roles/demo_facts), included by
[`playbooks/check_linux_vm.yml`](../../../playbooks/check_linux_vm.yml) and
[`playbooks/check_windows_vm.yml`](../../../playbooks/check_windows_vm.yml).

## First: which OS?

| | Linux | Windows |
|---|---|---|
| Group | `linuxweb` | `windemo` |
| Day 2 template | `Linux Day 2 - Gather Facts` | `Windows Day 2 - Gather Facts` |
| Day 1 step that also does it | `Linux Day 1 - 5 Check and Gather Facts` | `Windows Day 1 - 5 Check and Gather Facts` |
| Credential | `Sales Demos - Linux Machine` | `Sales Demos - Windows Machine` |
| Transport | SSH, port 22 | WinRM/NTLM, port 5986 |
| Docroot | `/var/www/html` | `C:\inetpub\wwwroot` |

Ask the cluster when it is not obvious:

```
mcp__openshift-<env>__resources_list  kubevirt.io/v1 VirtualMachine
  namespace: sales-demos-<env>
```

## Nothing writes the cache, and that is the point

`gather_facts: true` in the playbook plus `use_fact_cache: true` on the job
template is the **entire** mechanism. Do not go looking for the task that pushes
facts to AAP — there isn't one, and saying so out loud is half the demo. It is
also why this capability sat unused for so long: the flag has been set since #47
and nothing in the template list mentioned it.

## The inputs are the contract

| Variable | Values | Default (Day 1) | Default (Day 2) |
|---|---|---|---|
| `demo_facts_show_full` | `"false"` · `"true"` | `"false"` | `"false"` |
| `demo_facts_compare` | `"false"` · `"true"` | `"false"` | `"true"` |
| `check_vm_assert_serving` | `true` · `false` | `true` | `false` on Windows |

These names are shared verbatim with the AAP survey and the role defaults.

`demo_facts_compare` is on for Day 2 and off for Day 1 because a VM the chain has
just built has no previous facts to compare against. `check_vm_assert_serving` is
false on the Windows Day 2 template so a down page does not cost you the facts.

## Preflight Check

```bash
# 1. There is a VM to ask
#    mcp__aap-<env>__hosts_list
#    Expect at least one host in linuxweb or windemo. If the count is 0, the
#    VMs are torn down — provision first.

# 2. The template exists and caches
#    mcp__aap-<env>__job_templates_list  search="Gather Facts"
#    Expect use_fact_cache: true on all four. If a template is missing, the
#    branch has not been applied — run /sales-demos-config.

# 3. The host has a web_url, or facts.html has nowhere to go
#    mcp__aap-<env>__hosts_retrieve  id=<host id>
#    Look for web_url in variables. Empty means the VM predates the Route;
#    the run still succeeds and says the report was written but not linked.
```

## Run

Launch **`Linux Day 2 - Gather Facts`** or **`Windows Day 2 - Gather Facts`** in
AAP. Both are labelled `read-only` and are safe mid-demo — they change nothing on
the guest except the report page.

To get facts as part of a build instead, launch `Linux Day 1 - 0 Workflow` or
`Windows Day 1 - 0 Workflow`; step 5 does the same work.

## Verify it in the EE before merging a change

```bash
./utilities/run-in-ee.sh playbooks/check_linux_vm.yml -i inventory --limit linuxweb
```

## The check that matters, either OS

Two copies of the same data, from two directions. **Ask both — neither alone is
the claim being made.**

Ask the controller:

```
mcp__aap-<env>__hosts_ansible_facts_retrieve  id=<host id>
```

`ansible_facts_modified` must be non-null, and `demo_facts_summary` must be
present — that key only exists because the role sets it `cacheable: true`.

Ask the guest:

```bash
curl -sI "<web_url>/facts.html" | head -1     # HTTP/1.1 200 OK
curl -s  "<web_url>/facts.json" | head -20
```

**Then check they agree.** The virtualization field must read `KVM` / `guest` in
the page, in `facts.json` and in the Facts tab. A KubeVirt guest reports the
literal string `"NA"` for both facts, so `| default()` never fires and every
consumer has to normalise it identically — #160 is what it costs when one of them
does not, and `utilities/check-fact-normalisation.py` is what now stops it
happening again.

A green job recap is not the same thing. The recap proves the play ran; it says
nothing about whether AAP persisted anything or whether the page renders.

## Useful knobs

```bash
# Dump the complete fact set to the job log as well (large on Windows).
-e demo_facts_show_full=true

# Skip writing facts.html — cache only, leave the guest's docroot alone.
-e demo_facts_publish=false

# One misbehaving host rather than the whole group.
--limit web-lnx-1.sales-demos-sandbox.svc.cluster.local
```

## If it fails

- **`ERROR! Attempting to decrypt but no vault secrets found`** — the
  `Sales Demos - Vault` credential is not attached. It is required on every
  template here even though this playbook reads no secret, because
  `playbooks/group_vars/all/secrets.yml` is parsed for every play.
- **The Facts tab is still empty after a green run** — the template lost
  `use_fact_cache: true`. Nothing in the playbook writes the cache, so the
  toggle is the only thing that can be wrong. Check it with
  `mcp__aap-<env>__job_templates_retrieve`.
- **`facts.html` 404s but the job was green** — the run had no `web_url` host
  var, so the report was written to the docroot without a link, or
  `demo_facts_publish` was false. The job log's last task says which.
- **The page and `facts.json` disagree about virtualization** — that is #160
  reopening. Run `python3 utilities/check-fact-normalisation.py`; it names the
  copy that moved.
- **A 503 fails the Windows run** — that is `check_vm_assert_serving`, correct on
  the Day 1 chain and wrong for a fact gather. The Day 2 template already sets it
  false; add `-e check_vm_assert_serving=false` if you launched step 5 by hand.
