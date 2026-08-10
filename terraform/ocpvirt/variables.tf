# ---------------------------------------------------------------------------
# Cluster connection — real values go in terraform.tfvars (gitignored) or come
# from AAP as -var arguments in Phase 3. See terraform.tfvars.example.
# ---------------------------------------------------------------------------

variable "kubeconfig_path" {
  description = "Path to a kubeconfig. Leave empty to authenticate with openshift_api_url + openshift_api_token instead."
  type        = string
  default     = ""
}

variable "openshift_api_url" {
  description = "OpenShift API endpoint, e.g. https://api.cluster-<id>.dyn.redhatworkshops.io:6443. Ignored when kubeconfig_path is set."
  type        = string
  default     = ""
}

variable "openshift_api_token" {
  description = "OpenShift bearer token. Ignored when kubeconfig_path is set. Never commit this — it belongs in the vault or in gitignored tfvars."
  type        = string
  default     = ""
  sensitive   = true
}

variable "openshift_insecure" {
  description = "Skip TLS verification. True for RHDP, which uses self-signed certificates."
  type        = bool
  default     = true
}

variable "namespace" {
  description = "Namespace the demo VMs are created in. Matches ocpvirt_namespace in the environment's connection.yml."
  type        = string
  default     = "sales-demos-sandbox"
}

# ---------------------------------------------------------------------------
# VM sizing — survey-driven t-shirt tier, mapped to a cluster instance type in
# locals.tf. The tier strings are the CONTRACT shared with the AAP survey and
# the skill; changing one means changing all three.
# ---------------------------------------------------------------------------

variable "vm_size_tier" {
  description = "T-shirt size selected by the user in the AAP JT survey. Mapped to an sd1.* cluster instance type in locals.tf."
  type        = string
  default     = "small-1cpu-2gb"

  validation {
    condition     = contains(["small-1cpu-2gb", "medium-1cpu-4gb", "large-2cpu-6gb"], var.vm_size_tier)
    error_message = "vm_size_tier must be one of: small-1cpu-2gb, medium-1cpu-4gb, large-2cpu-6gb."
  }
}

# ---------------------------------------------------------------------------
# OS selection — drives count-based conditionals on the Windows and Linux
# resource blocks.
# ---------------------------------------------------------------------------

variable "os_type" {
  description = "Which OS to provision: windows only, linux (RHEL 9) only, or both. Windows requires the golden image from Phase 2 (#3)."
  type        = string
  default     = "linux"

  validation {
    condition     = contains(["windows", "linux", "both"], var.os_type)
    error_message = "os_type must be one of: windows, linux, both."
  }
}

# ---------------------------------------------------------------------------
# Memory budget guard.
#
# This node is shared with AAP and CNV, so the free figure is well below the
# node total and moves as pods come and go. Without this, an over-budget request
# schedules and then sits Pending with an Insufficient memory event while
# Terraform reports success. Failing in `plan` is cheaper to diagnose.
#
# No shipped tier/OS combination trips this at the default — it is a safety net
# for a smaller or busier cluster.
# ---------------------------------------------------------------------------

variable "available_memory_gb" {
  description = "Guest memory budget in GiB for this cluster. Raise it if the node has more headroom than the sandbox's ~14 GiB."
  type        = number
  default     = 14
}

variable "vm_memory_overhead_mb" {
  description = "Per-VM KubeVirt overhead in MiB, on top of guest memory — virtio, video, page tables. Roughly 250-350 in practice."
  type        = number
  default     = 350
}

# ---------------------------------------------------------------------------
# Naming.
#
# NOT random_string, unlike dc1.azure/terraform/locals.tf. `kubernetes_manifest`
# requires every value in the manifest to be KNOWN AT PLAN TIME, and a
# random_string result is unknown until apply, which makes `terraform plan` fail
# outright. A caller-supplied suffix keeps names unique across repeated
# apply/destroy cycles and across people sharing one RHDP cluster, while staying
# plan-time known. Phase 3 passes a unique value from AAP.
# ---------------------------------------------------------------------------

variable "name_suffix" {
  description = "Short suffix appended to VM names for uniqueness. Leave empty for deterministic names when you are the only one on the cluster."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[a-z0-9]*$", var.name_suffix))
    error_message = "name_suffix must be lowercase alphanumeric only — it becomes part of a Kubernetes object name."
  }
}

# ---------------------------------------------------------------------------
# Guest credentials and images.
# ---------------------------------------------------------------------------

variable "linux_admin_username" {
  description = "Login user created on the RHEL guest by cloud-init."
  type        = string
  default     = "cloud-user"
}

variable "linux_admin_password" {
  description = "Password for the Linux guest user. Demo convenience only; the AAP layer normally connects with a key."
  type        = string
  default     = ""
  sensitive   = true
}

variable "windows_admin_username" {
  description = "Local Windows administrator username on the new VM."
  type        = string
  default     = "demoadmin"

  validation {
    condition     = !contains(["administrator", "admin", "user", "root", "guest"], lower(var.windows_admin_username))
    error_message = "windows_admin_username cannot be one of the reserved Windows names (administrator, admin, user, root, guest)."
  }
}

variable "linux_datasource_name" {
  description = "DataSource cloned for the Linux VM. rhel9 ships with CNV and is Ready on a fresh install."
  type        = string
  default     = "rhel9"
}

variable "windows_datasource_name" {
  description = "DataSource cloned for the Windows VM. CNV ships win2k22 as an EMPTY placeholder (Ready=False) — Phase 2 (#3) populates it. Windows cannot boot until then."
  type        = string
  default     = "win2k22"
}

variable "datasource_namespace" {
  description = "Namespace holding the boot-source DataSources."
  type        = string
  default     = "openshift-virtualization-os-images"
}
