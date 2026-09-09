locals {
  # OS selection — drives count on per-VM resource blocks.
  #
  # EXACT MATCH, AND `both` IS GONE (#301). State is now keyed per OS as well as
  # per environment (secret_suffix=<env>-<os> in tasks/terraform_ocpvirt.yml), so
  # each state holds exactly one VM and an apply for one OS can no longer plan
  # the other one's VM for destruction. `both` cannot survive that: it would open
  # a THIRD state holding two VMs whose names collide with the two single-OS
  # states, and whichever ran last would fight the others forever.
  create_windows = var.os_type == "windows"
  create_linux   = var.os_type == "linux"

  # T-shirt tier -> repo-owned cluster instance type. Keys match the AAP survey
  # choices exactly. Mapping to instance types rather than raw CPU/memory is
  # deliberate: it is native OpenShift Virt functionality and demos better than
  # hand-rolled domain specs.
  #
  # READ FROM tiers.yaml, NOT DECLARED HERE (#348). Terraform stopped creating
  # the sd1.* objects when they moved to Ansible so they could outlive a per-OS
  # teardown — which put their specs in reach of two languages. That file is the
  # one copy; see its header for why. Terraform still needs the tier data to pick
  # a NAME to reference, size the root disk, and run the budget guard.
  #
  # Legacy tier names resolve through `aliases` (#239), so existing AAP surveys
  # and saved job launches keep working.
  tier_catalog   = yamldecode(file("${path.module}/tiers.yaml"))
  tier_defs      = local.tier_catalog.tiers
  canonical_tier = lookup(local.tier_catalog.aliases, var.vm_size_tier, var.vm_size_tier)
  tier           = local.tier_defs[local.canonical_tier]

  windows_min_disk_gb = local.tier_catalog.windows_min_disk_gb

  instancetype   = local.tier.instancetype
  linux_disk_gb  = local.tier.disk_gb
  windows_disk_g = max(local.tier.disk_gb, local.windows_min_disk_gb)

  # Budget check. THE COUNT IS NOW var.vm_count RATHER THAN A HARDCODED 1 (#389),
  # which is the whole reason a farm cannot quietly overcommit the node: this
  # multiplies the tier by however many VMs were asked for.
  #
  # THIS GUARD CAN ONLY SEE ITS OWN VMs, and that is the honest limit of putting
  # it here: the other OS lives in a different state file, so Terraform has no
  # way to know it exists. Since #389 the same is true of the other ROLE — state
  # is keyed <env>-<os>-<role>, so a `web` apply cannot see the `db` VMs either.
  # playbooks/provision_vm.yml therefore asks the CLUSTER what is already
  # requested before calling terraform, which is the only source that sees all
  # of them. Keep this one anyway — it catches "this tier at this count cannot
  # possibly fit" without a round trip, and it still runs when someone applies
  # by hand.
  requested_memory_gb = var.vm_count * (
    local.tier.memory_gb + (var.vm_memory_overhead_mb / 1024)
  )

  # Empty name_suffix gives deterministic names; see variables.tf for why this
  # is a variable rather than random_string.
  suffix = var.name_suffix != "" ? "-${var.name_suffix}" : ""

  # -------------------------------------------------------------------------
  # THE NAME FORMULA. EVERY OTHER NAME IN THIS MODULE DERIVES FROM IT (#389).
  #
  # `{role}-{os}-{index}` — `web-win-1`, `db-lnx-2`. Services, Routes, FQDNs,
  # URLs and the AAP host name are all built from `local.vm_names` below, so
  # this is the only place a naming decision is made. Changing it here changes
  # all of them together, which is exactly what the tier-based scheme could not
  # do: `windows_hostname` was a SEPARATE hand-maintained map, and it had to be,
  # because `sd-win-medium-1cpu-4gb` does not fit NetBIOS. That map is deleted —
  # the computed name fits by construction now.
  #
  # NO ENVIRONMENT IN THE NAME. The namespace (`sales-demos-sandbox`) already
  # carries it, and every character spent here comes out of the NetBIOS budget.
  #
  # NO TIER IN THE NAME. Sizing is not identity. It lives in the `vm_size_tier`
  # AAP host variable and the sd1.* instancetype the VM points at, both of which
  # can change on a converge without renaming — and renaming a KubeVirt VM
  # destroys and recreates it.
  #
  # PLAN-TIME KNOWN, which `kubernetes_manifest` requires: every input is a
  # variable or a loop index, never a resource attribute. This is the same
  # constraint that made name_suffix a variable instead of a random_string —
  # see variables.tf.
  # -------------------------------------------------------------------------
  os_prefix = var.os_type == "windows" ? "win" : "lnx"

  vm_names = [
    for i in range(var.vm_count) :
    "${var.vm_role}-${local.os_prefix}-${i + 1}${local.suffix}"
  ]

  # The last index has the most digits, so it is the longest name in the set.
  # Checked against the NetBIOS limit by the precondition at the foot of this
  # file — vm_role's own validation cannot see name_suffix, which spends from
  # the same 15 characters.
  longest_vm_name = element(local.vm_names, var.vm_count - 1)

  common_labels = {
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/part-of"    = "sales-demos"
    "sales-demos/tier"             = var.vm_size_tier
    "sales-demos/os-type"          = var.os_type
    # The role is a label as well as part of the name (#389), so a farm can be
    # selected without parsing names — `oc get vm -l sales-demos/role=web`.
    "sales-demos/role" = var.vm_role
  }

  # In-cluster DNS. Known at plan time, unlike a pod IP, which is why the
  # Service exists at all — see outputs.tf. One entry per VM, same order as
  # local.vm_names, so index i is the same machine everywhere in this file.
  vm_fqdns = [
    for n in local.vm_names : "${n}.${var.namespace}.svc.cluster.local"
  ]

  # Web service and Route — HTTP access for the demo web server.
  #
  # PER-OS SINCE #340, AND IT USED TO BE LINUX-ONLY. This was a single
  # `create_web_route = local.create_linux && ...`, so a Windows VM got no
  # Service, no Route and a null `web_url`: IIS could be installed and serve
  # nobody. The Linux demo's whole payoff is the Route turning 503 into a page,
  # and Windows had no counterpart to it.
  #
  # Two gates rather than one, because the OSes are not symmetric here: Cockpit
  # is a RHEL web console and stays behind the Linux gate below.
  create_linux_web_route   = local.create_linux && var.openshift_apps_domain != ""
  create_windows_web_route = local.create_windows && var.openshift_apps_domain != ""

  # ONE SET OF WEB LOCALS, NOT A LINUX PAIR AND A WINDOWS PAIR. The two were
  # byte-identical apart from which vm_name they read, and one state builds
  # exactly one OS since #301 — so `local.vm_names` already carries the OS and
  # the duplication bought nothing. #340 added the Windows half by copying the
  # Linux half; #389 merges them back now that the name is OS-agnostic.
  #
  # https, matching the Route edge termination added in #45. It was http://
  # while the Route had no TLS, which made every browser either warn about an
  # insecure page or fail outright on auto-upgrade.
  #
  # IIS serves the Default Web Site on :80 and httpd the same, so one port
  # covers both.
  web_svc_names   = [for n in local.vm_names : "${n}-web"]
  web_route_hosts = [for s in local.web_svc_names : "${s}-${var.namespace}.${var.openshift_apps_domain}"]
  web_urls        = [for h in local.web_route_hosts : "https://${h}"]

  # virtctl SSH commands, one per VM. Defined here rather than inline in
  # outputs.tf because BOTH the per-VM inventory entry and the top-level
  # ssh_commands output need them, and two copies of a command line is how they
  # drift apart.
  #
  # `vm/` is not decoration — virtctl takes a (VM|VMI) resource, and every
  # example in `virtctl ssh --help` carries the prefix. Without it the bare name
  # is ambiguous between a VM and a VMI.
  ssh_commands = [
    for n in local.vm_names :
    "virtctl ssh -o StrictHostKeyChecking=accept-new -n ${var.namespace} ${var.linux_admin_username}@vm/${n}"
  ]

  # Cockpit (RHEL web console) Service and Route — browser terminal (#63).
  # Linux only; there is no Windows counterpart, see outputs.tf.
  cockpit_svc_names   = [for n in local.vm_names : "${n}-cockpit"]
  cockpit_route_hosts = [for s in local.cockpit_svc_names : "${s}-${var.namespace}.${var.openshift_apps_domain}"]
  cockpit_urls        = [for h in local.cockpit_route_hosts : "https://${h}"]
}

