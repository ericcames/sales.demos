# ---------------------------------------------------------------------------
# outputs.tf — the inventory contract.
#
# The field names and null-when-absent behaviour are ported UNCHANGED from
# dc1.azure/terraform/outputs.tf. Phases 3 and 4 consume this shape to register
# hosts in AAP; renaming a field here breaks them.
#
# What differs is only what `host` and `ansible_host` contain. Azure had a public
# IP and a DNS label; here both are the VM's headless Service DNS name, which is
# stable, known at plan time, and resolves to the VM's current pod IP from
# anywhere in the cluster — including AAP, which runs on the same cluster.
# ---------------------------------------------------------------------------

output "os_type" {
  description = "OS type requested for this run."
  value       = var.os_type
}

output "namespace" {
  description = "Namespace the VMs were created in."
  value       = var.namespace
}

# ---------------------------------------------------------------------------
# Windows outputs — null when os_type excludes windows.
# ---------------------------------------------------------------------------

output "windows_inventory" {
  description = "Windows VM inventory data for AAP host registration. Null when os_type excludes windows."
  value = local.create_windows ? {
    host           = local.windows_fqdn
    ansible_host   = local.windows_fqdn
    ansible_user   = var.windows_admin_username
    vm_name        = local.windows_vm_name
    vm_size_tier   = var.vm_size_tier
    vm_size_chosen = local.instancetype
  } : null
}

# ---------------------------------------------------------------------------
# Linux outputs — null when os_type excludes linux.
# ---------------------------------------------------------------------------

output "linux_inventory" {
  description = "Linux VM inventory data for AAP host registration. Null when os_type excludes linux."
  value = local.create_linux ? {
    host           = local.linux_fqdn
    ansible_host   = local.linux_fqdn
    ansible_user   = var.linux_admin_username
    vm_name        = local.linux_vm_name
    vm_size_tier   = var.vm_size_tier
    vm_size_chosen = local.instancetype
  } : null
}

# ---------------------------------------------------------------------------
# Sizing, surfaced so a run can be checked against the cluster's headroom
# without reading the code.
# ---------------------------------------------------------------------------

output "memory_budget" {
  description = "Guest memory this run requests versus the configured budget, both in GiB."
  value = {
    requested_gb = local.requested_memory_gb
    available_gb = var.available_memory_gb
    vm_count     = local.vm_count
    instancetype = local.instancetype
  }
}
