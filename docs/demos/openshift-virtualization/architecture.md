# Architecture — OpenShift Virtualization

Reference for the presenter. What exists, what builds what, and how long each
part takes. Use it to answer "how does that actually work" without guessing.

This describes the demo as it is *shown*. For **why** it is built this way — the
research, the constraints, the decisions and the ones that were reversed — read
[`docs/plan/ocpvirt-demo-plan.md`](../../plan/ocpvirt-demo-plan.md).

---

## The one-button workflow

`Sales Demos - Build Demo VM`. Four job templates chained on success, one survey
that feeds all of them.

```mermaid
flowchart TD
    S["<b>Survey</b><br/>os_type · vm_size_tier"] --> P

    P["<b>Provision VM</b><br/>playbooks/provision_vm.yml<br/><i>terraform apply → register host in AAP</i>"]
    R["<b>Register VMs</b><br/>playbooks/register_vm.yml<br/><i>wait for ssh → attach to the Red Hat CDN</i>"]
    C["<b>Configure VMs</b><br/>playbooks/configure_vm.yml<br/><i>httpd · firewalld · Cockpit · page · patches</i>"]
    K["<b>Check VMs</b><br/>playbooks/check_vm.yml<br/><i>log in, gather facts, cache them in AAP</i>"]

    P -->|success| R
    R -->|success| C
    C -->|success| K

    P -.->|"Route exists, returns 503"| W(["web_url"])
    C -.->|"httpd running, returns 200"| W
```

As the controller draws it, mid-run:

![The workflow visualizer, provision in progress](../../images/aap-workflow-running.png)

The diagram above is a simplification: the real graph is left to right and
carries an explicit `Start` node, with each edge labelled `Run on success`.

**Chained on `success_nodes`, with no failure nodes at all.** A failure stops the
chain rather than cascading — and there is deliberately no incident-creation
path, because a failure node that does nothing useful is worse than an obvious
stop.

**Why a workflow rather than three buttons.** The order is not guessable.
`register` must precede `configure` because the OpenShift Virtualization `rhel9`
boot image ships with **no package repositories**, so every `dnf` task fails on
an unregistered guest. Encoding the sequence means it cannot be got wrong in
front of a customer (`controller_workflows.yml:10-14`).

**Why the wait lives in the playbook, not the workflow.** `provision` returns as
soon as `terraform apply` finishes; the guest takes roughly another minute to
accept ssh. In a workflow the nodes run back to back with no human pause, so
`register_vm.yml` opens with `wait_for_connection` — which also protects the
run-it-by-hand path.

---

## The survey

![The launch survey](../../images/aap-survey.png)

| Question | Variable | Choices | Default |
|---|---|---|---|
| Operating system | `os_type` | `linux` · `windows` · `both` | `linux` |
| VM size tier | `vm_size_tier` | `small-1cpu-2gb` · `medium-1cpu-4gb` · `large-2cpu-6gb` | `small-1cpu-2gb` |

**There is deliberately no question for the target environment.** A dropdown is
one mis-click away from provisioning into the customer-facing cluster. Each
controller's template is templated off its own `aap_env_name`, and
`playbooks/tasks/assert_target_environment.yml` fails the run if `limit` and
`target_env` ever disagree.

---

## Size tiers

Mapped to **repo-owned** `sd1.*` cluster instance types, not Red Hat's shipped
`u1.*` series.

| Tier | Instance type | vCPU / RAM | Linux disk |
|---|---|---|---|
| `small-1cpu-2gb` | `sd1.small` | 1 / 2 GiB | 30 GiB |
| `medium-1cpu-4gb` | `sd1.medium` | 1 / 4 GiB | 30 GiB |
| `large-2cpu-6gb` | `sd1.large` | 2 / 6 GiB | 50 GiB |

**Why not `u1.*`:** that series has no 6 GiB size — it goes 2 / 4 / 8 / 16. At
`u1.large`'s 8 GiB, `os_type=both` needs about 16.6 GiB, which did not fit the
~14 GiB free on the smaller cluster these tiers were designed against.