# ---------------------------------------------------------------------------
# Budget guard. A resource with a precondition rather than a variable
# validation, because the check spans several variables and must run even when
# one of the VM resources has count = 0.
# ---------------------------------------------------------------------------
resource "terraform_data" "memory_budget" {
  input = local.requested_memory_gb

  lifecycle {
    precondition {
      condition = local.requested_memory_gb <= var.available_memory_gb
      error_message = format(
        "os_type=%s role=%s at tier %s needs ~%.1f GiB (%d VM x %d GiB guest + %d MiB overhead) but available_memory_gb is %d. This checks THIS OS AND ROLE only — state is per OS since #301 and per role since #389, so neither the other OS nor another role is visible here, and provision_vm.yml does the cluster-wide check. Lower vm_count, pick a smaller tier, or raise available_memory_gb if this cluster has more headroom.",
        var.os_type,
        var.vm_role,
        var.vm_size_tier,
        local.requested_memory_gb,
        var.vm_count,
        local.tier.memory_gb,
        var.vm_memory_overhead_mb,
        var.available_memory_gb,
      )
    }
  }
}

# ---------------------------------------------------------------------------
# NetBIOS budget guard (#389).
#
# WHY THIS IS NOT A VARIABLE VALIDATION. It spans three variables — vm_role,
# vm_count and name_suffix — and a Terraform variable validation can only see
# the one it is attached to. vm_role's own validation caps it at 8 characters,
# which makes the longest name this formula can build `{8}-win-{2 digits}` = 15
# exactly. A non-empty name_suffix spends from the same 15 and is invisible
# there, so it is checked here instead.
#
# WHY IT FAILS RATHER THAN TRUNCATES. Windows truncates a ComputerName longer
# than 15 characters silently, and the guest would then answer to a name the
# K8s object, the Service DNS record and the AAP host variable all disagree
# with. Failing at plan time costs a message; truncating costs an afternoon.
#
# Windows only. Linux hostnames have no such limit, and `lnx` is the same
# length as `win` so the Linux name is never the longer of the two anyway.
# ---------------------------------------------------------------------------
resource "terraform_data" "netbios_budget" {
  count = local.create_windows ? 1 : 0
  input = local.longest_vm_name

  lifecycle {
    precondition {
      condition = length(local.longest_vm_name) <= 15
      error_message = format(
        "The longest Windows VM name this run would build is '%s' (%d characters), over the 15-character NetBIOS limit. vm_role='%s' (%d), vm_count=%d, name_suffix='%s'. Shorten vm_role, or clear name_suffix — it is only needed when several people share one cluster, and it spends from the same 15 characters.",
        local.longest_vm_name,
        length(local.longest_vm_name),
        var.vm_role,
        length(var.vm_role),
        var.vm_count,
        var.name_suffix,
      )
    }
  }
}
