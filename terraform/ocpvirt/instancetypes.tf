# ---------------------------------------------------------------------------
# instancetypes.tf — the t-shirt sizing catalog, as code.
#
# Red Hat ships a u1.* series with CNV, but it has no 6 GiB size — it goes
# 2 / 4 / 8 / 16. At u1.large's 8 GiB, os_type=both needs ~16.6 GiB against the
# ~14.2 GiB free on this node and would never schedule. Defining our own types
# keeps every combination inside the budget while preserving the mechanism:
# sizing still comes from a cluster instance type, not a hand-rolled domain spec.
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
  for_each = local.tier_memory_gb

  manifest = {
    apiVersion = "instancetype.kubevirt.io/v1beta1"
    kind       = "VirtualMachineClusterInstancetype"
    metadata = {
      name   = local.instancetype_map[each.key]
      labels = local.common_labels
      annotations = {
        "sales-demos/tier"                     = each.key
        "instancetype.kubevirt.io/description" = "sales.demos ${each.key} - ${local.tier_cpu[each.key]} vCPU / ${each.value} GiB"
      }
    }
    spec = {
      cpu = {
        guest = local.tier_cpu[each.key]
      }
      memory = {
        guest = "${each.value}Gi"
      }
    }
  }
}
