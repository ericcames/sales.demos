# ---------------------------------------------------------------------------
# outputs.tf — the inventory contract.
#
# The field names and null-when-absent behavior are ported UNCHANGED from
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
    aap_host_name  = "${random_id.windows_instance[0].hex}-${var.namespace}.${var.openshift_apps_domain}"
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
    aap_host_name  = "${random_id.linux_instance[0].hex}-${var.namespace}.${var.openshift_apps_domain}"
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

# ---------------------------------------------------------------------------
# Public access — SSH and HTTP endpoints added in #29.
#
# NodePort was spiked on RHDP and is FILTERED (high ports blocked by the RHDP
# firewall). SSH uses `virtctl ssh`, which rides port 6443 (confirmed open).
# HTTP uses a Route.
#
# NO `--local-ssh` FLAG. It existed while virtctl shipped its own SSH client and
# the flag chose the system `ssh` binary instead. v1.x removed that client, so
# local ssh is the only mode and the flag was DELETED rather than defaulted —
# passing it now fails with `unknown flag: --local-ssh` before anything
# connects. `-t/--local-ssh-opts` is the surviving way to pass ssh options.
# ---------------------------------------------------------------------------

# WEB_URL RESOLVES PER-OS, AND THAT KEEPS THE CONTRACT SINGLE (#340). One state
# builds exactly one OS since #301, so this is never ambiguous. Returning the
# right URL from the same output name means every downstream consumer is
# unchanged: the host var in register_hosts.yml, the set_stats in
# provision_artifacts.yml, the demo page, the compliance report link, and the
# check playbook all keep reading `web_url`. A second `windows_web_url` output
# would have forced every one of them to learn which OS it was looking at.
output "web_url" {
  description = "Public HTTPS URL for the demo VM's web server — the Linux VM under os_type=linux, the Windows VM under os_type=windows. Returns 503 until the web server is installed by AAP demo content. Null when openshift_apps_domain is not set."
  value = (
    local.create_windows_web_route ? local.windows_web_url :
    local.create_linux_web_route ? local.linux_web_url :
    null
  )
}

# NO WINDOWS COUNTERPART, DELIBERATELY. Cockpit is the RHEL web console; there
# is no equivalent to expose on Windows, and RDP is already published on the
# headless Service rather than through a Route (it is not HTTP).
output "cockpit_url" {
  description = "Cockpit (RHEL web console) URL for the Linux VM. Provides a browser-based terminal. Null when os_type excludes linux or openshift_apps_domain is not set."
  value       = local.create_linux_web_route ? local.linux_cockpit_url : null
}

output "ssh_command" {
  description = "SSH command for the Linux VM using virtctl (rides port 6443, no NodePort needed). Null when os_type excludes linux."
  # `vm/` is not decoration — virtctl takes a (VM|VMI) resource, and every
  # example in `virtctl ssh --help` carries the prefix. Without it the bare name
  # is ambiguous between a VM and a VMI.
  value = local.create_linux ? "virtctl ssh -o StrictHostKeyChecking=accept-new -n ${var.namespace} ${var.linux_admin_username}@vm/${local.linux_vm_name}" : null
}
