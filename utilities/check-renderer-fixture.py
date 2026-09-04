#!/usr/bin/env python3
"""Fail when render-demo-assets.py diverges from the linux_configure role.

Issue #145, the half that #85 could not close.

WHAT #85 PROVES, AND WHAT IT DOES NOT. `check-docs-artifacts.py` verifies that
the fenced blocks in the demo docs match `render-demo-assets.py`. That is the
docs half. It says nothing about whether the *script* still matches the role,
and the script necessarily carries its own copies of things the role owns —
that is what lets it render the demo's artifacts without a cluster.

WHY THAT GAP IS WORSE THAN NO CHECK. If the renderer and the role diverge,
#85's gate stays green: the renderer and the docs agree with each other while
both disagree with the machine `linux_configure` actually builds. The green tick
then asserts something it does not mean. This script closes that.

TWO PAIRINGS ARE CHECKED.

1. `linux_configure_motd_credits`. The MOTD "Powered by" list is data, not
   markup — motd.j2 iterates it — and it is defined in the role defaults and
   again in the renderer's FIXTURE. A straight list comparison.

2. `facts.json`. The role writes it from a Jinja dict literal piped through
   `to_nice_json`; the renderer builds the same document in `facts_json()`.
   Rather than compare key names and hope, this renders the ROLE'S OWN
   `content:` block using the renderer's fixture and diffs the result against
   `facts_json()`. That verifies structure *and* values, and it means the role
   task is the source of truth rather than a thing the docstring claims to
   match.

   `to_nice_json` is an Ansible filter, so it is supplied here as json.dumps
   with indent=4 — Ansible's own default for that filter, which is also what
   facts_json() passes.

NOT EVERY FIXTURE VALUE HAS A SOURCE OF TRUTH, and that is deliberate. Gathered
facts like `ansible_kernel`, and the pinned `ansible_date_time` that keeps output
deterministic, exist precisely because there is no cluster. Only values the role
owns are reconciled here.

Needs jinja2 and PyYAML. No cluster, no Chrome.
"""

from __future__ import annotations

import difflib
import importlib.util
import json
import sys
from pathlib import Path

import yaml
from jinja2 import Environment, StrictUndefined

REPO = Path(__file__).resolve().parent.parent
ROLE = REPO / "playbooks" / "roles" / "linux_configure"
DEFAULTS = ROLE / "defaults" / "main.yml"
TASKS = ROLE / "tasks" / "main.yml"

FACTS_TASK = "Publish the gathered facts as JSON"


def load_renderer():
    spec = importlib.util.spec_from_file_location(
        "render_demo_assets", REPO / "utilities" / "render-demo-assets.py"
    )
    if spec is None or spec.loader is None:  # pragma: no cover
        raise SystemExit("ERROR: cannot load utilities/render-demo-assets.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def report(name: str, want, got, source: str, mirror: str) -> int:
    """Print a diff for one pairing. Returns 1 on mismatch, 0 on match."""
    if want == got:
        return 0
    print(f"::error file={source}::'{name}' has diverged from {mirror}")
    print(f"\n--- {source}  (the role — source of truth)")
    print(f"+++ {mirror}  (the renderer's copy)")
    a = want if isinstance(want, list) else str(want).splitlines()
    b = got if isinstance(got, list) else str(got).splitlines()
    for line in list(difflib.unified_diff(a, b, lineterm="", n=2))[2:]:
        print(line)
    print()
    return 1


def check_motd_credits(renderer) -> int:
    defaults = yaml.safe_load(DEFAULTS.read_text(encoding="utf-8")) or {}
    key = "linux_configure_motd_credits"

    if key not in defaults:
        print(f"::error file={DEFAULTS.relative_to(REPO)}::{key} is no longer defined")
        return 1
    if key not in renderer.FIXTURE:
        print(f"::error::{key} is no longer in render-demo-assets.py's FIXTURE")
        return 1

    return report(
        key,
        list(defaults[key]),
        list(renderer.FIXTURE[key]),
        str(DEFAULTS.relative_to(REPO)),
        "utilities/render-demo-assets.py",
    )


def check_facts_json(renderer) -> int:
    tasks = yaml.safe_load(TASKS.read_text(encoding="utf-8")) or []
    task = next((t for t in tasks if t.get("name") == FACTS_TASK), None)

    if task is None:
        # The task was renamed or removed. Fail rather than silently check
        # nothing — a vanished source of truth is the drift, one level up.
        print(
            f"::error file={TASKS.relative_to(REPO)}::no task named "
            f"'{FACTS_TASK}' — check-renderer-fixture.py can no longer find "
            f"what facts_json() is supposed to mirror"
        )
        return 1

    content = (task.get("ansible.builtin.copy") or task.get("copy") or {}).get("content")
    if not content:
        print(f"::error file={TASKS.relative_to(REPO)}::'{FACTS_TASK}' has no content:")
        return 1

    env = Environment(  # noqa: S701 - rendering a trusted in-repo template
        undefined=StrictUndefined,
        trim_blocks=True,
        keep_trailing_newline=True,
        autoescape=False,
    )
    # Ansible's to_nice_json defaults to indent=4, which is what facts_json()
    # passes to json.dumps. Supplying it here keeps the comparison honest
    # rather than reformatting one side to match the other.
    env.filters["to_nice_json"] = lambda v: json.dumps(v, indent=4)

    try:
        from_role = env.from_string(content).render(renderer.FIXTURE).strip()
    except Exception as exc:  # noqa: BLE001
        print(
            f"::error file={TASKS.relative_to(REPO)}::could not render "
            f"'{FACTS_TASK}' with the renderer's fixture: {exc}"
        )
        print(
            "  Usually this means the task now uses a variable the fixture "
            "does not define — add it to FIXTURE in render-demo-assets.py."
        )
        return 1

    return report(
        "facts.json",
        from_role.splitlines(),
        renderer.facts_json().strip().splitlines(),
        str(TASKS.relative_to(REPO)),
        "utilities/render-demo-assets.py facts_json()",
    )


def main() -> int:
    renderer = load_renderer()
    failures = check_motd_credits(renderer) + check_facts_json(renderer)

    if failures:
        print(
            f"\n{failures} pairing(s) diverged. The ROLE is the source of "
            f"truth: update utilities/render-demo-assets.py to match it, then "
            f"re-run `python3 utilities/render-demo-assets.py --no-png` and "
            f"refresh the doc blocks it feeds.",
            file=sys.stderr,
        )
        return 1

    print("Renderer matches the linux_configure role: motd credits, facts.json.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