**That constraint no longer binds, and the tiers were left alone anyway.**
`sales-demos-probe-env` measured 75.63 GiB free on sandbox (2026-09-03) and
`available_memory_gb` is now 67 (#118). `u1.large` would fit comfortably. The
tiers stay at 6 GiB because resizing them is a separate decision with its own
blast radius — the lesson of #100 is that a number moves when something is
measured, not merely when it becomes possible.

**The ceiling is enforced in code.** `terraform/ocpvirt/locals.tf` carries a
`terraform_data.memory_budget` precondition:
`vm_count × (tier_memory + 350 MiB overhead) ≤ available_memory_gb`. An
over-budget request **fails at `plan`** rather than leaving a `Pending` VM while
Terraform reports success.

---

## What Terraform builds

`terraform/ocpvirt/` — one flat module, the official `hashicorp/kubernetes`
provider driving `kubernetes_manifest`. No community KubeVirt provider.

| Resource | Purpose |
|---|---|
| `kubernetes_namespace.demo` | The VM namespace, `sales-demos-<env>` |
| `VirtualMachineClusterInstancetype` ×3 | The `sd1.small` / `.medium` / `.large` types |
| `kubernetes_manifest.linux_vm` | RHEL 9 guest, cloned from the `rhel9` DataSource |
| `kubernetes_manifest.windows_vm` | Wired, cannot boot — see below |
| `kubernetes_service.linux` | **Headless.** Stable in-cluster DNS for the AAP inventory |
| `kubernetes_service.linux_web` | ClusterIP on :80, existing solely to back the Route |
| `kubernetes_manifest.linux_web_route` | The public URL, edge TLS |

**Two Services per Linux VM is not redundancy.** A headless Service gives the VM
a stable DNS name so AAP can reach it, but a headless Service cannot back a
Route — hence a second ClusterIP Service whose only job is to be the Route
target.

**The Route terminates TLS at the edge and redirects http.** Without it Chrome
auto-upgrades to HTTPS, finds no TLS route, and shows "Application is not
available"; forcing `http://` paints "Not secure" for the whole demo. The
platform's wildcard certificate is publicly issued, so this gets a real padlock
with zero certificate management.

**URL shape:** `https://<vm-name>-web-<namespace>.<apps-domain>`

**State lives on the Kubernetes backend** in its own long-lived namespace,
`sales-demos-tfstate`, keyed by environment. Local state is fatal when the run
happens inside an ephemeral execution-environment pod.

---

## What AAP holds

All of it is configuration-as-code under `inventory/group_vars/`, applied by
`playbooks/config.yml`. Nothing is clicked into existence.

| Type | Name |
|---|---|
| Organization | `IT Service Automation` |
| Project | `Sales Demos` |
| Execution environment | `Sales Demos - OCP Virt EE` |
| Credentials | `Sales Demos - Vault` · `Sales Demos - Linux Machine` · `Sales Demos - PAH Registry` |
| Inventory | `Sales Demo VMs` · `Sales Demo VMs - Control` |
| Job templates | `Sales Demos - Provision VM` · `Register VMs` · `Configure VMs` · `Check VMs` · `Run Demo` · `Teardown VMs` |
| Workflow | `Sales Demos - Build Demo VM` |
| Schedules | `Sales Demos - Nightly teardown (6 PM)` (+ a 10 PM safety net in sandbox) |

**Two inventories, one of them empty.** `Sales Demo VMs` holds the demo VMs;
`Sales Demo VMs - Control` stays empty and exists only for teardown, because AAP
locks the hosts of the inventory a running job is using — teardown cannot delete
hosts out from under itself.

**AAP reaches the guests over plain ssh on port 22.** The controller runs on the
same cluster, each VM has a headless Service giving it in-cluster DNS, and there
is no NetworkPolicy in between. No bastion, no agent. `virtctl` is the *laptop*
path only.

**There is no OpenShift credential in AAP.** Every connection value arrives via
the SCM-synced `inventory/hosts.yml` plus the environment's `connection.yml`, so
a new environment is a one-file edit. Credentials arrive at run time through the
Vault credential.

**The execution environment exists for one reason:** the provision playbook
shells out to the `terraform` CLI, and no stock image ships that binary.
Everything else in it is the standard AAP 2.6 base plus the same pinned
collections a laptop installs — so both entry points resolve identical code.

---

## Timing

### One real workflow run, node by node

![The controller's job list for a complete run](../../images/aap-job-timings.png)

Measured, not estimated — this is workflow job 225, start to finish:

| Node | Duration | Share |
|---|---|---|
| Source control update + inventory sync | 6 s + 9 s (parallel) | — |
| **Provision VM** | 36 s | 7% |
| **Register VMs** | 4 m 25 s | 48% |
| **Configure VMs** | 3 m 49 s | 42% |
| **Check VMs** | 5 s | 1% |
| **Whole workflow** | **9 m 9 s** | |

**Ninety percent of the run is register plus configure** — attaching to the CDN
and then pulling packages and patches over it. The machine itself exists in
under 40 seconds. That is the honest shape of the demo, and it is why "the VM
built in 45 seconds" and "the demo takes nine minutes" are both true.

Use `Check VMs` at 5 seconds when someone asks whether the verification step is
real: it logs in, gathers facts and caches them, and that is all it needs to do.

### Everything else

| Step | Time |
|---|---|
| Bare environment → demo-ready | ~20 min (mostly platform provisioning) |
| Install OpenShift Virtualization | ~4 min |
| Readiness proof (`prepare_env.yml`) | ~2 min |
| `terraform apply` returns | ~10 s |
| VM reports `Running` | ~45 s |
| Guest accepts ssh | ~1 min after that |
| Windows golden image (one-time, not yet done) | ~45 min |

---

## Windows

**Wired end to end. Does not boot.**

Terraform creates the VM, the `windemo` inventory group exists with WinRM
configured, and the outputs are the same shape as Linux. What is missing is the
image: OpenShift Virtualization ships `win2k22` as an **empty DataSource
placeholder**, because Red Hat cannot redistribute Windows media.

The provision playbook **warns rather than refuses** — pick `windows` or `both`
and it will build a VM that waits forever on a volume that never imports.

The fix is a one-time golden-image build — import the ISO, install the drivers
and guest agent, sysprep, snapshot, publish to a private registry — tracked in
public as issue #3. Teardown is written to preserve that image so it stays a
one-time cost.

---

## What teardown keeps

| Destroyed | Preserved |
|---|---|
| The demo VMs | OpenShift Virtualization itself |
| Their Services and Route | Boot-source DataSources (incl. the future Windows image) |
| Their AAP host entries | The `sales-demos-tfstate` namespace |
| The RHSM subscription and Insights host | The published container image |

Rebuilding the preserved half costs about 45 minutes, which is why teardown is
deliberately selective rather than a namespace delete.
