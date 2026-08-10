# ---------------------------------------------------------------------------
# main.tf — the namespace, the VMs, and a Service per VM.
#
# Each VM clones a boot-source DataSource into its own DataVolume and takes its
# sizing from an sd1.* cluster instance type plus an OS preference.
#
# WHY A SERVICE. Azure gave each VM a public IP and FQDN. OpenShift Virt gives
# neither: a VM gets a pod-network address that is unknown until it boots and
# changes on restart, so it cannot appear in a plan-time output. A ClusterIP
# Service gives a stable in-cluster DNS name, known before anything is created,
# which is what the inventory outputs publish. AAP runs on this same cluster, so
# it can reach the VMs there.
#
# APPLY DOES NOT MEAN RUNNING. The default StorageClass is WaitForFirstConsumer,
# so the PVC binds and the disk clones only once the VM first schedules.
# terraform apply returns well before the guest is up.
# ---------------------------------------------------------------------------

resource "kubernetes_namespace" "demo" {
  metadata {
    name   = var.namespace
    labels = local.common_labels
  }
}

# ---------------------------------------------------------------------------
# Linux — RHEL 9 from the CNV-shipped boot source. Works today.
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "linux_vm" {
  count = local.create_linux ? 1 : 0

  # KubeVirt's mutating webhook fills in defaults the manifest never sent —
  # domain.machine, domain.firmware, domain.resources, template metadata, and
  # DataVolume template defaults. Without declaring those subtrees server-managed,
  # the provider compares what it sent against what came back and fails with
  # "Provider produced inconsistent result after apply", even though the object
  # was created correctly. Note this list REPLACES the default
  # ["metadata.annotations", "metadata.labels"], so both are repeated here.
  computed_fields = [
    "metadata.annotations",
    "metadata.labels",
    "spec.template.spec.domain",
    "spec.template.metadata",
    "spec.dataVolumeTemplates",
    "spec.runStrategy",
  ]

  manifest = {
    apiVersion = "kubevirt.io/v1"
    kind       = "VirtualMachine"
    metadata = {
      name      = local.linux_vm_name
      namespace = var.namespace
      labels    = merge(local.common_labels, { "sales-demos/os" = "linux" })
    }
    spec = {
      running = true

      instancetype = {
        kind = "VirtualMachineClusterInstancetype"
        name = local.instancetype
      }
      preference = {
        kind = "VirtualMachineClusterPreference"
        name = "rhel.9"
      }

      dataVolumeTemplates = [{
        metadata = {
          name = "${local.linux_vm_name}-root"
        }
        spec = {
          sourceRef = {
            kind      = "DataSource"
            name      = var.linux_datasource_name
            namespace = var.datasource_namespace
          }
          storage = {
            resources = {
              requests = {
                storage = "${local.linux_disk_gb}Gi"
              }
            }
          }
        }
      }]

      template = {
        metadata = {
          labels = merge(local.common_labels, {
            "sales-demos/vm" = local.linux_vm_name
            "sales-demos/os" = "linux"
          })
        }
        spec = {
          # Required by the VirtualMachine CRD even though the instance type
          # supplies CPU and memory. It must stay EMPTY: setting cpu or memory
          # here conflicts with the instancetype and the webhook rejects it.
          domain = {
            devices = {}
          }
          volumes = [
            {
              name = "rootdisk"
              dataVolume = {
                name = "${local.linux_vm_name}-root"
              }
            },
            {
              name = "cloudinitdisk"
              cloudInitNoCloud = {
                userData = <<-EOT
                  #cloud-config
                  user: ${var.linux_admin_username}
                  ${var.linux_admin_password != "" ? "password: ${var.linux_admin_password}\nchpasswd: { expire: False }" : ""}
                  ssh_pwauth: true
                EOT
              }
            },
          ]
        }
      }
    }
  }

  depends_on = [
    kubernetes_namespace.demo,
    kubernetes_manifest.instancetype,
    terraform_data.memory_budget,
  ]
}

