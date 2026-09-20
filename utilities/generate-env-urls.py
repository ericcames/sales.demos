#!/usr/bin/env python3
"""Generate env-urls.yml from connection.yml (and local.yml overrides).

Issue #426, #429, #582, #759.

Every Route hostname in this platform follows a fixed prefix plus the cluster's
*.apps domain.  The apps domain is already committed in each environment's
connection.yml as ``openshift_apps_domain``, so the URLs are deterministic —
but discovering them via MCP burns tokens every session.  This script reads
that one key from each environment and writes a gitignored YAML file that
Claude (or a human) can read directly.

By default the output includes usernames (from connection.yml) and passwords
(decrypted from the vault).  Pass ``--no-creds`` to suppress them.  The file
is gitignored, so credentials never reach the remote.

Regenerate after repointing an environment (new RHDP cluster, edge rebuild).

The file lives at the REPO ROOT, not in inventory/ (#582). Every command here
passes ``-i inventory``, and Ansible parses every file in an inventory
directory as an inventory source, so the old inventory/env-urls.yml produced
"Skipping key (portal) in group (sandbox)" warnings on every run. Writing the
new file deletes a leftover copy at the old path.

Environments that lack ``aap_hostname`` in their connection.yml (e.g. GPU)
get only OCP routes and their own credential keys (#759).

Usage:
    python3 utilities/generate-env-urls.py              # URLs + credentials
    python3 utilities/generate-env-urls.py --no-creds   # URLs only
    python3 utilities/generate-env-urls.py --check       # exits non-zero if stale
"""

from __future__ import annotations

import argparse
import os
import pathlib
import re
import subprocess
import sys
from typing import Any, Dict, List, Optional, Tuple

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
GROUP_VARS = REPO_ROOT / "inventory" / "group_vars"
OUTPUT = REPO_ROOT / "env-urls.yml"
# Pre-#582 location. Removed on write so it stops being parsed as inventory
# and a second plaintext copy of the credentials does not linger.
LEGACY_OUTPUT = REPO_ROOT / "inventory" / "env-urls.yml"

AAP_ROUTE_PREFIXES: List[Tuple[str, str]] = [
    ("aap", "aap-aap"),
]

OCP_ROUTE_PREFIXES: List[Tuple[str, str]] = [
    ("ocp_console", "console-openshift-console"),
    ("ocp_oauth", "oauth-openshift"),
]

AAP_EXTRA_ROUTE_PREFIXES: List[Tuple[str, str]] = [
    ("ao", "ao-automation-orchestrator"),
    ("portal", "rhaap-portal-aap-portal"),
]

APPS_DOMAIN_RE = re.compile(
    r'^openshift_apps_domain:\s*["\']?([^"\'#\s]+)["\']?\s*$'
)
AAP_HOSTNAME_RE = re.compile(
    r'^aap_hostname:\s*["\']?([^"\'#\s]+)["\']?\s*$'
)

USERNAME_KEYS = [
    "aap_username", "openshift_admin_username",
    "linux_admin_username", "windows_admin_username",
]
USERNAME_RES = {
    key: re.compile(rf'^{key}:\s*["\']?([^"\'#\s]+)["\']?\s*$')
    for key in USERNAME_KEYS
}

GPU_VAULT_KEYS: Dict[str, str] = {
    "gpu_admin_password": "openshift_admin_password",
    "gpu_openshift_api_token": "openshift_api_token",
}


def read_apps_domain(connection: pathlib.Path) -> str | None:
    for line in connection.read_text().splitlines():
        m = APPS_DOMAIN_RE.match(line)
        if m:
            return m.group(1)
    return None


def has_aap_hostname(env_dir: pathlib.Path) -> bool:
    for filename in ("local.yml", "connection.yml"):
        path = env_dir / filename
        if not path.is_file():
            continue
        for line in path.read_text().splitlines():
            if AAP_HOSTNAME_RE.match(line):
                return True
    return False


def read_usernames(connection: pathlib.Path) -> Dict[str, str]:
    usernames: Dict[str, str] = {}
    for line in connection.read_text().splitlines():
        for key, pattern in USERNAME_RES.items():
            m = pattern.match(line)
            if m:
                usernames[key] = m.group(1)
    return usernames


