#!/usr/bin/env python3
"""Regenerate the three hub/*-requirements.yml lists Private Automation Hub syncs. Issue #68.

    python3 utilities/refresh-hub-requirements.py
    python3 utilities/refresh-hub-requirements.py --check        # writes nothing
    python3 utilities/refresh-hub-requirements.py --audit-pins   # no network either

Writes, all committed:

    hub/certified-requirements.yml    214 collections, 3 newest versions each
    hub/validated-requirements.yml     47 collections, 3 newest versions each
    hub/community-requirements.yml     15 collections, current version only

Measured 2026-08-11: ~25 seconds for all three.

WHY THIS EXISTS AT ALL: PULP HAS NO "KEEP N VERSIONS" CONTROL. A collection
remote whose requirements entry is a bare `namespace.name` syncs EVERY published
version, and some certified collections have 40+. That is where the sync time
and the disk go.

`retain_repo_versions` is not the answer and must not be mistaken for it — it
prunes repository SNAPSHOTS, not collection versions. Every version ever synced
still lives in the current snapshot.

The mechanism that works is a version floor per collection, computed here:

    - name: kubernetes.core
      version: ">=6.2.0"        # 6.2.0, 6.3.0, 6.4.0 — the 3 newest

`>=` ONLY EVER WIDENS, and that is a real limitation rather than a bug. Re-running
this raises the floor so future syncs pull less, but versions already synced stay
in the repository until orphan cleanup. The window caps what ARRIVES, not what is
already there.

WHY A SCRIPT AND NOT A PLAYBOOK. It writes into the repo checkout, so it is
laptop-only by nature and must never run from AAP — the same reasoning that keeps
utilities/build-ee.sh out of a job template. It is also ~260 HTTP calls, which as
sequential `ansible.builtin.uri` tasks would take minutes and produce output
nobody can read. Here they are concurrent and quiet.

--audit-pins ANSWERS A QUESTION #69 DEPENDS ON, offline: would every collection
in collections/requirements.yml actually resolve from the hub? A collection
pinned BELOW its window floor is simply not there. Two are, today
(ansible.controller and ansible.platform), which breaks nothing while no
organization has a Galaxy credential — and would break every project sync the
day one does.

DO NOT CONFUSE THE OUTPUT WITH collections/requirements.yml. That file is what
your laptop and the execution environment INSTALL. These are what PAH SYNCS from
upstream. Different direction, different lifecycle, different file.

THE TOKEN. Certified and validated need the Red Hat offline token, read from
~/.ansible.cfg [galaxy_server.rh_certified]. That is an SSO REFRESH token tied to
your subscription entitlement: it is exchanged here for a short-lived access
token, and neither is ever written to disk or printed. Community needs no
credential at all — reading public Galaxy is anonymous.

If the token is missing or expired the certified and validated lists are left
untouched rather than emptied, and the script says so and exits non-zero. An
expired token authenticates fine and then returns nothing, so "wrote an empty
list" is a failure mode worth designing out.

Deliberately dependency-free: urllib and concurrent.futures from the standard
library. A clone must be able to regenerate these without a pip install.
"""
from __future__ import annotations

import argparse
import configparser
import json
import os
import pathlib
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

REPO = pathlib.Path(__file__).resolve().parent.parent
HUB = REPO / "hub"

ANSIBLE_CFG = pathlib.Path(os.path.expanduser("~/.ansible.cfg"))
TOKEN_SECTION = "galaxy_server.rh_certified"

SSO_URL = "https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token"
CONSOLE = "https://console.redhat.com/api/automation-hub"
GALAXY = "https://galaxy.ansible.com"

# Console serves certified content from the `published` repository and validated
# content from `validated`. The names differ from the PAH-side repository names
# (`rh-certified` / `validated`), which is a genuine trap — see
# inventory/group_vars/aap/hub_collection_remotes.yml.
SOURCES = {
    "certified": {"host": CONSOLE, "repo": "published", "auth": True},
    "validated": {"host": CONSOLE, "repo": "validated", "auth": True},
    "community": {"host": GALAXY + "/api", "repo": "published", "auth": False},
}

TIMEOUT = 60
WORKERS = 8


