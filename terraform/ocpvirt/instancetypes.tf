# ---------------------------------------------------------------------------
# instancetypes.tf — the t-shirt sizing catalog, as code.
#
# Repo-owned sd1.* instance types, sized for the doubled RHDP hardware (#239).
# The u1.* series shipped with CNV has the same 4/8/16 GiB sizes now, but
# keeping our own types lets the annotation and label stay consistent and avoids
# any dependency on the CNV version's catalog.
#
# CLUSTER-SCOPED, and deliberately NOT suffixed with name_suffix. Two people
# running this against the same cluster converge on identical definitions
# instead of littering it with near-duplicates. The trade-off is that
# `terraform destroy` removes them, so a concurrent run loses its sizing — fine
# for a sandbox, worth knowing before pointing this at a shared cluster.
#
# ONE STATE MANAGES THEM, AND SINCE #301 THAT HAS TO BE SAID OUT LOUD (#309).
# These are a shared CATALOG, not per-VM resources: one set of sd1.* types
# serves both guests. State is now keyed per OS, so if both states managed them
# the second apply would hit
#
#     Error: Cannot create resource that already exists
#     resource "/sd1.small" already exists
#
# which is exactly what a Windows provision did on a cluster the Linux state had
# already built. `kubernetes_manifest` cannot adopt an existing object, so the
# fix is ownership, not force: the Linux state owns the catalog and the Windows
# state references it by name.
#
# THE WART, NAMED SO IT IS NOT REDISCOVERED: an environment that has only ever
# provisioned Windows has no catalog. setup.yml and prepare_env.yml both build a
# Linux VM, so every environment this repo stands up has one — but the honest
# fix is to move the catalog to environment scope where it belongs, tracked in
# #309.
#
# The u1.* types are left untouched.
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "instancetype" {
  for_each = var.manage_instancetypes ? local.canonical_tiers : toset([])

  manifest = {
    apiVersion = "instancetype.kubevirt.io/v1beta1"
    kind       = "VirtualMachineClusterInstancetype"
    metadata = {
      name   = local.instancetype_map[each.key]
      labels = local.common_labels
      annotations = {
        "sales-demos/tier"                     = each.key
        "instancetype.kubevirt.io/description" = "sales.demos ${each.key} - ${local.tier_cpu[each.key]} vCPU / ${local.tier_memory_gb[each.key]} GiB"
      }
    }
    spec = {
      cpu = {
        guest = local.tier_cpu[each.key]
      }
      memory = {
        guest = "${local.tier_memory_gb[each.key]}Gi"
      }
    }
  }
}
