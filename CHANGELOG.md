# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
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
