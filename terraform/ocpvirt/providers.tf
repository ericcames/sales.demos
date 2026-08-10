# ---------------------------------------------------------------------------
# providers.tf — OpenShift Virtualization via the OFFICIAL kubernetes provider.
#
# `kubernetes_manifest` handles the KubeVirt CRDs directly. No community
# KubeVirt provider: no third-party dependency to vet or keep current, and the
# CRDs exist on the cluster once Phase 0 has run. See CLAUDE.md -> Terraform.
#
# Auth accepts either a kubeconfig or an explicit host + token. The token path
# is what AAP uses in Phase 3, where the values come from the vault-encrypted
# group_vars/aap/secrets.yml rather than a file on a runner.
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.6"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }
}

provider "kubernetes" {
  # Whichever is supplied wins; the unset one is null and ignored.
  config_path = var.kubeconfig_path != "" ? var.kubeconfig_path : null

  host     = var.openshift_api_url != "" ? var.openshift_api_url : null
  token    = var.openshift_api_token != "" ? var.openshift_api_token : null
  insecure = var.openshift_insecure
}
