# AAC pack — generated, do not edit here

This tree is **generated** from the private `ynotbhatc/compliance` repository
(commit `c8135bfca32d`, 2026-10-08T17:29:20Z) by its
`scripts/export_sales_demos_pack.py`, and refreshed by a weekly pull request
from the AAC lab's Automation Platform. Edit the source there; a change made
here is overwritten by the next sync. `MANIFEST.yml` lists every file with its
source path and checksum.

| Directory | What it is |
|---|---|
| `playbooks/` | The AAC playbooks the Compliance as Code job templates run (`project: Sales Demos`, `playbook: aac/playbooks/<name>.yml`) |
| `vars/`, `files/` | What those playbooks read relative to themselves; `vault_secrets.yml` is deliberately absent, the platform's credentials supply secrets |
| `opa-routing/policies/` | The AO decision policies `install_opa_routing.yml` loads: the policy decides, the model recommends |
| `ao/workflows/`, `ao/components.yml` | The six AO workflow definitions as the AO API returns them, and what each needs |
| `grafana/` | AAC dashboards over the `aac` evidence database |

Plan and phases: ericcames/sales.demos#841. The pack is scrubbed on export:
lab identifiers, secret-shaped strings and customer names fail the export.
