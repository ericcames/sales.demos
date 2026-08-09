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
