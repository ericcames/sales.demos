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

  # OpenShift's SCC controller stamps every namespace with the UID/GID/MCS ranges
  # it allocated (openshift.io/sa.scc.*) plus the pod-security level it derived.
  # Terraform never sent those, so it plans to strip them on every run and the
  # controller immediately puts them back — a diff that can never converge, and
  # applying it would hand the guests a different UID range than the one their
  # pods were admitted under. They are the cluster's to own, so ignore them.
  lifecycle {
    ignore_changes = [metadata[0].annotations]
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
          # This subtree is x-kubernetes-preserve-unknown-fields, so the provider
          # has no schema for it and infers the type from the manifest written
          # here. That makes the KEY SET load-bearing: it must match what the
          # server returns exactly. KubeVirt's webhook stamps
          # kubevirt.io/pci-topology-version and a null creationTimestamp onto
          # every template, so both are declared below even though neither is
          # ours to set. Omit them and plan fails reading the refreshed object
          # back (`can't use tftypes.Object[...] as tftypes.Object[...]`); omit
          # them at apply and it is "Provider produced inconsistent result after
          # apply: incorrect object attributes".
          #
          # computed_fields (spec.template.metadata, above) covers the VALUES, so
          # the "v3" below is only a placeholder the server overwrites — a bump
          # to v4 costs nothing. A NEW annotation key would need adding here.
          creationTimestamp = null
          annotations = {
            "kubevirt.io/pci-topology-version" = "v3"
          }
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
                  ssh_pwauth: ${var.demo_ssh_public_key != "" ? "false" : "true"}
                  ${var.demo_ssh_public_key != "" ? "ssh_authorized_keys:\n  - ${var.demo_ssh_public_key}" : ""}
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
          # This subtree is x-kubernetes-preserve-unknown-fields, so the provider
          # has no schema for it and infers the type from the manifest written
          # here. That makes the KEY SET load-bearing: it must match what the
          # server returns exactly. KubeVirt's webhook stamps
          # kubevirt.io/pci-topology-version and a null creationTimestamp onto
          # every template, so both are declared below even though neither is
          # ours to set. Omit them and plan fails reading the refreshed object
          # back (`can't use tftypes.Object[...] as tftypes.Object[...]`); omit
          # them at apply and it is "Provider produced inconsistent result after
          # apply: incorrect object attributes".
          #
          # computed_fields (spec.template.metadata, above) covers the VALUES, so
          # the "v3" below is only a placeholder the server overwrites — a bump
          # to v4 costs nothing. A NEW annotation key would need adding here.
          creationTimestamp = null
          annotations = {
            "kubevirt.io/pci-topology-version" = "v3"
          }
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

# ---------------------------------------------------------------------------
# Web Service and Route — HTTP access to the Linux VM.
#
# The headless Service above cannot back a Route (no ClusterIP to proxy to).
# This adds a SEPARATE ClusterIP Service on port 80 as the Route target.
# Both Services coexist: the headless one stays for in-cluster DNS and AAP
# inventory, the web one exists only to give the Route something to target.
#
# The URL is live the moment apply finishes and returns 503 until httpd is
# installed by the AAP demo content (#5). That is expected, not a bug.
# ---------------------------------------------------------------------------

resource "kubernetes_service" "linux_web" {
  count = local.create_linux ? 1 : 0

  metadata {
    name      = local.linux_web_svc_name
    namespace = var.namespace
    labels    = local.common_labels
  }

  spec {
    selector = {
      "sales-demos/vm" = local.linux_vm_name
    }

    port {
      name        = "http"
      port        = 80
      target_port = 80
    }
  }

  depends_on = [kubernetes_namespace.demo]
}

resource "kubernetes_manifest" "linux_web_route" {
  count = local.create_web_route ? 1 : 0

  computed_fields = [
    "metadata.annotations",
    "metadata.labels",
  ]

  manifest = {
    apiVersion = "route.openshift.io/v1"
    kind       = "Route"
    metadata = {
      name      = local.linux_web_svc_name
      namespace = var.namespace
      labels    = local.common_labels
    }
    spec = {
      host = local.linux_web_route_host
      to = {
        kind   = "Service"
        name   = local.linux_web_svc_name
        weight = 100
      }
      port = {
        targetPort = "http"
      }
      # TLS AT THE EDGE, WHICH IS NOT OPTIONAL POLISH (#45). Without a tls
      # block the Route is HTTP-only, and every browser meets it badly:
      # Chrome auto-upgrades to HTTPS, finds no matching TLS route, and shows
      # "Application is not available" — the demo looks broken. Forcing http://
      # works but paints "Not secure" in the address bar for the whole demo.
      #
      # `edge` terminates at the router using the cluster's *.apps wildcard
      # certificate, which on RHDP is issued by Google Trust Services and
      # publicly trusted (confirmed in #35) — so this needs no certificate
      # management and produces a real padlock.
      #
      # `Redirect` keeps a bare http:// link working by sending it to https,
      # rather than serving content over plaintext.
      tls = {
        termination                   = "edge"
        insecureEdgeTerminationPolicy = "Redirect"
      }
      wildcardPolicy = "None"
    }
  }

  depends_on = [
    kubernetes_namespace.demo,
    kubernetes_service.linux_web,
  ]
}