# ---------------------------------------------------------------------------
# Windows — wired up, but CANNOT BOOT until Phase 2 (#3).
#
# CNV ships win2k22 as an empty DataSource placeholder: it exists and is listed,
# but reports Ready=False with no populated PVC, because Red Hat cannot
# redistribute Windows media. Phase 2 builds and publishes the golden image that
# fills it. Until then os_type=windows or both will create the VM and it will
# wait forever on a DataVolume that never imports.
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "windows_vm" {
  count = local.create_windows ? 1 : 0

  # KubeVirt's mutating webhook fills in defaults the manifest never sent —
  # domain.machine, domain.firmware, domain.resources, template metadata, and
  # DataVolume template defaults. Without declaring those subtrees server-managed,
  # the provider compares what it sent against what came back and fails with
  # "Provider produced inconsistent result after apply", even though the object
  # was created correctly. Note this list REPLACES the default
  # ["metadata.annotations", "metadata.labels"], so both are repeated here.
  computed_fields = [
    "metadata.annotations",
    "metadata.labels",
    "spec.template.spec.domain",
    "spec.template.metadata",
    "spec.dataVolumeTemplates",
    "spec.runStrategy",
  ]

  manifest = {
    apiVersion = "kubevirt.io/v1"
    kind       = "VirtualMachine"
    metadata = {
      name      = local.windows_vm_name
      namespace = var.namespace
      labels    = merge(local.common_labels, { "sales-demos/os" = "windows" })
    }
    spec = {
      running = true

      instancetype = {
        kind = "VirtualMachineClusterInstancetype"
        name = local.instancetype
      }
      preference = {
        kind = "VirtualMachineClusterPreference"
        name = "windows.2k22"
      }

      dataVolumeTemplates = [{
        metadata = {
          name = "${local.windows_vm_name}-root"
        }
        spec = {
          sourceRef = {
            kind      = "DataSource"
            name      = var.windows_datasource_name
            namespace = var.datasource_namespace
          }
          storage = {
            resources = {
              requests = {
                storage = "${local.windows_disk_g}Gi"
              }
            }
          }
        }
      }]

      template = {
        metadata = {
          labels = merge(local.common_labels, {
            "sales-demos/vm" = local.windows_vm_name
            "sales-demos/os" = "windows"
          })
        }
        spec = {
          # Required by the VirtualMachine CRD even though the instance type
          # supplies CPU and memory. It must stay EMPTY: setting cpu or memory
          # here conflicts with the instancetype and the webhook rejects it.
          domain = {
            devices = {}
          }
          volumes = [{
            name = "rootdisk"
            dataVolume = {
              name = "${local.windows_vm_name}-root"
            }
          }]
        }
      }
    }
  }

  depends_on = [
    kubernetes_namespace.demo,
    kubernetes_manifest.instancetype,
    terraform_data.memory_budget,
  ]
}

# ---------------------------------------------------------------------------
# Services — the stable address the inventory outputs publish.
#
# Selector matches the VMI pod labels stamped onto spec.template.metadata above.
# Typed resources rather than kubernetes_manifest: no CRD involved, and it keeps
# the plan readable.
# ---------------------------------------------------------------------------

resource "kubernetes_service" "linux" {
  count = local.create_linux ? 1 : 0

  metadata {
    name      = local.linux_vm_name
    namespace = var.namespace
    labels    = local.common_labels
  }

  spec {
    selector = {
      "sales-demos/vm" = local.linux_vm_name
    }
    cluster_ip = "None" # Headless: DNS resolves straight to the VM's pod IP.

    port {
      name        = "ssh"
      port        = 22
      target_port = 22
    }
  }

  depends_on = [kubernetes_namespace.demo]
}

resource "kubernetes_service" "windows" {
  count = local.create_windows ? 1 : 0

  metadata {
    name      = local.windows_vm_name
    namespace = var.namespace
    labels    = local.common_labels
  }

  spec {
    selector = {
      "sales-demos/vm" = local.windows_vm_name
    }
    cluster_ip = "None"

    port {
      name        = "rdp"
      port        = 3389
      target_port = 3389
    }
    port {
      name        = "winrm"
      port        = 5985
      target_port = 5985
    }
  }

  depends_on = [kubernetes_namespace.demo]
}
