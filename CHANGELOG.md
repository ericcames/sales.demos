# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed -- prepare_env no longer waits 15 minutes to report a 44s answer (#39)
- `playbooks/prepare_env.yml` — the smoke-namespace cleanup ran with
  `wait: true` and dominated the whole playbook. Measured across two live
  environments, an identical 44s/45s build produced a total runtime of ~2.3 min
  on a warm cluster and **~17.5 min on a fresh one**, because deleting the
  namespace blocks on DataVolume and PVC teardown, which on a freshly installed
  cluster contends with the CSI clone still materialising underneath. The
  playbook was slowest on exactly the environment where the answer matters most.
  Now `wait: false` — **42s total on the environment that previously took
  17m29s**, a 25× reduction with the same verdict. The namespace still goes
  away; it was observed gone within a minute, unattended.

### Changed -- the real end-to-end timings are written down (#39)
- The docs quoted "5m47s cold, ~30s warm" for a VM build, but never said how
  long a fresh RHDP environment takes to become demo-ready. Now stated in
  `README.md` and the `ocpvirt-new-env` skill: **~4 min to install CNV, ~2 min
  to verify, and roughly 20 minutes end to end from a bare RHDP environment** —
  most of which is the environment provisioning itself.
- Two corrections recorded rather than quietly dropped:
  - **The 5m47s cold build did not reproduce.** A brand-new environment built in
    44s, the same as a day-old one: all six boot-source VolumeSnapshots were
    `readyToUse` before CNV finished installing, because the import runs
    alongside the install. The original figure most likely came from building
    immediately after install and catching the import mid-flight.
  - **The CNV install is ~4 minutes**, not the ~15 stated while #30 was in
    progress — that was inferred from a background task's apparent runtime
    rather than measured.

### Added -- fresh-environment readiness (#30)
- `playbooks/prepare_env.yml` and the `ocpvirt-new-env` skill. Answers one
  question — would a live VM build in front of a customer be fast? Measured on
  the sandbox: **5m47s cold versus ~30s warm**, and that gap is not Terraform's
  doing. The module is already on the fast path; the slow case is building
  against a cluster whose boot source has not finished importing, so the fix
  belongs in environment spin-up rather than the VM definition.
