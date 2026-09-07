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
  # Updated for doubled RHDP hardware (#239). Old names are legacy aliases that
  # resolve to the new specs — backward compatible with existing AAP surveys and
  # saved job launches.
  instancetype_map = {
    "small"           = "sd1.small"
    "medium"          = "sd1.medium"
    "large"           = "sd1.large"
    "small-1cpu-2gb"  = "sd1.small"
    "medium-1cpu-4gb" = "sd1.medium"
    "large-2cpu-6gb"  = "sd1.large"
  }

  # Guest memory per tier, in GiB. Single source of truth: instancetypes.tf
  # builds the objects from this, and the budget guard measures against it.
  tier_memory_gb = {
    "small"           = 4
    "medium"          = 8
    "large"           = 16
    "small-1cpu-2gb"  = 4
    "medium-1cpu-4gb" = 8
    "large-2cpu-6gb"  = 16
  }

  tier_cpu = {
    "small"           = 2
    "medium"          = 2
    "large"           = 4
    "small-1cpu-2gb"  = 2
    "medium-1cpu-4gb" = 2
    "large-2cpu-6gb"  = 4
  }

  # Root disk per tier. Windows needs more regardless of tier.
  tier_disk_gb = {
    "small"           = 30
    "medium"          = 30
    "large"           = 50
    "small-1cpu-2gb"  = 30
    "medium-1cpu-4gb" = 30
    "large-2cpu-6gb"  = 50
  }
  windows_min_disk_gb = 60

  instancetype   = local.instancetype_map[var.vm_size_tier]
  linux_disk_gb  = local.tier_disk_gb[var.vm_size_tier]
  windows_disk_g = max(local.tier_disk_gb[var.vm_size_tier], local.windows_min_disk_gb)

  # Budget check. ALWAYS ONE VM NOW, because state is per OS (#301).
  #
  # THIS GUARD CAN ONLY SEE ITS OWN VM, and that is the honest limit of putting
  # it here: the other OS lives in a different state file, so Terraform has no
  # way to know it exists. playbooks/provision_vm.yml therefore asks the CLUSTER
  # what is already requested before calling terraform, which is the only source
  # that sees both. Keep this one anyway — it catches "this tier cannot possibly
  # fit" without a round trip, and it still runs when someone applies by hand.
  vm_count = 1
  requested_memory_gb = local.vm_count * (
    local.tier_memory_gb[var.vm_size_tier] + (var.vm_memory_overhead_mb / 1024)
  )

  # Empty name_suffix gives deterministic names; see variables.tf for why this
  # is a variable rather than random_string.
  suffix = var.name_suffix != "" ? "-${var.name_suffix}" : ""

  windows_vm_name = "sd-win-${var.vm_size_tier}${local.suffix}"
  linux_vm_name   = "sd-lnx-${var.vm_size_tier}${local.suffix}"

  # Windows NetBIOS hostname: max 15 characters.
  tier_windows_hostname = {
    "small"           = "sd-win-small"
    "medium"          = "sd-win-medium"
    "large"           = "sd-win-large"
    "small-1cpu-2gb"  = "sd-win-sm-1c-2g"
    "medium-1cpu-4gb" = "sd-win-md-1c-4g"
    "large-2cpu-6gb"  = "sd-win-lg-2c-6g"
  }
  windows_hostname = local.tier_windows_hostname[var.vm_size_tier]

  # Canonical tier names — used by instancetypes.tf for_each to avoid creating
  # duplicate cluster objects from the legacy aliases.
  canonical_tiers = toset(["small", "medium", "large"])

  common_labels = {
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/part-of"    = "sales-demos"
    "sales-demos/tier"             = var.vm_size_tier
    "sales-demos/os-type"          = var.os_type
  }

  # In-cluster DNS. Known at plan time, unlike a pod IP, which is why the
  # Service exists at all — see outputs.tf.
  windows_fqdn = "${local.windows_vm_name}.${var.namespace}.svc.cluster.local"
  linux_fqdn   = "${local.linux_vm_name}.${var.namespace}.svc.cluster.local"

  # Web service and Route — HTTP access for the demo web server.
  create_web_route     = local.create_linux && var.openshift_apps_domain != ""
  linux_web_svc_name   = "${local.linux_vm_name}-web"
  linux_web_route_host = "${local.linux_web_svc_name}-${var.namespace}.${var.openshift_apps_domain}"
  # https, matching the Route edge termination added in #45. It was http://
  # while the Route had no TLS, which made every browser either warn about an
  # insecure page or fail outright on auto-upgrade.
  linux_web_url = "https://${local.linux_web_route_host}"

  # Cockpit (RHEL web console) Service and Route — browser terminal (#63).
  linux_cockpit_svc_name   = "${local.linux_vm_name}-cockpit"
  linux_cockpit_route_host = "${local.linux_cockpit_svc_name}-${var.namespace}.${var.openshift_apps_domain}"
  linux_cockpit_url        = "https://${local.linux_cockpit_route_host}"
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
        "os_type=%s at tier %s needs ~%.1f GiB (%d VM x %d GiB guest + %d MiB overhead) but available_memory_gb is %d. This checks THIS OS only — state is per OS since #301, so the other OS is invisible here and provision_vm.yml does the cluster-wide check. Pick a smaller tier, or raise available_memory_gb if this cluster has more headroom.",
        var.os_type,
        var.vm_size_tier,
        local.requested_memory_gb,
        local.vm_count,
        local.tier_memory_gb[var.vm_size_tier],
        var.vm_memory_overhead_mb,
        var.available_memory_gb,
      )
    }
  }
}