# ---------------------------------------------------------------------------
# Version ordering
# ---------------------------------------------------------------------------
def version_key(version: str) -> tuple:
    """Sort key for a collection version. Numeric, not lexical.

    String ordering puts 1.9.0 above 1.10.0, which would silently pick the wrong
    floor and quietly exclude the newest release — the exact bug this whole file
    exists to avoid. Verified by the --check run in the skill.
    """
    core = version.split("+", 1)[0].split("-", 1)[0]
    parts = []
    for chunk in core.split("."):
        try:
            parts.append(int(chunk))
        except ValueError:
            # Unparseable segment: sort it below any numeric one rather than
            # raising. Galaxy does not enforce semver as strictly as it claims.
            parts.append(-1)
    return tuple(parts)


def is_prerelease(version: str) -> bool:
    """Pre-release versions do not count toward the window.

    Pulp's version-spec matching excludes pre-releases by default, so counting
    one toward the three would silently yield a window of two real releases.
    """
    return "-" in version.split("+", 1)[0]


# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------
def get_json(url: str, token: str | None = None) -> dict:
    request = urllib.request.Request(url, headers={"Accept": "application/json"})
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
        return json.load(response)


def access_token(offline_token: str) -> str:
    """Exchange the offline (refresh) token for a short-lived access token."""
    payload = urllib.parse.urlencode(
        {
            "grant_type": "refresh_token",
            "client_id": "cloud-services",
            "refresh_token": offline_token,
        }
    ).encode()
    request = urllib.request.Request(SSO_URL, data=payload)
    with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
        return json.load(response)["access_token"]


def read_offline_token() -> str | None:
    if not ANSIBLE_CFG.is_file():
        return None
    parser = configparser.ConfigParser()
    try:
        parser.read(ANSIBLE_CFG)
    except configparser.Error:
        return None
    if TOKEN_SECTION not in parser:
        return None
    return parser[TOKEN_SECTION].get("token") or None


# ---------------------------------------------------------------------------
# Collection discovery
# ---------------------------------------------------------------------------
def index_url(source: dict, namespace: str | None = None) -> str:
    url = (
        f"{source['host']}/v3/plugin/ansible/content/{source['repo']}"
        f"/collections/index/?limit=100"
    )
    if namespace:
        url += f"&namespace={namespace}"
    return url


def next_url(current: str, page: dict) -> str | None:
    """The next page, resolved against the URL we just fetched.

    `links.next` comes back as a path anchored at the DOMAIN root
    (`/api/automation-hub/v3/...`), not relative to the API base. Joining it onto
    the base by hand produces `/api/automation-hub/api/automation-hub/...` and a
    404 on page two — which looks exactly like a permissions problem and is not.
    urljoin against the current absolute URL gets both forms right.
    """
    nxt = (page.get("links") or {}).get("next")
    if not nxt:
        return None
    return urllib.parse.urljoin(current, nxt)


def paginate(url: str, token: str | None) -> list[dict]:
    items: list[dict] = []
    while url:
        page = get_json(url, token)
        items.extend(page.get("data", []))
        url = next_url(url, page)
    return items


def list_collections(source: dict, token: str | None, namespace: str | None = None) -> list[dict]:
    """Every collection in a repository, following pagination."""
    return paginate(index_url(source, namespace), token)


def list_versions(source: dict, token: str | None, item: dict) -> list[str]:
    """Every published version of one collection.

    Uses the API's own `versions_url` rather than rebuilding the path. Console
    and Galaxy expose the same field, so one code path covers both, and it cannot
    drift if either changes its routing.
    """
    url = item.get("versions_url") or (
        f"/v3/plugin/ansible/content/{source['repo']}"
        f"/collections/index/{item['namespace']}/{item['name']}/versions/"
    )
    return [entry["version"] for entry in paginate(urllib.parse.urljoin(source["host"] + "/", url), token)]


def floor_for(versions: list[str], keep: int) -> str | None:
    """The version floor that admits exactly the `keep` newest releases."""
    releases = sorted((v for v in versions if not is_prerelease(v)), key=version_key)
    if not releases:
        return None
    if keep <= 0 or keep >= len(releases):
        return releases[0]
    return releases[-keep]


def approved_pins() -> dict[str, str]:
    """The curated set's exact versions, if it has been generated yet.

    Used to LOWER a version floor. A collection this repo has pinned below its
    own window is otherwise absent from the hub entirely, and then it cannot be
    curated into `approved` either — which is how the first real
    playbooks/curate_hub.yml run failed, on ansible.platform 2.7.20260604 sitting
    under a >=2.7.20260615 floor (#70).

    The cost is small and worth stating: lowering the floor to the pin admits 4
    versions of ansible.platform instead of 3, and 5 of ansible.controller
    instead of 3. Two extra versions across the whole hub, in exchange for the
    curated repository being seedable at all.
    """
    path = HUB / "approved-collections.yml"
    return parse_requirements(path) if path.exists() else {}


