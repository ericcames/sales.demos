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
# The u1.* types are left untouched.
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "instancetype" {
  for_each = local.canonical_tiers

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
