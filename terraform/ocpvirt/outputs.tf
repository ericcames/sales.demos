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

# A LIST SINCE #389, AND EMPTY RATHER THAN NULL WHEN THIS OS IS NOT BUILT.
#
# It was a single dict, because one state held one VM. `vm_count` makes that
# false, and a list of one is the same thing a farm of three is — so the
# consumers loop once instead of branching on shape. Empty beats null for the
# same reason: `loop: []` is a no-op, while `loop: null` is an error, so the
# "this OS was not requested" case needs no `when:` of its own.
#
# THE FIELD NAMES INSIDE EACH ENTRY ARE UNCHANGED. register_hosts.yml,
# provision_artifacts.yml and teardown_ocpvirt.yml read them by name; the shape
# around them moved, the contract inside them did not.
#
# web_url IS PER-VM AND LIVES IN HERE NOW. It used to be a single top-level
# output because there was a single VM to point at. With a farm there is one
# Route each, and the host variable has to carry its own — see register_hosts.yml.
output "windows_inventory" {
  description = "Windows VM inventory data for AAP host registration, one entry per VM. Empty when os_type excludes windows."
  value = [
    for i in range(local.create_windows ? var.vm_count : 0) : {
      host           = local.vm_fqdns[i]
      ansible_host   = local.vm_fqdns[i]
      ansible_user   = var.windows_admin_username
      vm_name        = local.vm_names[i]
      vm_role        = var.vm_role
      vm_index       = i + 1
      vm_size_tier   = var.vm_size_tier
      vm_size_chosen = local.instancetype
      aap_host_name  = "${local.vm_names[i]}-${random_id.windows_instance[i].hex}-${var.namespace}.${var.openshift_apps_domain}"
      web_url        = local.create_windows_web_route ? local.web_urls[i] : null
      cockpit_url    = null
      ssh_command    = null
    }
  ]
}

# ---------------------------------------------------------------------------
# Linux outputs — null when os_type excludes linux.
# ---------------------------------------------------------------------------

output "linux_inventory" {
  description = "Linux VM inventory data for AAP host registration, one entry per VM. Empty when os_type excludes linux."
  value = [
    for i in range(local.create_linux ? var.vm_count : 0) : {
      host           = local.vm_fqdns[i]
      ansible_host   = local.vm_fqdns[i]
      ansible_user   = var.linux_admin_username
      vm_name        = local.vm_names[i]
      vm_role        = var.vm_role
      vm_index       = i + 1
      vm_size_tier   = var.vm_size_tier
      vm_size_chosen = local.instancetype
      aap_host_name  = "${local.vm_names[i]}-${random_id.linux_instance[i].hex}-${var.namespace}.${var.openshift_apps_domain}"
      web_url        = local.create_linux_web_route ? local.web_urls[i] : null
      cockpit_url    = local.create_linux_web_route ? local.cockpit_urls[i] : null
      ssh_command    = local.ssh_commands[i]
    }
  ]
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
    vm_count     = var.vm_count
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
# unchanged.
#
# A LIST SINCE #389, ONE ENTRY PER VM, in the same order as the inventory
# outputs. The per-VM copy inside each inventory entry is what register_hosts.yml
# puts on the host; this stays because the workflow artifacts and the summary
# want the whole set, and because a caller running terraform by hand should be
# able to see every URL without parsing the inventory.
output "web_urls" {
  description = "Public HTTPS URLs for the demo VMs' web servers, one per VM, in vm_names order. Each returns 503 until the web server is installed by AAP demo content. Empty when openshift_apps_domain is not set."
  value = (
    local.create_windows_web_route || local.create_linux_web_route
    ? local.web_urls
    : []
  )
}

# NO WINDOWS COUNTERPART, DELIBERATELY. Cockpit is the RHEL web console; there
# is no equivalent to expose on Windows, and RDP is already published on the
# headless Service rather than through a Route (it is not HTTP).
output "cockpit_urls" {
  description = "Cockpit (RHEL web console) URLs for the Linux VMs, one per VM. Empty when os_type excludes linux or openshift_apps_domain is not set."
  value       = local.create_linux_web_route ? local.cockpit_urls : []
}

# NO `--local-ssh` FLAG. It existed while virtctl shipped its own SSH client and
# the flag chose the system `ssh` binary instead. v1.x removed that client, so
# local ssh is the only mode and the flag was DELETED rather than defaulted —
# passing it now fails with `unknown flag: --local-ssh` before anything
# connects. `-t/--local-ssh-opts` is the surviving way to pass ssh options.
output "ssh_commands" {
  description = "SSH commands for the Linux VMs using virtctl (rides port 6443, no NodePort needed), one per VM. Empty when os_type excludes linux."
  value       = local.create_linux ? local.ssh_commands : []
}
