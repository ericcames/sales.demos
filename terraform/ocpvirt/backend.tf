# ---------------------------------------------------------------------------
# backend.tf — where Terraform state lives. (#4)
#
# WHY THIS EXISTS. The plan doc said "local state initially", which is fine on a
# laptop and fatal from AAP: an execution environment pod is ephemeral, so local
# state disappears the moment the job ends. The next run would collide with
# resources it no longer knows about, and `ocpvirt-teardown` (#6) would have
# nothing to destroy from.
#
# The kubernetes backend keeps state in a Secret in `namespace`, with Lease-based
# locking. It needs no extra infrastructure: the cluster is already what we
# authenticate to, so the SAME bearer token drives both the provider and the
# backend, and behavior is identical from a laptop and from an EE pod. NooBaa
# S3 was the alternative and is deliberately not used — it needs ODF present, an
# ObjectBucketClaim, and S3 credentials in the vault, all of which are more to
# set up and more to be missing on a fresh RHDP environment.
#
# EVERY SETTING IS DELIBERATELY EMPTY HERE. A backend block cannot reference
# variables — Terraform resolves it before variables exist — so this is a
# "partial configuration" and the real values arrive at init time:
#
#   terraform init -reconfigure \
#     -backend-config="secret_suffix=sandbox" \
#     -backend-config="namespace=sales-demos-sandbox" \
#     -backend-config="host=https://api.cluster-<id>.dyn.redhatworkshops.io:6443" \
#     -backend-config="token=<bearer>" \
#     -backend-config="insecure=true"
#
# playbooks/provision_vm.yml does exactly this. That is the same shape
# dc1.azure/playbooks/provision_vm.yml already uses for its azurerm backend, so
# the porting stays faithful.
#
# secret_suffix IS KEYED PER ENVIRONMENT (`sandbox` / `demo`) so the two never
# share state. State lands in a Secret named `tfstate-default-<secret_suffix>`.
#
# `namespace` IS NOT THE VM NAMESPACE, and that is deliberate. State must outlive
# everything it describes, so it goes in a long-lived namespace of its own
# (`sales-demos-tfstate` by default) shared by both environments. Putting it
# beside the VMs would mean an `oc delete project sales-demos-sandbox` — the
# obvious way to "clean up the demo" — silently destroying the state that tracks
# them. Teardown (#6) must never delete the state namespace.
#
# NEITHER NAMESPACE IS CREATED BY TERRAFORM. The backend will not create its own,
# and `kubernetes_manifest` does not create one for the VMs either.
# playbooks/provision_vm.yml creates both with kubernetes.core.k8s before running
# init — the same guard a sibling daily-demo repo uses for its S3 state bucket,
# and the same pattern install_cnv.yml uses for openshift-cnv. Running terraform
# by hand on a fresh cluster means creating them yourself first:
#
#   oc create namespace sales-demos-tfstate     # long-lived; never delete
#   oc create namespace sales-demos-sandbox     # disposable; holds the VMs
#
# -reconfigure, not -migrate-state: in AAP the `.terraform/` directory is fresh
# on every run, so there is never a previous backend to migrate from.
# ---------------------------------------------------------------------------

terraform {
  backend "kubernetes" {}
}
