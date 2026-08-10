locals {
  # OS selection — drives count on per-VM resource blocks.
  create_windows = contains(["windows", "both"], var.os_type)
  create_linux   = contains(["linux", "both"], var.os_type)

  # T-shirt tier -> repo-owned cluster instance type. Keys match the AAP survey
  # choices exactly. Mapping to instance types rather than raw CPU/memory is
  # deliberate: it is native OpenShift Virt functionality and demos better than
  # hand-rolled domain specs.
  #
  # These are sd1.* (defined in instancetypes.tf), not Red Hat's shipped u1.*,
  # because large needs 6 GiB and the u1 series has no such size — it goes
  # 2 / 4 / 8 / 16. At u1.large's 8 GiB, os_type=both would need ~16.6 GiB
  # against ~14.2 GiB free on this node and would never schedule. Reverting a
  # tier to u1.* is a one-line change here.
  instancetype_map = {
    "small-1cpu-2gb"  = "sd1.small"
    "medium-1cpu-4gb" = "sd1.medium"
    "large-2cpu-6gb"  = "sd1.large"
  }

  # Guest memory per tier, in GiB. Single source of truth: instancetypes.tf
  # builds the objects from this, and the budget guard measures against it.
  tier_memory_gb = {
    "small-1cpu-2gb"  = 2
    "medium-1cpu-4gb" = 4
    "large-2cpu-6gb"  = 6
  }

  tier_cpu = {
    "small-1cpu-2gb"  = 1
    "medium-1cpu-4gb" = 1
    "large-2cpu-6gb"  = 2
  }

  # Root disk per tier. Windows needs more regardless of tier.
  tier_disk_gb = {
    "small-1cpu-2gb"  = 30
    "medium-1cpu-4gb" = 30
    "large-2cpu-6gb"  = 50
  }
  windows_min_disk_gb = 60

  instancetype   = local.instancetype_map[var.vm_size_tier]
  linux_disk_gb  = local.tier_disk_gb[var.vm_size_tier]
  windows_disk_g = max(local.tier_disk_gb[var.vm_size_tier], local.windows_min_disk_gb)

  # Budget check. Counts every VM this run would create, plus per-VM KubeVirt
  # overhead, against the cluster's headroom.
  vm_count = (local.create_windows ? 1 : 0) + (local.create_linux ? 1 : 0)
  requested_memory_gb = local.vm_count * (
    local.tier_memory_gb[var.vm_size_tier] + (var.vm_memory_overhead_mb / 1024)
  )

  # Empty name_suffix gives deterministic names; see variables.tf for why this
  # is a variable rather than random_string.
  suffix = var.name_suffix != "" ? "-${var.name_suffix}" : ""

  windows_vm_name = "sd-win-${var.vm_size_tier}${local.suffix}"
  linux_vm_name   = "sd-lnx-${var.vm_size_tier}${local.suffix}"

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
  create_web_route       = local.create_linux && var.openshift_apps_domain != ""
  linux_web_svc_name     = "${local.linux_vm_name}-web"
  linux_web_route_host   = "${local.linux_web_svc_name}-${var.namespace}.${var.openshift_apps_domain}"
  linux_web_url          = "http://${local.linux_web_route_host}"
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
        "os_type=%s at tier %s needs ~%.1f GiB (%d VM(s) x %d GiB guest + %d MiB overhead each) but available_memory_gb is %d. Pick a smaller tier, a single OS, or raise available_memory_gb if this cluster has more headroom.",
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