def build_entries(kind: str, keep: int, token: str | None, namespaces: list[str] | None) -> list[dict]:
    source = SOURCES[kind]
    pinned = approved_pins() if SOURCES[kind]["auth"] else {}

    if namespaces:
        collections = []
        for namespace in namespaces:
            collections.extend(list_collections(source, token, namespace))
    else:
        collections = list_collections(source, token)

    # Fast path: a window of one needs no version listing, because the index
    # already carries highest_version. That is 130 fewer HTTP calls.
    if keep == 1:
        entries = []
        for item in collections:
            highest = (item.get("highest_version") or {}).get("version")
            if highest:
                entries.append({"name": f"{item['namespace']}.{item['name']}", "version": highest})
        return sorted(entries, key=lambda e: e["name"])

    failures: list[str] = []

    def resolve(item: dict) -> dict | None:
        name = f"{item['namespace']}.{item['name']}"
        try:
            versions = list_versions(source, token, item)
        except (urllib.error.URLError, urllib.error.HTTPError) as exc:
            # Collect rather than raise. One collection failing must not abort the
            # other 213, but it must not silently shrink the list either — main()
            # refuses to write if anything landed here.
            failures.append(f"{name}: {exc}")
            return None
        found = floor_for(versions, keep)
        if not found:
            failures.append(f"{name}: no non-prerelease versions")
            return None
        # Never exclude a version this repo has pinned. See approved_pins().
        pin = pinned.get(name)
        if pin and pin in versions and version_key(pin) < version_key(found):
            found = pin
        return {"name": name, "version": f">={found}"}

    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        resolved = list(pool.map(resolve, collections))

    if failures:
        raise LookupError(
            f"{len(failures)} of {len(collections)} collections could not be resolved:\n"
            + "\n".join(f"         {f}" for f in failures[:10])
        )

    return sorted((e for e in resolved if e), key=lambda e: e["name"])


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------
HEADER = """---
# ============================================================================
# hub/{filename} — {title} (#68)
# ============================================================================
# GENERATED. Do not hand-edit; run the refresh and commit the diff:
#
#   python3 utilities/refresh-hub-requirements.py
#   git diff hub/
#
# THIS IS NOT collections/requirements.yml. That file is what your laptop and
# the execution environment INSTALL. This file is what Private Automation Hub
# SYNCS from upstream. Confusing the two is the likeliest mistake here.
#
{body}
# ============================================================================
"""

TITLES = {
    "certified": "Red Hat certified collections PAH syncs",
    "validated": "Red Hat validated collections PAH syncs",
    "community": "community collections PAH syncs",
}

BODIES = {
    "certified": (
        "# Every certified collection, windowed to the {keep} newest releases of each by a\n"
        "# `>=` floor. Consumed by the rh-certified remote in\n"
        "# inventory/group_vars/aap/hub_collection_remotes.yml.\n"
        "#\n"
        "# {count} collections."
    ),
    "validated": (
        "# Every validated collection, windowed to the {keep} newest releases of each by a\n"
        "# `>=` floor. Consumed by the validated remote in\n"
        "# inventory/group_vars/aap/hub_collection_remotes.yml.\n"
        "#\n"
        "# {count} collections."
    ),
    "community": (
        "# Pinned to one exact version each — the current release at the last refresh,\n"
        "# not a floor. This is the whole \"most current version only\" requirement: a\n"
        "# bare `namespace.name` here would sync every version ever published.\n"
        "#\n"
        "# {count} collections across the namespaces: {namespaces}."
    ),
}


def render(kind: str, entries: list[dict], keep: int, namespaces: list[str] | None) -> str:
    body = BODIES[kind].format(
        keep=keep,
        count=len(entries),
        namespaces=", ".join(namespaces) if namespaces else "-",
    )
    text = HEADER.format(
        filename=f"{kind}-requirements.yml",
        title=TITLES[kind],
        body=body,
    )
    text += "collections:\n"
    for entry in entries:
        text += f"  - name: {entry['name']}\n"
        text += f"    version: \"{entry['version']}\"\n"

    # NO TRAILING NEWLINE, AND THIS IS LOAD-BEARING RATHER THAN A STYLE CHOICE.
    #
    # ansible.hub sends this file's contents verbatim as the remote's
    # requirements_file, and Pulp stores it with the trailing newline STRIPPED.
    # On the next run the module compares what it would send against what is
    # stored, they differ by exactly that one character, and it rewrites the
    # remote. Every run. Forever.
    #
    # That is invisible until you look for it -- the sync still works, the
    # content is still correct, the run is still green. It just never reports
    # changed=0, which is precisely the claim the config-as-code demo makes.
    # Measured: three remotes, changed=3 on every re-run, until this rstrip.
    #
    # .yamllint carries a matching per-rule ignore for hub/ so the missing
    # newline does not fail the lint gate. Nothing else in the repo is exempt.
    return text.rstrip("\n")