def read_vault_secrets() -> Tuple[Optional[Dict[str, Dict[str, str]]], Dict[str, Any]]:
    """Decrypt secrets.yml and return (env_secrets, full_vault_data)."""
    vault_pass = os.environ.get(
        "SALES_DEMOS_VAULT_PASS",
        str(pathlib.Path.home() / "secrets" / ".vault_pass_sales_demos"),
    )
    secrets_path = REPO_ROOT / "playbooks" / "group_vars" / "all" / "secrets.yml"

    if not secrets_path.exists():
        print(f"WARNING: {secrets_path} not found, skipping credentials", file=sys.stderr)
        return None, {}
    if not pathlib.Path(vault_pass).exists():
        print(f"WARNING: vault password file {vault_pass} not found", file=sys.stderr)
        return None, {}

    try:
        import yaml  # noqa: PLC0415
    except ImportError:
        print("WARNING: pyyaml not installed, skipping credentials", file=sys.stderr)
        return None, {}

    try:
        result = subprocess.run(
            [
                "ansible-vault", "view", str(secrets_path),
                "--vault-password-file", vault_pass,
            ],
            capture_output=True, text=True, check=True,
        )
    except FileNotFoundError:
        print("WARNING: ansible-vault not found, skipping credentials", file=sys.stderr)
        return None, {}
    except subprocess.CalledProcessError as exc:
        print(f"WARNING: ansible-vault failed: {exc.stderr.strip()}", file=sys.stderr)
        return None, {}

    try:
        data: Dict[str, Any] = yaml.safe_load(result.stdout) or {}
    except yaml.YAMLError as exc:
        print(f"WARNING: could not parse vault output: {exc}", file=sys.stderr)
        return None, {}

    return data.get("env_secrets"), data


class EnvInfo:
    __slots__ = ("domain", "has_aap")

    def __init__(self, domain: str, has_aap: bool) -> None:
        self.domain = domain
        self.has_aap = has_aap


def discover_environments() -> Dict[str, EnvInfo]:
    envs: Dict[str, EnvInfo] = {}
    for env_dir in sorted(GROUP_VARS.iterdir()):
        conn = env_dir / "connection.yml"
        if not conn.is_file():
            continue
        domain = read_apps_domain(conn)
        # local.yml is a gitignored overlay that overrides connection.yml for
        # laptop use. Ansible loads group_vars files in sorted order and
        # local.yml ('l' > 'c') wins. Mirror that here so env-urls reflects
        # the cluster the laptop is actually pointed at.
        local = env_dir / "local.yml"
        if local.is_file():
            local_domain = read_apps_domain(local)
            if local_domain:
                domain = local_domain
        if domain:
            envs[env_dir.name] = EnvInfo(domain, has_aap_hostname(env_dir))
    return envs


def _route_prefixes(info: EnvInfo) -> List[Tuple[str, str]]:
    if info.has_aap:
        return AAP_ROUTE_PREFIXES + OCP_ROUTE_PREFIXES + AAP_EXTRA_ROUTE_PREFIXES
    return OCP_ROUTE_PREFIXES