- **It asserts rather than assumes**, because every check corresponds to a way
  an environment looks fine and is still slow:
  - The `rhel9` DataSource can report `Ready` while the **VolumeSnapshot behind
    it** is still materialising — the actual slow-build state. The snapshot is
    resolved from `spec.source` by name and checked for `readyToUse`, rather
    than inferred from the DataSource condition. Handles the PVC form too.
  - A StorageProfile reporting `copy` instead of `csi-clone` makes every create
    pay a full disk copy, which no amount of pre-warming fixes. On RHDP the
    default StorageClass must be the ceph-rbd one; **noobaa reports `copy`**.
  - The IngressController must actually be Available, or the Routes giving demo
    VMs their web URL (#29) are never admitted. A mismatch between
    `openshift_apps_domain` and the cluster's real domain warns rather than
    fails — a stale value produces URLs that resolve nowhere.
- **And it builds a real VM**, times it, and destroys it. A playbook that has
  verified everything except "can this cluster make a VM" is the failure mode it
  exists to prevent. The smoke VM lives in its own namespace, removed in an
  `always:` block so a slow or failed run leaves nothing eating the memory
  budget. It uses Red Hat's `u1.small` rather than the repo's `sd1.*` types,
  which do not exist until `terraform/ocpvirt` has run — and this playbook is
  for clusters where it has not.
- `playbooks/tasks/resolve_storage_class.yml` — the StorageClass discovery
  extracted out of `install_cnv.yml` so both use one definition rather than two
  that drift, the same reasoning that extracted `assert_target_environment.yml`
  in #24.

### Changed -- documentation caught up with the code (#30)
- `ROADMAP.md` — the sizing table still listed `u1.small` / `u1.medium` /
  `u1.large`. #2 moved to repo-owned `sd1.*` types because `u1.*` has no 6 GiB
  size: at `u1.large`'s 8 GiB, `os_type=both` needs ~16.6 GiB against the
  ~14.2 GiB actually free once AAP and CNV are running, so it would never
  schedule. Also notes that the real ceiling is enforced in `locals.tf` at plan
  time, not by the table.
- `docs/plan/ocpvirt-demo-plan.md` — the state backend said "local state
  initially; optionally the NooBaa S3 endpoint later", which #4 found
  unworkable. Now records the `kubernetes` backend and why state lives in its
  own long-lived namespace.
- `inventory/group_vars/demo/connection.yml` — the `demo` environment is live
  rather than placeholders, so #16's environment isolation is now load-bearing
  instead of theoretical: `--limit demo` and `--limit sandbox` reach two
  different clusters.

### Changed -- the EE is pulled from Private Automation Hub (#35)
- `inventory/group_vars/aap/hub_ee_registries.yml` and
  `hub_ee_repositories.yml` — PAH mirrors `quay.io/zigfreed/sales-demos-ee` into
  a local `sales_demos_ee` repository, and Controller pulls the local copy.
  quay stays the published artifact and the source of truth; this removes
  quay.io from the demo's *runtime* dependencies and makes the pull
  cluster-local rather than an internet round trip.
- **The sync has two gates and needs both**, which is invisible if you only read
  one file: the repository item must carry `sync: true`, *and* a variable named
  `hub_ee_repository_sync` must be **defined** (dispatch includes the role on
  `... is defined` and never reads the value). Miss either and there is no
  error — the repository is created, stays empty, and Controller later fails to
  pull an image that was never mirrored. That flag is deliberately not suffixed
  `_all`: it is a scalar, and dispatch's wildcard merge handles only lists and
  dicts.
- `controller_execution_environments.yml` — image is now
  `{{ aap_hostname }}/sales_demos_ee:v1.0.0`. **Templated on purpose**: PAH is
  fronted by the AAP gateway on the AAP hostname, which differs per environment,
  so a literal would make this shared `_all` entry wrong for one of
  sandbox/demo. The name uses underscores because Hub repository names allow
  only alphanumerics and underscores.
- `controller_credentials.yml` — `Sales Demos - PAH Registry` (Container
  Registry). PAH requires authentication for container pulls even when the
  repository is not private, so this is needed regardless of visibility.
- `collections/requirements.yml` — `ansible.hub` pinned to 1.1.0. It drives the
  Hub objects and was **unpinned and drifting**: 1.0.4 was installed locally
  while the execution environment ships 1.1.0.

### Notes -- why PAH works here without weakening the cluster (#35)
- AAP 2.6's gateway proxies Hub **by path** at `/api/galaxy/`; there is no
  separate hub route. `ansible.hub`'s `ah_path_prefix` already defaults to
  `galaxy`, so nothing needs overriding.
- The `*.apps` certificate is issued by Google Trust Services and is publicly
  trusted, so the cluster pulls from PAH over TLS with **no**
  `insecureRegistries` and **no** `additionalTrustedCA` — both verified still
  empty after the change.
- Verified end to end: `skopeo inspect` against PAH returns
  `sha256:a6ee9e4b110bc12d47b222af93127f8fae9f8e3d02599dd8f1b35e3204d3559b`,
  byte-identical to the quay original, and both job templates ran to success on
  the PAH-sourced image.

### Added -- Phase 3: run playbooks from AAP, and against the VMs (#4)
- `playbooks/provision_vm.yml` — ported from `dc1.azure`. Asserts inputs, runs
  `terraform init`/`apply` against `terraform/ocpvirt/`, and registers the VMs
  into AAP (`linuxweb` with SSH vars, `windemo` with WinRM vars). The output
  shape is preserved field-for-field, so Phase 4 needs no adaptation.
- `terraform/ocpvirt/backend.tf` — state moves to the **kubernetes backend**.
  Local state is fatal from AAP: an execution-environment pod is ephemeral, so
  state would vanish with the job and teardown (#6) would have nothing to
  destroy from. State lives in a Secret in a long-lived namespace of its own,
  deliberately **not** the VM namespace — `oc delete project
  sales-demos-sandbox` is the obvious way to clean up a demo and must not take
  the state with it. `secret_suffix` keys `sandbox` and `demo` apart.
- `playbooks/check_vm.yml` and the `Sales Demos - Check VMs` job template —
  the proof that AAP can run playbooks *against* a VM, not merely create one.
- Config-as-code in `inventory/group_vars/aap/`: project, both inventories, the
  inventory source, credentials, and both job templates.

### Changed -- the vaulted secrets file moved (#4)
- `inventory/group_vars/aap/secrets.yml` → **`playbooks/group_vars/aap/secrets.yml`**.
  Ansible loads `group_vars/` beside the playbook as well as beside the
  inventory, so playbooks resolve it identically. AAP does not: an SCM inventory
  source runs `ansible-inventory`, which parses every `group_vars` file next to
  the inventory. Verified against live AAP 2.6 — the vaulted file under
  `inventory/group_vars/` makes the sync die with `ERROR! Attempting to decrypt
  but no vault secrets found`; it cannot be given the password, because AAP
  rejects Vault credentials on SCM sources outright; and a custom credential
  type injecting `ANSIBLE_VAULT_PASSWORD_FILE` *would* work but is the wrong
  answer, since the sync would then write `env_secrets` and the SSH private key
  into AAP's inventory variables in plaintext. Moving it keeps secrets out of
  the inventory tree while `connection.yml` still syncs freely.
- `inventory/group_vars/{sandbox,demo}/connection.yml` — `demo_ssh_public_key`
  filled in. Both were empty, which made cloud-init emit `ssh_pwauth: true` with
  no authorized key *and* no password: the guest had no credentials at all and
  was unreachable by SSH, by `virtctl`, by anything.
- `inventory/group_vars/aap/controller_projects.yml` — `scm_branch` accepts a
  `sales_demos_branch` override. A job template validates its `playbook:`
  against the project's current checkout, so without this no config-as-code
  referencing a new playbook can be tested before merging.

### Fixed -- the private-key check never worked (#4)
- `utilities/check-no-secrets.sh` — the private-key pattern starts with
  `-----`, which `grep` parsed as an option bundle. `grep` errored, the error
  was swallowed by `2>/dev/null || true`, `hits` came back empty, and the check
  reported **pass** on files that plainly matched. Fixed with `-e`, and verified
  by planting a real key in a tracked file and watching the check fail. This is
  the guard that stops a private key reaching a public repo; it had been inert.
- `.ansible-lint` — `yaml[line-length]` moved to `warn_list`, matching what
  `.yamllint` already declared. An SSH public key is a single 575-character
  token that cannot be wrapped without risking silent base64 corruption.

### Notes -- how AAP reaches the VMs (#4)
- **No bastion and no `virtctl`.** AAP runs on the same cluster as the VMs, each
  VM has a headless Service giving stable in-cluster DNS, and there is no
  NetworkPolicy between the namespaces — so it is plain `ssh` to port 22 at the
  address `provision_vm.yml` already registers. `virtctl ssh` is the *laptop*
  path, because a laptop is outside the cluster; the execution environment does
  not ship the binary.
- The kubernetes backend will **not** accept a bare host + token despite
  advertising those keys — it builds its client through client-go's `clientcmd`,
  where they are only overrides on a base config. The playbook synthesises a
  kubeconfig and passes `config_path`; `insecure` must be passed separately
  because the backend ignores `insecure-skip-tls-verify` from the file.
- `ansible.controller` 4.8.0 has no `controller_oauthtoken`; the parameter is
  `aap_token`. A gateway token from `ansible.platform.token` returns 401 against
  `/api/controller/v2/` on AAP 2.6, so the playbook uses basic auth like
  `playbooks/config.yml` — and then has no token to leak or clean up.

### Added -- execution environment with terraform (#31)
- `execution-environment.yml` — the image AAP runs this repo's playbooks on,
  built on `ee-supported-rhel9` (AAP 2.6). It exists for one reason: Phase 3
  (#4) drives `terraform/ocpvirt/` through `ansible.builtin.command`, and no
  stock execution environment ships the terraform binary. Terraform 1.15.8 is
  downloaded and sha256-verified rather than installed from the HashiCorp yum
  repo — one pinned version, one checked artifact, no extra repo config on a UBI
  base with no subscription. `curl` and `unzip` are already in the base image.
- The base image is pinned by **digest, not tag**. `latest` moves, and the
  registry publishes no immutable tag matching what `latest` currently resolves
  to (its `version`/`release` labels are absent from `RepoTags`), so the digest
  is the only thing that names one build. This follows `aap_config`.
- `dependencies.exclude.python: [systemd-python]`. ansible-builder introspects
  every collection in the image, not just the ones requested. `ee-supported-rhel9`
  ships `ansible.eda`, whose `requirements.txt` lists `systemd-python` for its
  journald event source; no wheel is published, so pip builds from source and
  fails with `Cannot find libsystemd or libsystemd-journal` on a UBI base with no
  `systemd-devel`. Nothing here has a journald event source, so the dependency is
  pure collateral from the base image and is excluded rather than compiled.
  (`aap.lightspeed.patching` compiles it instead — correct there, because that EE
  is on `ee-minimal` where the dependency arrives through a collection in use.)
- `options.package_manager_path: /usr/bin/microdnf` — `ee-supported-rhel9` ships
  microdnf, not dnf, and ansible-builder defaults to `/usr/bin/dnf`.
- `utilities/build-ee.sh` — the build entry point. Stages `~/.ansible.cfg` into
  the gitignored `.ee-build/` so the galaxy stage can install certified
  collections, asserting first that it is a **real file**: ansible-builder's
  `COPY` does not follow symlinks, so a symlinked config silently yields an image
  with no Hub token. It is staged rather than referenced in place because an
  absolute `/home/<user>/` path is not portable and a tracked `ansible.cfg` at
  the repo root would shadow `~/.ansible.cfg` and break certified installs
  machine-wide. The token reaches the galaxy build stage only; the published
  image carries no credential.
- The script verifies the built image **as UID 1000**, which is who AAP runs a
  job as — `terraform version` must execute, and every collection pinned in
  `collections/requirements.yml` must be present at exactly that version. The
  in-Containerfile check cannot do this: ansible-builder emits `USER 1000` after
  every `append_final` step, so those steps all run as root.
- `inventory/group_vars/aap/controller_execution_environments.yml` — registers
  `quay.io/zigfreed/sales-demos-ee:v1.0.0` in AAP, applied by
  `playbooks/config.yml` via the dispatch role like every other object. It lives
  in `group_vars/` rather than `demos/ocpvirt/` because dispatch reads
  `group_vars` implicitly and nothing loads `demos/ocpvirt/` yet; it can move
  when #4 adds a loader. A **public** quay repository on purpose, so the cluster
  pulls it with no image pull secret and no AAP registry credential.
- `collections/requirements.yml` — `cloud.terraform` 4.0.0 pinned. The binary,
  not this collection, is the hard requirement for Phase 3, but pinning it keeps
  the module set identical on both entry points and lets `ansible-lint` resolve
  it locally.
- `.claude/skills/sales-demos-ee-build/` — build, verify, and publish the EE.
  No playbook, deliberately: like `collections-sync` it touches a laptop and a
  registry, never a demo environment, so it must never run from AAP. Carries the
  immutable-tag rule and the build gotchas.

### Added -- public SSH and HTTP access (#29)
- `terraform/ocpvirt/variables.tf` — `demo_ssh_public_key` variable. When set,
  cloud-init injects the key via `ssh_authorized_keys` and disables password-based
  SSH (`ssh_pwauth: false`). A public key is not a credential, so it lives in each
  environment's `connection.yml` beside `linux_admin_username`, not in the vault.
  The `accessCredentials` + `qemuGuestAgent` mechanism was tried first but the
  RHEL 9 cloud image's guest agent fails with "failed to create directory
  '/home/cloud-user/.ssh': File exists" — a QEMU guest agent `mkdir` bug —
  and the `guest-exec` fallback is disabled by RHEL 9's security policy.
  Cloud-init works reliably; the trade-off is that key rotation requires a VM
  restart rather than a live push.
- `terraform/ocpvirt/variables.tf` — `openshift_apps_domain` variable, the
  `*.apps` ingress domain used to construct Route hostnames at plan time.
  Required for HTTP access; without it the Route and web Service are skipped.
- `terraform/ocpvirt/main.tf` — `-web` ClusterIP Service (port 80) and
  `route.openshift.io/v1` Route per Linux VM. The headless Service is unchanged
  (in-cluster DNS for AAP inventory). The Route returns 503 until httpd is
  installed by the AAP demo content (#5); that is expected, not a bug.
- `terraform/ocpvirt/outputs.tf` — `web_url` (the Route URL, null when
  `openshift_apps_domain` is unset) and `ssh_command` (the `virtctl ssh` command
  for the current VM, null when `os_type` excludes linux).
- `inventory/group_vars/{sandbox,demo}/connection.yml` — `demo_ssh_public_key`
  and `openshift_apps_domain` fields added to both environments.

### Notes -- NodePort spike (#29)
- NodePort was spiked on the RHDP sandbox cluster and is **filtered**. The RHDP
  firewall blocks high ports — `ssh -p <nodePort> cloud-user@<public-ip>` returns
  "No route to host". SSH access uses `virtctl ssh` instead, which tunnels over
  the Kubernetes API (port 6443, confirmed open). The spike Service was created,
  tested, and deleted in a single session; no residue remains.

### Added
- `terraform/ocpvirt/` — Phase 1. Provisions Linux and Windows VMs sized by
  `sd1.*` cluster instance types, each with a headless Service giving a stable
  in-cluster DNS name, since an OpenShift Virt VM has no plan-time-knowable
  address. The `linux_inventory` / `windows_inventory` output shape is preserved
  field-for-field from `dc1.azure/terraform`, which Phases 3 and 4 consume. A
  precondition enforces the guest-memory budget so an over-budget request fails
  in `plan` rather than leaving a VM `Pending`. Verified on the sandbox: VM
  `Running` and `Ready` in 5m47s, PVC `Bound`, `terraform plan` clean. (#2)

### Fixed
- `terraform/ocpvirt/` — `terraform plan` could never come back clean, so the
  module could not be trusted to report real drift. Two independent causes, both
  cases of the cluster owning fields Terraform believed were its own:
  - The namespace drifted forever. OpenShift's SCC controller stamps every
    namespace with the UID/GID/MCS ranges it allocated plus the derived
    pod-security level; Terraform planned to strip all four on every run and the
    controller put them straight back. Applying it would also have handed the
    guests a different UID range than the one their pods were admitted under.
    Now ignored via `lifecycle`, as cluster-owned.
  - `spec.template.metadata` is `x-kubernetes-preserve-unknown-fields`, so the
    provider has no schema and infers the object type from the manifest — making
    the key set load-bearing. KubeVirt's webhook adds
    `kubevirt.io/pci-topology-version` and a null `creationTimestamp`, which the
    manifest never declared, so plan failed reading the refreshed object back and
    apply failed with "Provider produced inconsistent result". `computed_fields`
    does not help here: it can override a value but cannot add a missing
    attribute. Both keys are now declared, with `computed_fields` still covering
    their values.
- `playbooks/install_cnv.yml` — installs OpenShift Virtualization: namespace,
  OperatorGroup, `kubevirt-hyperconverged` Subscription on the `stable` channel,
  and the `HyperConverged` CR, then waits for the operator to report `Available`
  and the RHEL boot-source DataSource to be `Ready`. Idempotent, no prompts,
  every input via `extra_vars`. Discovers the cluster's default StorageClass at
  run time rather than hard-coding one, so it is not tied to a single catalog
  item. Deliberately does not enable hugepages, KSM, or workload partitioning —
  each writes a MachineConfig and reboots the node, and AAP is co-resident on
  the only node in this catalog item. (#1)
- `playbooks/setup.yml` — Phase 0 entry point; currently imports
  `install_cnv.yml`. The AAP bootstrap half of #1 imports here when it lands, so
  the skill, the README table, and the future job template never re-point.
- `.claude/skills/ocpvirt-setup/SKILL.md` — first in-repo skill. Preflight
  checks, a cluster-side check for whether CNV is already present, then invokes
  `playbooks/setup.yml`. No business logic, per the two-entry-point contract.
  Ends in a verification step that queries the cluster for the
  `kubevirt.io`/`cdi`/`hco`/`instancetype` API groups, the `u1` instance-type
  shapes the sizing tiers depend on, and `devices.kubevirt.io/kvm` on the node —
  a green Ansible recap is not treated as proof. (#1)
- `kubernetes.core.k8s` and `kubernetes.core.k8s_info` added to `.ansible-lint`
  `mock_modules` so the offline CI lint gate can resolve them.

- Initial repository skeleton for the two-axis layout: `demos/` by demo,
  `terraform/` by platform, `inventory/group_vars/` by environment.
- `docs/plan/ocpvirt-demo-plan.md` — environment research confirming the RHDP
  "Ansible Product Demo" catalog item supports OpenShift Virtualization, plus
  the phase-by-phase implementation plan.
- `ROADMAP.md` covering phases 0–4 and the t-shirt sizing tiers.
- Secrets convention: `inventory/group_vars/<env>/secrets.yml` as the single
  place every environment-specific value lives, with `secrets.yml.example` as
  the repo's only `.example` file.
- `.gitignore` as the first commit, so no environment-specific value can enter
  history.
- CI lint gate ported and adapted from `aap_config`: yamllint, ansible-lint,
  a secret-hygiene guard, and a portability check on in-repo skills.
- `utilities/check-no-secrets.sh` — enforces the pre-push audit automatically.
  Matches the shape of real credentials so docs and `.example` placeholders pass
  while genuine values fail the build.
- `.yamllint`, `.ansible-lint`, and pinned `collections/requirements.yml`.
- GitHub CODEOWNERS, PR template, issue templates, and security policy.
- `.claude/skills/collections-sync/SKILL.md` — pins, installs, and verifies the
  collections, failing loudly on drift. No playbook, deliberately: it touches
  the laptop's collection path, never a demo environment, so it must never run
  from AAP. (#8)

- Shared AAP configuration ported from `ericcames/aap_config` into
  `inventory/group_vars/aap/` — `aap_settings.yml`
  (`dispatch_include_wildcard_vars`, `aap_configuration_secure_logging`),
  `aap_organizations.yml`, `controller_settings.yml` (Automation Analytics and
  subscriptions), and `gateway_settings.yml` (the `custom_login_info` sign-in
  banner). Values verbatim; comments adapted to this repo, which has two
  environments and no export tooling. Every key was verified present on the
  live AAP 2.6 catalog item first, so the standing "aap_config targets 2.7, do
  not copy its settings verbatim" caution does not apply to these files.
  Collection pins already matched exactly. Nothing consumes these variables
  until the AAP bootstrap half of #1 lands. (#14)
- `vaulted_subscriptions_client_id` and `vaulted_subscriptions_client_secret`
  added to `secrets.yml.example`. `controller_settings.yml` requires both in
  every environment or the apply fails with an undefined-variable error. (#14)

### Added — first-time setup and run logging (#26)
- `.claude/skills/sales-demos-first-time/SKILL.md` — one-time setup for a new
  machine. Audits what exists, guides what is missing, and validates each step by
  exercising the real path (inventory resolution, the vault, and the Hub token
  lookup together) rather than checking files exist.
  - It is explicit that the vault password **cannot be created by a new user**.
    `group_vars/aap/secrets.yml` is committed but encrypted, so without
    `~/secrets/.vault_pass_sales_demos` nothing decrypts and every playbook fails.
    It has to be handed over; there is no derivation and no recovery.
- Run logs now go to **`~/ansible-logs/`, outside the repo**, via
  `ANSIBLE_LOG_PATH`. Documented in `README.md`, the `ocpvirt-setup` skill, and
  the first-time skill. Outside the repo on purpose: this repo is public, and
  keeping logs out entirely beats relying on an ignore rule. A defensive
  `logs/` + `*.log` rule is added anyway in case someone points
  `ANSIBLE_LOG_PATH` at the working tree.
  - **Not `tee`.** In a pipeline the exit status comes from `tee`, not from
    `ansible-playbook`, so a failed run reports success. This is recorded because
    it caused a real misread during Phase 0. `ANSIBLE_LOG_PATH` also works
    without an `ansible.cfg`, which matters since a project-local one is banned.

### Changed
- `CLAUDE.md` and `README.md` now state plainly that **this repo is
  self-contained**: every skill it needs lives in `.claude/skills/`, nothing
  depends on a plugin or another repo's skills, and nothing that does should be
  added. The skill-authoring guidance points at `ocpvirt-setup` as the in-repo
  example rather than at an external repo. (#26)

### Added — config-as-code apply and validate (#24)
- `playbooks/config.yml` applies the AAP objects defined in
  `inventory/group_vars/`; `playbooks/validate.yml` is the same play in check
  mode. Until now nothing in this repo ran `infra.aap_configuration.dispatch`, so
  the objects ported in #14 and the sign-in logos from #20 had never been executed
  against a real AAP.
- Both are thin — the work is `include_role: infra.aap_configuration.dispatch`,
  with variables arriving implicitly from `inventory/group_vars/`. Basic auth via
  `aap_username`/`aap_password`; no OAuth token is minted, so there is nothing to
  leak and nothing to clean up in an `always:` block.
- The environment guard from #16 moves to
  `playbooks/tasks/assert_target_environment.yml` rather than being copied a third
  time; `install_cnv.yml` adopts it and still runs at `changed=0`.
- Verified against the sandbox by running it: check mode `ok=36 changed=4`, then
  the apply `ok=37 changed=2`, then confirmed against the AAP API — organization
  created, banner set, and `custom_logo` byte-identical to the committed
  `docs/images/logo-sandbox.png.b64`.
- Documented check-mode caveat: some roles' "wait for the object to exist" tasks
  report `FAILED - RETRYING` under check mode because nothing was created for them
  to find. The play still succeeds; treat check mode as a strong signal, not a
  contract.

### Changed — what the vault actually holds (#22)
- **`automation_hub_token` is no longer stored in the vault.** Nothing consumed
  it — `ansible-galaxy collection install` reads `~/.ansible.cfg` itself, which
  is the authoritative copy of that token and is shared across every repo.
  `inventory/group_vars/aap/main.yml` now reads it with an `ansible.builtin.ini`
  lookup against `~/.ansible.cfg`, matching how `aap.as.code` and `aap-skills`
  already do it. A vaulted second copy would have gone stale silently on the
  next rotation, with nothing to detect the drift.
  - Reads `~/.ansible.cfg`, **not** `~/.ansible/ansible.cfg`. Both hold the same
    token today, but the latter is a frozen leftover from when the former was a
    symlink, and will drift. `aap-skills` still points at the stale path.
  - Known limitation, documented in the file: the lookup resolves on the
    controller, so it will not resolve inside an AAP execution environment. The
    only consumer is the AAP bootstrap, which is inherently laptop-side.
- **The Automation Analytics credentials are now real, not `CHANGEME`.**
  `vaulted_subscriptions_client_id` and `_client_secret` are required by
  `controller_settings.yml` for every environment (#14) but were seeded as
  placeholders. Copied from `aap_config`'s qa vault — the same Red Hat service
  account — by piping between `ansible-vault` invocations, so the values never
  touched a plaintext file or shell history.
  - Consequence recorded in the vault file's header: they now live in two vaults
    with no shared secret store, so rotating the service account means updating
    both.
- `secrets.yml.example` stays `CHANGEME` for the analytics keys — it is a
  template, not a value store — and now explains that the Hub token is not there.

### Added — per-environment sign-in logos (#20)
- `inventory/group_vars/<env>/gateway_settings.yml` sets the gateway's
  `custom_logo` to an environment-badged version of the AAP lockup, so the
  sign-in page shows which environment you are entering. Green for `sandbox`,
  red for `demo` — the environment you break, and the one you show customers,
  reusing `aap_config`'s severity convention.
- `utilities/make-env-logo.py`, ported from `aap_config` with this repo's two
  environments in place of its dev/qa/prod. Extends the official product lockup
  rather than replacing it, so Red Hat branding survives and only a badge is
  added. Needs Pillow, ImageMagick with the librsvg delegate, and Red Hat
  Display.
- `docs/images/` — `aap-logo-white.svg` plus the generated `logo-{sandbox,demo}.png`
  and their base64 sidecars, all committed so they render on GitHub and so a
  clone does not need ImageMagick to apply the config.
- `custom_logo` changes the **sign-in page only**, never the post-login masthead,
  which is a bundled UI asset rather than a setting. Confirmed on AAP 2.6: 44
  gateway settings exist and none of them mark the environment after login.
- Relies on `dispatch_include_wildcard_vars` merging `gateway_settings_all` with
  `gateway_settings_<env>`. The shared `custom_login_info` banner stays in
  `group_vars/aap/`, and the per-environment files set only `custom_logo` —
  verified disjoint, since merging is per-key and a scalar in both would mean the
  environment file wins rather than combines. The setting reaches a real gateway
  only once an AAP apply playbook exists (the open half of #1).

### Changed — secrets model (#18)
- **`secrets.yml` is now vault-encrypted and committed, not gitignored plaintext**,
  matching `aap_config`. One file at `inventory/group_vars/aap/secrets.yml`,
  vault-id `sales.demos`, loaded for every environment because it sits in the
  `aap` group directory. Replaces the per-environment gitignored files.
- **It holds credentials only.** Per-environment credentials are keyed under
  `env_secrets` by environment name; each `connection.yml` selects its slice with
  `env_secrets[aap_env_name]`, which is also what keeps `--limit demo` from
  reaching sandbox's credentials (#16).
- **`connection.yml` now carries the environment-specific non-secrets** in
  committed plaintext — `aap_hostname`, `openshift_api_url`, usernames,
  namespaces. It previously held structure only. A new RHDP environment is now a
  two-file edit: that `connection.yml` plus two keys in the vault.
- **RHDP URLs are no longer treated as sensitive.** `*.dyn.redhatworkshops.io`
  hostnames are ephemeral demo-platform addresses, not customer-identifying, and
  are committed in the clear on purpose — that is what lets the vaulted file hold
  credentials only. The RHDP-hostname pattern is removed from
  `utilities/check-no-secrets.sh`. This reverses a rule previously stated in
  `CLAUDE.md`, `CONTRIBUTING.md`, `README.md`, and the plan doc, all updated.
- **`utilities/check-no-secrets.sh` guard inverted.** The "no tracked
  `secrets.yml`" rule is replaced by "a tracked `secrets.yml` must begin with
  `$ANSIBLE_VAULT`", checked against the committed blob rather than the working
  tree. Since `secrets.yml` is no longer gitignored, this is the only thing
  preventing a plaintext credential file from being pushed. Every other pattern —
  bearer tokens, private keys, AWS and GitHub tokens, quay credentials — is
  unchanged. Verified by triggering it: a staged plaintext `secrets.yml` fails
  with exit 1.
- `.gitignore` drops the `inventory/group_vars/*/secrets.yml` rule and adds vault
  password patterns. The password itself lives outside the repo at
  `~/secrets/.vault_pass_sales_demos`, following the same convention as
  `aap_config`'s `.vault_pass_<env>` files.
- `.claude/skills/ocpvirt-setup/SKILL.md` — two real breakages fixed, not just
  wording. Its preflight asserted `git check-ignore` *succeeds* on `secrets.yml`,
  which is now exactly backwards; and its preflight and verification blocks
  `yaml.safe_load`ed the secrets file directly, which fails on ciphertext. Both
  now resolve credentials through `ansible … -m debug` with `--vault-id`, so the
  `--limit` selects the environment by the same path the playbook takes.

### Fixed
- **`--limit demo` silently targeted `sandbox`.** Both environment groups in
  `inventory/hosts.yml` pointed at the same host, `localhost`. `--limit` filters
  which hosts run, not which `group_vars` load, so a host in two environment
  groups loaded both environments' variables — and same-level groups resolve
  alphabetically with the later name winning, so `sandbox` always beat `demo`.
  Asking for `demo` returned sandbox's hostname and sandbox's bearer token with
  no warning, which meant the `demo` environment could not be targeted at all.
  Each environment now has its own host (`sandbox-local`, `demo-local`), so
  `group_vars` stop merging. Adding a `demo/secrets.yml` would not have fixed
  this; `sandbox` still won. (#16)
- Playbooks target `hosts: aap` and assert that exactly one environment is in
  scope, so a run without `--limit` fails closed instead of configuring both
  environments at once. An optional `-e target_env=<env>` makes the play verify
  the inventory resolved to the environment the caller intended. `--limit
  sandbox` and `--limit demo` are unchanged as invocations. (#16)

### Changed
- `aap_organization_name` in `inventory/group_vars/aap/main.yml` moved
  `Default` → `IT Service Automation`, matching the organization
  `aap_organizations.yml` declares, so the repo names one organization rather
  than two. A fresh RHDP environment ships `Default` and `Ansible Product Demos
  (APD)`, so the first apply creates it. (#14)
- **Every collection in `collections/requirements.yml` is now pinned to an exact
  version.** `ansible.platform` (2.7.20260604), `ansible.controller` (4.8.0),
  `kubernetes.core` (6.4.0), and `redhat.openshift_virtualization` (2.3.0) were
  floating, so two laptops could resolve different code. Pins record the
  versions Phase 0 was validated against, not the newest published. (#8)
- `infra.aap_configuration` pin moved 4.2.0 → 4.7.0 to match what is installed
  and used. Nothing in this repo consumes it yet; revisit when the AAP bootstrap
  half of #1 lands. (#8)
- `.gitignore` now covers `.ansible/`, ansible-lint's artifact directory.
  Collections install to `~/.ansible/collections` and are never vendored here.
  (#8)
- `inventory/hosts.yml` pins `ansible_python_interpreter` to
  `{{ ansible_playbook_python }}`. Interpreter discovery otherwise picks whatever
  `/usr/bin` python it finds first, which on Fedora can be an older minor version
  without the `kubernetes` client. Pinned in the inventory rather than an
  `ansible.cfg`, which would shadow `~/.ansible.cfg` and break certified
  collection installs. (#1)
- `docs/plan/ocpvirt-demo-plan.md` records the Phase 0 validation run. The
  original research stands — it correctly reported `kubevirt-hyperconverged` as
  *available in the operator catalog*, not installed — but the doc read as a
  plan with nothing confirming it had been executed. Now states outright that a
  freshly provisioned environment has no `kubevirt.io` API group, and adds the
  observed versions and timings, confirmation of the `u1` instance-type shapes
  the sizing tiers depend on, the decision to discover the default StorageClass
  rather than hard-code it, and a note that OpenShift version and cluster ID are
  per-environment samples rather than properties of the catalog item. (#9)

### Removed
- Three ansible-lint-generated module mocks that were tracked under
  `.ansible/collections/ansible_collections/`. They are regenerated from
  `.ansible-lint` `mock_modules` on every run, so tracking them only guaranteed
  they would go stale. (#8)

### Notes
- `aap_config`'s `deploy-{dev,qa,prod}` workflows were deliberately not ported
  and will not be (#7). CI is a PR gate only; nothing deploys from GitHub
  Actions. Deploys run via `ansible-playbook` — wrapped by a skill locally, or
  as an AAP job template — which keeps every environment-specific value in the
  gitignored `secrets.yml` with no second copy in GitHub Environment secrets.
