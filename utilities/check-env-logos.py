#!/usr/bin/env python3
"""Fail when a committed env logo has drifted from its base64 sidecar, or when a
gateway_settings.yml points at a logo that is not there.

Issue #422.

THE PROBLEM THIS SOLVES. `assets/aap-branding/logo-<env>.png.b64` is a generated
copy of the `.png` beside it, and `inventory/group_vars/<env>/gateway_settings.yml`
feeds it to AAP as `custom_logo` at playbook run time. Nothing checked either
half. The `generated-files` job already says why that matters, about a different
file:

    A committed generator output that nothing verifies is a copy waiting to
    drift.

Replace the PNG and forget the sidecar and AAP keeps serving the old logo, with
git looking correct and `config.yml` reporting `changed` exactly as it always
does.

WHY IT DOES NOT REGENERATE THE PNG TO COMPARE. `make-env-logo.py` needs Pillow,
ImageMagick with the librsvg delegate, and the Red Hat Display font, and font
rasterisation is not byte-reproducible across machines. A regenerate-and-diff
check would fail on a fontconfig change rather than on real drift -- the same
reason `check-docs-artifacts.py` deliberately skips `demo-page.png`.

Base64 is deterministic, so the sidecar can be verified exactly, with no
dependencies and in milliseconds. That catches the drift that actually happens.

WHY IT ALSO CHECKS THE LOOKUP PATH. A `file` lookup that resolves to nothing
raises at run time -- during `config.yml`, against a live environment, which is
the worst place to find out. Worse, one that resolves to the *wrong but existing*
file reports `changed` and looks green. This asserts the path in the YAML names a
file that exists, so moving these assets can never silently break the gateway.
"""

from __future__ import annotations

import base64
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
ASSETS = REPO / "assets" / "aap-branding"
INVENTORY_DIR = REPO / "inventory"
GROUP_VARS = INVENTORY_DIR / "group_vars"

# inventory_dir + '/../<path>' inside an ansible.builtin.file lookup
LOOKUP = re.compile(
    r"lookup\(\s*'ansible\.builtin\.file'\s*,\s*inventory_dir\s*\+\s*'/\.\./([^']+)'\s*\)"
)


def check_sidecars() -> list[str]:
    problems = []
    pngs = sorted(ASSETS.glob("logo-*.png"))
    if not pngs:
        return [f"no logo-*.png found in {ASSETS.relative_to(REPO)} -- did they move?"]
    for png in pngs:
        sidecar = png.with_suffix(png.suffix + ".b64")
        if not sidecar.exists():
            problems.append(f"{sidecar.relative_to(REPO)} is missing")
            continue
        expected = base64.b64encode(png.read_bytes()).decode() + "\n"
        if sidecar.read_text() != expected:
            problems.append(
                f"{sidecar.relative_to(REPO)} is not the base64 of "
                f"{png.name} -- run: python3 utilities/make-env-logo.py "
                f"--env {png.stem.removeprefix('logo-')}"
            )
    return problems


def check_lookup_paths() -> list[str]:
    problems = []
    checked = 0
    for yml in sorted(GROUP_VARS.rglob("gateway_settings.yml")):
        for rel in LOOKUP.findall(yml.read_text()):
            checked += 1
            # Model the lookup exactly: inventory_dir + '/../' + rel
            target = (INVENTORY_DIR / ".." / rel).resolve()
            if not target.exists():
                problems.append(
                    f"{yml.relative_to(REPO)} looks up '{rel}', which does not "
                    f"exist -- config.yml would raise against a live environment"
                )
    if checked == 0:
        problems.append(
            "no inventory_dir file lookups found in any gateway_settings.yml -- "
            "this check would pass on an empty set, which is worse than no check"
        )
    return problems


def main() -> int:
    problems = check_sidecars() + check_lookup_paths()
    if problems:
        for p in problems:
            print(f"::error::{p}")
        print(f"\nFAILED: {len(problems)} problem(s) in the AAP branding assets.")
        return 1
    print("AAP branding assets: sidecars match their PNGs, lookups resolve.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
