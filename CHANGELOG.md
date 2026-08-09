# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
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
