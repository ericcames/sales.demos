#!/usr/bin/env python3
"""Generate the colour table the masthead badge reads. Issues #54, #87.

    python3 utilities/make-env-badge-config.py

Writes utilities/aap-env-badge/colors.json, which is committed so loading the
extension needs no build step.

WHAT THIS NO LONGER DOES. Until #87 this emitted a hostname -> environment map
scraped from `aap_hostname` in each inventory/group_vars/<env>/connection.yml,
and the extension decided which environment it was on by looking up
location.hostname in it. That made this script a third thing to re-run every
time RHDP handed over a new cluster, and the failure mode was silent: a stale
map does not error, it just stops recognising the environment. It went stale in
exactly that way and nobody noticed until a grey UNRECOGNIZED ENV pill turned up
next to a correctly badged green sign-in page.

The badge now asks AAP itself — `target_env`, which this repo already sets on
its job templates — so there is no hostname to keep in step. This script reads
NOTHING from connection.yml any more, which is the point: rotating an
environment does not require re-running it.

WHY IT STILL EXISTS. utilities/env_colors.py is the single source of truth for
the colour convention, shared with make-env-logo.py so the sign-in logo and the
masthead pill cannot drift apart. The extension is JavaScript and cannot import
it. Hand-copying two hex values into the extension would recreate, for colours,
precisely the duplicated-source problem #87 removed for hostnames. So the values
are generated instead, and CI fails the build if the committed file drifts.

Re-run this only when the colour convention changes or an environment is added
-- not when a cluster is rebuilt.

Deliberately dependency-free: no Pillow, no PyYAML. A clone should be able to
regenerate this without a pip install.
"""
import json
import pathlib

from env_colors import COLORS, UNKNOWN_COLOR

REPO = pathlib.Path(__file__).resolve().parent.parent
OUT = REPO / "utilities" / "aap-env-badge" / "colors.json"


def main() -> None:
    environments = {
        env: {"fill": fill, "text": text} for env, (fill, text) in COLORS.items()
    }

    unknown_fill, unknown_text = UNKNOWN_COLOR
    config = {
        "_generated_by": "utilities/make-env-badge-config.py — do not edit by hand",
        # Keyed by the value of `target_env` on the job templates, which is
        # aap_env_name — the same string as the group_vars/<env>/ directory.
        "environments": environments,
        "unknown": {
            "label": "UNRECOGNIZED ENV",
            "fill": unknown_fill,
            "text": unknown_text,
        },
    }

    OUT.parent.mkdir(parents=True, exist_ok=True)
    # ensure_ascii=False so the committed file reads as text rather than \u
    # escapes — it is reviewed in diffs, not just parsed.
    OUT.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n")
    print(f"wrote {OUT.relative_to(REPO)}")
    for env, meta in environments.items():
        print(f"  {env:<8} {meta['fill']}")


if __name__ == "__main__":
    main()