# ---------------------------------------------------------------------------
# Pin audit
# ---------------------------------------------------------------------------
PIN_RE = re.compile(r"^\s*-\s*name:\s*(\S+)|^\s*version:\s*\"?([^\"\s]+)\"?", re.MULTILINE)


def parse_requirements(path: pathlib.Path) -> dict[str, str]:
    """name -> version, for any galaxy-style requirements file."""
    pins: dict[str, str] = {}
    name = None
    for line in path.read_text().splitlines():
        match = re.match(r"\s*-\s*name:\s*(\S+)", line)
        if match:
            name = match.group(1)
            continue
        match = re.match(r'\s*version:\s*"?([^"\s]+)"?', line)
        if match and name:
            pins[name] = match.group(1)
            name = None
    return pins


def write_approved() -> int:
    """Regenerate hub/approved-collections.yml from collections/requirements.yml.

    THE CURATED REPOSITORY IS SEEDED WITH WHAT THIS REPO ACTUALLY DEPENDS ON, and
    that is not an arbitrary starting point — it is what makes #69 safe. Point AAP
    at a repository containing exactly the collections a project sync needs and it
    resolves by construction, rather than by hoping the version window happened to
    include them.

    It also closes the gap --audit-pins reports: ansible.controller 4.8.0 and
    ansible.platform 2.7.20260604 sit BELOW the certified 3-version floor, so they
    are not in rh-certified at all. Copying an exact version into a curated
    repository does not care about the window.

    DERIVED, NOT DUPLICATED. Bump a pin in collections/requirements.yml, re-run
    this, and the curated set follows. The two are allowed to diverge later — that
    is why this is a separate file rather than the playbook reading the pins
    directly — but nothing has needed it to yet.
    """
    pins = parse_requirements(REPO / "collections" / "requirements.yml")
    if not pins:
        print("ERROR  no pins found in collections/requirements.yml", file=sys.stderr)
        return 1

    body = (
        "# The curated set: what this repo itself installs, at the exact pinned\n"
        "# version. Derived from collections/requirements.yml -- bump a pin there\n"
        "# and re-run with --write-approved.\n"
        "#\n"
        "# UNLIKE THE OTHER THREE FILES, THIS ONE IS A TRUE DESIRED STATE. Delete a\n"
        "# line and playbooks/curate_hub.yml removes that collection from the\n"
        "# repository. A sync cannot do that; a curated repository can, which is the\n"
        "# whole reason it exists (#70).\n"
        "#\n"
        f"# {len(pins)} collections, exact versions."
    )
    text = HEADER.format(
        filename="approved-collections.yml",
        title="the curated repository's desired contents",
        body=body,
    )
    text += "collections:\n"
    for name in sorted(pins):
        text += f"  - name: {name}\n"
        text += f"    version: \"{pins[name]}\"\n"
    text = text.rstrip("\n")

    path = HUB / "approved-collections.yml"
    current = path.read_text() if path.exists() else None
    if current == text:
        print(f"ok     {path.relative_to(REPO)} — {len(pins)} collections, unchanged")
        return 0
    path.write_text(text)
    print(f"wrote  {path.relative_to(REPO)} — {len(pins)} collections")
    return 0


