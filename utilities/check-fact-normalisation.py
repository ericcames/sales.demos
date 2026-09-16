#!/usr/bin/env python3
"""Fail when the three copies of the KubeVirt fact normalisation diverge.

Issue #647, closing the trap #160 left open.

WHY THERE ARE THREE COPIES. On a KubeVirt guest `ansible_virtualization_type`
and `ansible_virtualization_role` come back as the literal string "NA" -- on
RHEL, and on Windows, where ansible.windows' setup.ps1 ends its detection with
the same literal fallback. `| default()` never fires, because "NA" is defined.

#160 is what that costs when one consumer handles it and another does not: a
live VM served a page reading "KVM (guest)" while the file the page invites you
to curl said "NA". Same host, same run. The page made a claim and the artifact
offered as evidence denied it.

The fix #160 reached for was to define the value once, and it did -- once per
role. `demo_facts` is now a third consumer, so there are three definitions:

    playbooks/roles/linux_configure/vars/main.yml     linux_configure_virt_*
    playbooks/roles/windows_configure/vars/main.yml   windows_configure_virt_*
    playbooks/roles/demo_facts/vars/main.yml          demo_facts_virt_*

CONSOLIDATING THEM IS A REFACTOR OF THE DAY 1 CRITICAL PATH, and #647 is not
that change. So the copies stay and drift is made impossible instead: this
compares the expressions and fails if any one of them moves alone.

THE COMPARISON IS ON THE EXPRESSION, NOT THE VARIABLE NAME. Each file uses its
own role prefix, which is correct -- role variables should be namespaced. Only
the right-hand side has to agree, so the prefix is stripped before comparing and
whitespace is normalised, because these are folded YAML scalars whose line
breaks carry no meaning.

WHAT THIS DOES NOT DO. It does not check that the expression is *right*. Three
identical copies of a wrong rule still pass, and that is the correct scope: #160
was not a wrong rule, it was two rules where there should have been one. The
rule itself is verified on a live KubeVirt guest by the Day 1 chain, which is
where a fact about a hypervisor can actually be checked.

Needs PyYAML. No cluster.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parent.parent
ROLES = REPO / "playbooks" / "roles"

# role directory -> variable prefix. Add a row when a fourth consumer appears;
# an unreconciled copy is the whole failure mode this exists to catch.
SOURCES = {
    "linux_configure": "linux_configure_",
    "windows_configure": "windows_configure_",
    "demo_facts": "demo_facts_",
}

# Suffixes every copy must define identically.
SHARED = ("virt_type", "virt_role")


def normalise(expr: str, prefix: str) -> str:
    """Strip the role prefix and collapse whitespace so folded scalars compare."""
    # The golden-image derivations reference their own prefixed variables; the
    # virt ones do not, but strip anyway so the function is honest for both.
    expr = expr.replace(prefix, "")
    return re.sub(r"\s+", " ", expr).strip()


def main() -> int:
    collected: dict[str, dict[str, str]] = {}
    failures = 0

    for role, prefix in SOURCES.items():
        path = ROLES / role / "vars" / "main.yml"
        if not path.exists():
            print(f"::error::{path.relative_to(REPO)} is missing")
            return 1
        data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        for suffix in SHARED:
            key = prefix + suffix
            if key not in data:
                print(
                    f"::error file={path.relative_to(REPO)}::{key} is no longer "
                    f"defined -- check-fact-normalisation.py can no longer "
                    f"compare this copy"
                )
                failures += 1
                continue
            collected.setdefault(suffix, {})[role] = normalise(data[key], prefix)

    for suffix in SHARED:
        variants = collected.get(suffix, {})
        distinct = set(variants.values())
        if len(distinct) > 1:
            failures += 1
            print(f"::error::'{suffix}' differs between roles -- #160 all over again")
            for role, expr in sorted(variants.items()):
                print(f"    {role:18} {expr}")
            print()

    if failures:
        print(
            f"\n{failures} problem(s). These three expressions must stay "
            f"identical: a guest reports the same 'NA' whatever is asking, so "
            f"the demo page, facts.json and facts.html must normalise it the "
            f"same way or one of them will contradict the others on a live VM.",
            file=sys.stderr,
        )
        return 1

    print(f"OK: {len(SOURCES)} copies agree on {len(SHARED)} shared expressions.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
