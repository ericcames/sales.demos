#!/usr/bin/env python3
"""Generate the hostname -> environment map the masthead badge reads. Issue #54.

    python3 utilities/make-env-badge-config.py

Writes utilities/aap-env-badge/envs.json, which is committed so loading the
extension needs no build step.

WHY GENERATED. `aap_hostname` in inventory/group_vars/<env>/connection.yml is
the single source of truth for where an environment lives. A hand-maintained
copy in the extension would be a third place to edit on a fresh RHDP
environment, and the failure mode is silent: a stale map does not error, it just
labels the wrong cluster with the right color — the exact mistake the badge
exists to prevent.

So a new RHDP environment stays what CLAUDE.md says it is — edit connection.yml
and the vault — plus re-running the two generators:

    python3 utilities/make-env-logo.py --env sandbox
    python3 utilities/make-env-badge-config.py

Colors come from env_colors.py, shared with make-env-logo.py, so the sign-in
logo and the masthead pill cannot drift apart.

Deliberately dependency-free: no Pillow, no PyYAML. The one value it needs from
each connection.yml is a plain quoted scalar, and requiring PyYAML to read it
would mean a clone could not regenerate this without a pip install.
"""
import json
import pathlib
import re
import sys

from env_colors import COLORS, UNKNOWN_COLOR

REPO = pathlib.Path(__file__).resolve().parent.parent
GROUP_VARS = REPO / "inventory" / "group_vars"
OUT = REPO / "utilities" / "aap-env-badge" / "envs.json"

# aap_hostname: "aap-aap.apps.cluster-<id>.dyn.redhatworkshops.io"
HOSTNAME_RE = re.compile(r'^aap_hostname:\s*["\']?([^"\'\s]+)', re.MULTILINE)


def hostname_for(env: str) -> str:
    path = GROUP_VARS / env / "connection.yml"
    if not path.exists():
        sys.exit(f"missing {path}")
    match = HOSTNAME_RE.search(path.read_text())
    if not match:
        sys.exit(f"no aap_hostname found in {path}")
    return match.group(1)


def main() -> None:
    envs = {}
    for env, (fill, text) in COLORS.items():
        envs[hostname_for(env)] = {"label": env.upper(), "fill": fill, "text": text}

    unknown_fill, unknown_text = UNKNOWN_COLOR
    config = {
        "_generated_by": "utilities/make-env-badge-config.py — do not edit by hand",
        "environments": envs,
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
    for host, meta in envs.items():
        print(f"  {meta['label']:<8} {host}")


if __name__ == "__main__":
    main()