def build_yaml(
    envs: Dict[str, EnvInfo],
    *,
    with_creds: bool = False,
    usernames: Optional[Dict[str, Dict[str, str]]] = None,
    secrets: Optional[Dict[str, Dict[str, str]]] = None,
    vault_data: Optional[Dict[str, Any]] = None,
) -> str:
    regen_cmd = "python3 utilities/generate-env-urls.py"
    if not with_creds:
        regen_cmd += " --no-creds"
    lines = [
        "# Auto-generated by utilities/generate-env-urls.py. Do not commit.",
        "# Regenerate after repointing an environment:",
        f"#   {regen_cmd}",
        "---",
    ]
    for env_name, info in envs.items():
        lines.append(f"{env_name}:")
        for key, prefix in _route_prefixes(info):
            lines.append(f'  {key}: "https://{prefix}.{info.domain}/"')

        if with_creds:
            env_usernames = (usernames or {}).get(env_name, {})
            env_secrets = (secrets or {}).get(env_name, {})

            if not info.has_aap and vault_data:
                for vault_key, output_key in GPU_VAULT_KEYS.items():
                    val = vault_data.get(vault_key)
                    if val:
                        env_secrets[output_key] = val

            if env_usernames or env_secrets:
                lines.append("  credentials:")
                if "openshift_admin_username" in env_usernames:
                    lines.append(f'    openshift_admin_username: "{env_usernames["openshift_admin_username"]}"')
                if "aap_username" in env_usernames:
                    lines.append(f'    aap_username: "{env_usernames["aap_username"]}"')
                if "aap_password" in env_secrets:
                    lines.append(f'    aap_password: "{env_secrets["aap_password"]}"')
                if "openshift_api_token" in env_secrets:
                    lines.append(f'    openshift_api_token: "{env_secrets["openshift_api_token"]}"')
                if "openshift_admin_password" in env_secrets:
                    lines.append(f'    openshift_admin_password: "{env_secrets["openshift_admin_password"]}"')
                if "kubeadmin_password" in env_secrets:
                    lines.append(f'    kubeadmin_password: "{env_secrets["kubeadmin_password"]}"')
                if "linux_admin_username" in env_usernames:
                    lines.append(f'    linux_admin_username: "{env_usernames["linux_admin_username"]}"')
                if "linux_admin_password" in env_secrets:
                    lines.append(f'    linux_admin_password: "{env_secrets["linux_admin_password"]}"')
                if "windows_admin_username" in env_usernames:
                    lines.append(f'    windows_admin_username: "{env_usernames["windows_admin_username"]}"')
                if "windows_admin_password" in env_secrets:
                    lines.append(f'    windows_admin_password: "{env_secrets["windows_admin_password"]}"')

    lines.append("")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Exit non-zero if the file is missing or stale (do not write).",
    )
    parser.add_argument(
        "--no-creds",
        action="store_true",
        help="Exclude usernames and vault-decrypted passwords from the output.",
    )
    args = parser.parse_args()
    args.with_creds = not args.no_creds

    envs = discover_environments()
    if not envs:
        print("ERROR: no environments found under", GROUP_VARS, file=sys.stderr)
        raise SystemExit(1)

    # aap is the shared group, not an environment
    envs.pop("aap", None)

    usernames: Optional[Dict[str, Dict[str, str]]] = None
    secrets: Optional[Dict[str, Dict[str, str]]] = None
    vault_data: Dict[str, Any] = {}

    if args.with_creds:
        usernames = {}
        for env_name in envs:
            conn = GROUP_VARS / env_name / "connection.yml"
            if conn.is_file():
                u = read_usernames(conn)
                local = GROUP_VARS / env_name / "local.yml"
                if local.is_file():
                    u.update(read_usernames(local))
                usernames[env_name] = u
        secrets, vault_data = read_vault_secrets()

    content = build_yaml(
        envs, with_creds=args.with_creds,
        usernames=usernames, secrets=secrets, vault_data=vault_data,
    )

    if args.check:
        # --check compares URL-only output whether or not credentials were
        # included (--no-creds), because CI has no vault access.
        if not OUTPUT.exists():
            print(f"MISSING: {OUTPUT.relative_to(REPO_ROOT)}", file=sys.stderr)
            if LEGACY_OUTPUT.exists():
                print(f"  (found at the old path {LEGACY_OUTPUT.relative_to(REPO_ROOT)} — "
                      "regenerating moves it, #582)", file=sys.stderr)
            print("Run: python3 utilities/generate-env-urls.py", file=sys.stderr)
            raise SystemExit(1)
        existing = OUTPUT.read_text()
        # The file may have been generated with or without creds. For --check
        # we only verify the URL lines are present and current.
        expected_urls = build_yaml(envs)
        if not _urls_match(existing, expected_urls):
            print(f"STALE: {OUTPUT.relative_to(REPO_ROOT)}", file=sys.stderr)
            print("Run: python3 utilities/generate-env-urls.py", file=sys.stderr)
            raise SystemExit(1)
        print(f"OK: {OUTPUT.relative_to(REPO_ROOT)} is current")
        return

    OUTPUT.write_text(content)
    print(f"Wrote {OUTPUT.relative_to(REPO_ROOT)}")
    if LEGACY_OUTPUT.exists():
        LEGACY_OUTPUT.unlink()
        print(f"Removed legacy {LEGACY_OUTPUT.relative_to(REPO_ROOT)} (#582)")
    for env_name, info in envs.items():
        n_urls = len(_route_prefixes(info))
        detail = f"{n_urls} URLs"
        if args.with_creds:
            detail += " + credentials"
        print(f"  {env_name}: {detail}")


def _urls_match(existing: str, expected_urls: str) -> bool:
    """Check that every URL line in expected_urls appears in existing."""
    expected_url_lines = {
        line.strip()
        for line in expected_urls.splitlines()
        if "https://" in line
    }
    existing_lines = {line.strip() for line in existing.splitlines()}
    return expected_url_lines.issubset(existing_lines)


if __name__ == "__main__":
    main()
