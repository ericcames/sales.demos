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
  default     = "small"

  # THIS LIST REPEATS tiers.yaml, AND THAT IS TOLERATED RATHER THAN OVERLOOKED
  # (#348). Terraform does not allow a variable validation to reference a local,
  # so it cannot read the catalog the rest of the module now reads.
  #
  # It is safe because it CANNOT DRIFT SILENTLY, which is the property the
  # duplications behind #334 and #342 lacked. Add a tier to tiers.yaml and not
  # here, and this validation rejects it by name. Remove one from tiers.yaml and
  # not here, and `local.tier_defs[local.canonical_tier]` fails on a missing key.
  # Both directions fail loudly, at plan time, before anything is built.
  validation {
    condition     = contains(["small", "medium", "large", "small-1cpu-2gb", "medium-1cpu-4gb", "large-2cpu-6gb"], var.vm_size_tier)
    error_message = "vm_size_tier must be one of: small, medium, large (or legacy: small-1cpu-2gb, medium-1cpu-4gb, large-2cpu-6gb)."
  }
}

# ---------------------------------------------------------------------------
# Workload role and farm size (#389).
#
# ROLE REPLACED THE TIER IN THE NAME, and that is the point rather than a side
# effect. Names were `sd-win-large` — infrastructure sizing, which tells you
# nothing about what the machine is for and collides the moment you want two of
# them. `web-win-1` tells you the workload, the OS, and which member of the farm
# it is. The tier did not disappear; it moved to the `vm_size_tier` AAP host
# variable and the sd1.* instancetype label, where sizing belongs.
#
# ROLE IS FIRST because it is what you scan a list for. `web` before `win`
# before `1`.
#
# THE 8-CHARACTER LIMIT IS THE NetBIOS BUDGET, NOT A STYLE RULE. A Windows
# computer name is capped at 15 characters, and the name is used verbatim as the
# NetBIOS hostname in the sysprep unattend. The longest name this formula can
# build is `{8}-win-{2 digits}` = 15 exactly, so 8 is the largest value that
# cannot overflow. locals.tf holds a precondition for the case this validation
# cannot see — a non-empty name_suffix, which adds to the same budget.
# ---------------------------------------------------------------------------

variable "vm_role" {
  description = "Workload role — becomes part of the K8s object name, the NetBIOS hostname, and the AAP host name. Max 8 characters, for the NetBIOS budget."
  type        = string
  default     = "web"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{0,7}$", var.vm_role))
    error_message = "vm_role must be 1-8 characters, lowercase alphanumeric, starting with a letter. The 8-character cap is the Windows NetBIOS budget: the longest name this builds is {role}-win-{2 digits} = 15, which is the maximum."
  }
}

# THE CAP OF 2 IS A GUARD RAIL, NOT A CAPACITY FIGURE. Capacity is enforced
# twice and neither check lives here: the precondition in locals.tf multiplies
# the tier by this count against available_memory_gb, and provision_vm.yml asks
# the CLUSTER what is already requested before calling terraform, which is the
# only source that sees the other OS's state (#301).
#
# IT WAS 10, AND 10 WAS THE WRONG PLACE TO PUT A GUARD RAIL (#397). The stated
# reason was that "a typo in a survey box cannot ask for 100 VMs and spend a
# minute being refused" -- correct in kind, wrong in degree. A large guest is
# 16 GiB against an available_memory_gb of 63, so THREE already exceed the
# budget. Eight of the ten values the survey offered had no outcome but the
# refusal the cap exists to pre-empt. Set the rail where the demo actually
# lives, and the capacity checks below stay exactly as they were.
#
# The vm_role validation above still budgets for {role}-win-{2 digits} = 15
# characters. That is now an over-estimate rather than the exact worst case --
# a deliberately conservative bound, not a stale one.
variable "vm_count" {
  description = "Number of VMs to create for this role. Budget-guarded by the precondition in locals.tf and by the cluster-wide check in provision_vm.yml."
  type        = number
  default     = 1

  validation {
    condition     = var.vm_count >= 1 && var.vm_count <= 2 && floor(var.vm_count) == var.vm_count
    error_message = "vm_count must be 1 or 2."
  }
}

# ---------------------------------------------------------------------------
# OS selection — drives count-based conditionals on the Windows and Linux
# resource blocks.
# ---------------------------------------------------------------------------

variable "os_type" {
  description = "Which OS to provision: windows, or linux (RHEL 9). One apply builds one OS — `both` was removed in #301 when state became per-OS; run it twice to get both. Windows requires this environment to be linked to a published golden image — playbooks/link_windows_image.yml (#3)."
  type        = string
  default     = "linux"

  validation {
    condition     = contains(["windows", "linux"], var.os_type)
    error_message = "os_type must be one of: windows, linux. `both` was removed in #301 -- state is keyed per OS, so one apply builds one OS. Run it twice to get both."
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

variable "windows_admin_password" {
  # NOT the password baked into the golden image. The image ships a random one
  # generated at build time and thrown away (image.builder.pipeline#24), so a
  # leaked containerdisk exposes a string nobody uses. The real password is set
  # here, on the clone, by the sysprep unattend in main.tf — which is why the
  # quay repository being private is a convenience and not a security control.
  #
  # playbooks/provision_vm.yml passes this environment's own
  # windows_admin_password, separate from the Linux one since #305.
  #
  # It was shared with linux_admin_password between #201 and #305, and the
  # reason is easy to get backwards: #201's defect was SCOPE. The old
  # windows_admin_password was a single GLOBAL value because it lived baked in
  # the image both environments pull, which cannot be reconciled with a
  # per-environment credential. #201 moved the real password onto the clone --
  # and once it left the image, nothing forced it to equal the Linux one.
  # Per-environment is compatible with #201; a global key would still not be.
  #
  # It also has to be LONGER than the Linux one: CIS L1 for Windows Server 2022
  # requires 14 characters, and provision_vm.yml asserts that before applying.
  description = "Password for the local Windows administrator created by the sysprep unattend. Set per environment; not the throwaway password baked into the golden image."
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
  description = "DataSource cloned for the Linux VM. rhel9-cis-l1 is the CIS-hardened golden image from image.builder.pipeline; rhel9 is the stock CNV boot source."
  type        = string
  default     = "rhel9-cis-l1"
}

variable "windows_datasource_name" {
  # CNV ships win2k22 as an EMPTY placeholder (Ready=False, "PVC not found").
  # playbooks/link_windows_image.yml adds a DataImportCron whose
  # managedDataSource is this same name, which takes the placeholder over and
  # populates it. Change this and win_managed_datasource in that playbook
  # together — they are one contract.
  description = "DataSource cloned for the Windows VM. Populated by playbooks/link_windows_image.yml (#3); empty until that runs."
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
