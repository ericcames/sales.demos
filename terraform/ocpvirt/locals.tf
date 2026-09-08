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
    local.tier.memory_gb + (var.vm_memory_overhead_mb / 1024)
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

  linux_web_svc_name   = "${local.linux_vm_name}-web"
  linux_web_route_host = "${local.linux_web_svc_name}-${var.namespace}.${var.openshift_apps_domain}"
  # https, matching the Route edge termination added in #45. It was http://
  # while the Route had no TLS, which made every browser either warn about an
  # insecure page or fail outright on auto-upgrade.
  linux_web_url = "https://${local.linux_web_route_host}"

  # Windows web Service and Route (#340). Same shape as the Linux pair above;
  # IIS serves the Default Web Site on :80, so the port matches.
  windows_web_svc_name   = "${local.windows_vm_name}-web"
  windows_web_route_host = "${local.windows_web_svc_name}-${var.namespace}.${var.openshift_apps_domain}"
  windows_web_url        = "https://${local.windows_web_route_host}"

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
        local.tier.memory_gb,
        var.vm_memory_overhead_mb,
        var.available_memory_gb,
      )
    }
  }
}