def audit_pins() -> int:
    """Would every collection this repo pins actually resolve from the hub?

    This is gate 2 of #69, checkable without touching a cluster. A collection
    pinned BELOW its window floor is simply not in the hub, so the day AAP is
    pointed at PAH its project sync fails — and the error names a missing
    version, not a missing window, which sends you looking in the wrong place.

    Phase 1 does not point AAP at PAH, so a failure here breaks nothing today.
    It is a precondition for #69, reported early on purpose.
    """
    repo_pins = parse_requirements(REPO / "collections" / "requirements.yml")
    floors: dict[str, tuple[str, str]] = {}
    for kind in ("certified", "validated"):
        path = HUB / f"{kind}-requirements.yml"
        if path.exists():
            for name, spec in parse_requirements(path).items():
                floors[name] = (spec, kind)

    problems = 0
    for name, pin in sorted(repo_pins.items()):
        if name not in floors:
            print(f"ABSENT {name} — pinned {pin}, in neither certified nor validated")
            problems += 1
            continue
        spec, kind = floors[name]
        floor = spec.lstrip(">=")
        if version_key(pin) < version_key(floor):
            print(f"BELOW  {name} — pinned {pin}, {kind} floor is {spec}")
            problems += 1
        else:
            print(f"ok     {name} — pinned {pin}, {kind} floor {spec}")

    if problems:
        print(
            f"\n{problems} collection(s) would not resolve from PAH.\n"
            "Nothing is broken today — no organization has a Galaxy credential.\n"
            "Fix before #69 by widening the window, bumping the pin, or accepting\n"
            "the gap deliberately."
        )
    else:
        print("\nEvery pinned collection is inside its window. Gate 2 of #69 is clear.")
    return 0


# ---------------------------------------------------------------------------
def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--certified-versions", type=int, default=3, metavar="N")
    parser.add_argument("--validated-versions", type=int, default=3, metavar="N")
    parser.add_argument("--community-versions", type=int, default=1, metavar="N")
    parser.add_argument(
        "--namespaces",
        default="ericcames,mlowcher61",
        help="comma-separated Galaxy namespaces for the community list",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="report drift without writing; exit 1 if any file would change",
    )
    parser.add_argument(
        "--audit-pins",
        action="store_true",
        help="check collections/requirements.yml against the windows; no network, no writes",
    )
    parser.add_argument(
        "--write-approved",
        action="store_true",
        help="regenerate hub/approved-collections.yml from the repo's pins; no network",
    )
    args = parser.parse_args()

    if args.audit_pins:
        return audit_pins()
    if args.write_approved:
        HUB.mkdir(exist_ok=True)
        return write_approved()

    namespaces = [n.strip() for n in args.namespaces.split(",") if n.strip()]
    HUB.mkdir(exist_ok=True)

    offline = read_offline_token()
    token = None
    if offline:
        try:
            token = access_token(offline)
        except (urllib.error.URLError, urllib.error.HTTPError, KeyError) as exc:
            print(f"ERROR  could not exchange the offline token: {exc}", file=sys.stderr)
            print(
                "       Regenerate it at "
                "https://console.redhat.com/ansible/automation-hub/token "
                f"and update {TOKEN_SECTION} in {ANSIBLE_CFG}.",
                file=sys.stderr,
            )
            return 1
    else:
        print(
            f"ERROR  no offline token in {ANSIBLE_CFG} [{TOKEN_SECTION}].\n"
            "       Certified and validated cannot be refreshed without it, and\n"
            "       writing them empty would silently shrink the hub. Nothing written.",
            file=sys.stderr,
        )
        return 1

    plan = [
        ("certified", args.certified_versions, None),
        ("validated", args.validated_versions, None),
        ("community", args.community_versions, namespaces),
    ]

    drift = False
    for kind, keep, scope in plan:
        use_token = token if SOURCES[kind]["auth"] else None
        try:
            entries = build_entries(kind, keep, use_token, scope)
        except (urllib.error.URLError, urllib.error.HTTPError, LookupError) as exc:
            print(f"ERROR  {kind}: {exc}\n       Nothing written for it.", file=sys.stderr)
            return 1

        if not entries:
            print(
                f"ERROR  {kind}: upstream returned no collections. This is what an\n"
                "       expired token looks like — it authenticates, then returns\n"
                "       nothing. Refusing to write an empty list.",
                file=sys.stderr,
            )
            return 1

        text = render(kind, entries, keep, scope)
        path = HUB / f"{kind}-requirements.yml"
        current = path.read_text() if path.exists() else None

        if current == text:
            print(f"ok     {path.relative_to(REPO)} — {len(entries)} collections, unchanged")
            continue

        drift = True
        if args.check:
            print(f"DRIFT  {path.relative_to(REPO)} would change")
        else:
            path.write_text(text)
            print(f"wrote  {path.relative_to(REPO)} — {len(entries)} collections")

    if args.check:
        if drift:
            print("\nRun without --check, then review and commit the diff.")
            return 1
        print("\nNo drift.")
        return 0

    if drift:
        print("\nReview and commit:\n    git diff hub/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
