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

# MEASURED, NOT GUESSED (#118). 67 is what playbooks/probe_env.yml emitted
# against sandbox on 2026-09-03, cross-checked against the node's own
# accounting: 124.68 GiB allocatable, 49.05 GiB already requested, 75.63 GiB
# free, less an 8 GiB safety margin.
#
# The 14 it replaces was measured once on a smaller cluster and then outlived
# it by roughly 5x. Nothing reported the drift and nothing could have — the
# precondition in locals.tf fails CLOSED, so a stale figure does not error, it
# silently refuses tiers this cluster runs easily. The demo gets smaller and
# nobody learns why.
#
# THIS NUMBER IS ENVIRONMENT-SPECIFIC AND WILL GO STALE. Do not hand-adjust it;
# re-run the probe. `sales-demos-probe-env` is read-only and safe mid-demo, and
# it prints the recommendation beside whatever this default currently says.
# Re-run it after installing any platform add-on — the candidates in
# inventory/group_vars/aap/probe_workloads.yml come out of this budget.
#
# 67 -> 63 IS EXACTLY THAT HAPPENING (#141). Automation Orchestrator and its
# CloudNativePG database now install on every build, and they take 1.91 vCPU /
# 2.47 GiB of requests with them — measured by probe_env.yml either side of the
# install, 50.30 -> 52.77 GiB requested. Overstating this budget is the
# dangerous direction: the precondition in locals.tf fails CLOSED, so a figure
# that is too small merely refuses tiers the cluster could run, while one that
# is too large admits a plan that will not schedule.
variable "available_memory_gb" {
  description = "Guest memory budget in GiB for this cluster. Measured by playbooks/probe_env.yml on sandbox 2026-09-03 with Automation Orchestrator installed; re-run sales-demos-probe-env rather than hand-adjusting (#118, #141)."
  type        = number
  default     = 63
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
# plan-time known.
#
# LEAVE IT EMPTY unless you are sharing a cluster. This comment used to say
# "Phase 3 passes a unique value from AAP", which stopped being right when state
# moved to the kubernetes backend in #4: with persistent state, a suffix that
# changes per run makes every apply DESTROY and RE-CREATE the VMs instead of
# converging on them. Phase 3 therefore passes whatever the caller set and
# defaults to empty, i.e. deterministic names.
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

# ---------------------------------------------------------------------------
# SSH key injection.
#
# Injected via cloud-init ssh_authorized_keys at first boot. The
# accessCredentials + qemuGuestAgent mechanism was tried first (#29) but the
# RHEL 9 cloud image's guest agent fails with "failed to create directory
# '/home/<user>/.ssh': File exists" — a known QEMU guest agent bug where
# guest-ssh-add-authorized-keys uses mkdir instead of mkdir -p. The
# guest-exec fallback is also disabled by RHEL 9's security policy. Cloud-init
# works reliably; the trade-off is that key rotation requires a VM restart.
#
# A public key is not a credential. In the Ansible layer it lives in each
# environment's connection.yml beside linux_admin_username, not in the vault.
# ---------------------------------------------------------------------------

variable "demo_ssh_public_key" {
  description = "SSH public key added to the Linux VM via cloud-init. When set, password-based SSH is disabled."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# OpenShift ingress domain — used to construct Route hostnames at plan time.
#
# NodePort was spiked on RHDP and is FILTERED (high ports are blocked by the
# RHDP firewall), so SSH access uses `virtctl ssh` (rides port 6443, confirmed
# open; the `--local-ssh` flag it once took was removed in virtctl v1.x — see
# outputs.tf). HTTP access uses a Route, which needs the *.apps ingress domain
# to construct a plan-time-known hostname.
#
# Find it with:
#   oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}'
# ---------------------------------------------------------------------------

variable "openshift_apps_domain" {
  description = "The *.apps ingress domain for this cluster, e.g. apps.cluster-<id>.dyn.redhatworkshops.io. Required for Route-based HTTP access."
  type        = string
  default     = ""
}
