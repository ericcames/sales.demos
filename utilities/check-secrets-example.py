#!/usr/bin/env python3
# ===========================================================================
# check-secrets-example.py — secrets.yml.example is a CONTRACT, so verify it.
#
# The real playbooks/group_vars/all/secrets.yml is vault-encrypted, so CI can
# never read it and no check can diff the two. What CI *can* do is compare the
# example against the thing that actually matters: the set of variables the
# code reads and nothing in the repo defines. Those can only come from the
# vault (or an explicit extra_var), so every one of them must be declared in
# the example or a new user cannot build a working secrets file.
#
# THIS CHECK EXISTS BECAUSE THE EXAMPLE HAD ALREADY DRIFTED. (#128)
# playbooks/roles/linux_register asserts rhsm_org_id and rhsm_activation_key.
# Neither was in the example. A secrets file built from it passed every
# preflight in every skill and then failed Phase 4 on guest registration —
# the one failure mode that only shows up in front of an audience. Nothing
# caught it because nothing was looking.
#
# HOW A "VAULT KEY" IS IDENTIFIED. Three filters, in order:
#
#   1. Referenced inside {{ }} or {% %} somewhere under playbooks/ or
#      inventory/.
#   2. Not defined anywhere in those trees — not a group_var, not a role
#      default, not a set_fact, not a register, not a Jinja loop or set local.
#   3. Referenced at least once BARE, i.e. in an expression with no
#      `| default(...)`. This is the discriminator that separates a required
#      credential from an optional override: `tf_state_namespace` is always
#      written `| default('sales-demos-tfstate')` and needs no vault entry,
#      whereas `{{ rhsm_org_id }}` at linux_register/tasks/main.yml:53 is bare
#      and will fail the play outright if the vault does not carry it.
#
# Filter 3 is why the assert in linux_register is written the way it is. It
# uses `| default('')` to produce a readable message, but the role also uses
# the value bare further down, and that bare use is what makes it visible here.
#
# WHAT THIS DOES NOT DO. It does not check values, does not decrypt anything,
# and needs no vault password — so it runs in CI exactly as it runs on a
# laptop.
# ===========================================================================
import re
import subprocess
import sys
from pathlib import Path

import yaml

EXAMPLE = Path("playbooks/group_vars/all/secrets.yml.example")

# Keys declared in the example that nothing reads YET. Staged for planned work,
# so they are kept rather than deleted (the repo is additive-only), but they are
# named here so that *adding* an orphan is a deliberate act and not an accident.
# Delete an entry from this list the moment the code starts consuming the key.
STAGED = {
    "windows_admin_password": "#193 — terraform/ocpvirt has no Windows password var yet",
}

# Structural Jinja that survives the extractor and is not a variable. Keep this
# list SHORT and justified: every entry is a hole in filter 2, so an unexplained
# addition is how a real missing key would get silenced.
NOT_A_VAULT_KEY = {
    "target_env": (
        "supplied per run, never stored: `-e target_env=<env>` on the CLI and an "
        "extra_var on every job template. playbooks/tasks/assert_target_environment.yml "
        "exists precisely because it is external and must be checked against --limit."
    ),
}

JINJA = re.compile(r"\{\{(.*?)\}\}|\{%(.*?)%\}", re.S)
COMMENT = re.compile(r"^[ \t]*#.*$", re.M)
STRLIT = re.compile(r"'[^']*'|\"[^\"]*\"")
WORD = re.compile(r"[A-Za-z_]\w*")

# Jinja statement keywords, tests, and the builtin filters/functions. None of
# these are variables even though they parse as identifiers.
KEYWORDS = set(
    """for endfor if endif elif else set raw endraw macro endmacro call endcall block endblock
    with endwith do break continue filter endfilter is not and or in none true false True False
    None namespace loop self""".split()
)
BUILTINS = set(
    """default bool int float string list join map select reject selectattr rejectattr attribute
    trim upper lower replace regex_replace regex_search regex_findall to_nice_yaml to_nice_json
    to_json from_json to_yaml from_yaml first last unique sort combine ternary items2dict dict2items
    difference union intersect flatten batch min max sum round abs urlsplit urlencode basename dirname splitext
    path_join expanduser quote split splitlines b64encode b64decode hash checksum password_hash
    strftime to_datetime human_readable human_to_bytes json_query mandatory type_debug comment indent
    truncate wordwrap capitalize title center format count reverse defined undefined equalto match
    search version subelements product zip lookup query range enumerate length dict vars item
    mapping sequence iterable callable sameas escaped divisibleby even odd upper lower""".split()
)
GLOBALS = set(
    """hostvars inventory_hostname inventory_hostname_short groups group_names inventory_dir
    playbook_dir role_path role_name now omit lipsum cycler environment""".split()
)


def tracked_yaml() -> list[Path]:
    out = subprocess.run(
        ["git", "ls-files", "playbooks", "inventory"], capture_output=True, text=True, check=True
    ).stdout.split()
    return [
        Path(f)
        for f in out
        if f.endswith((".yml", ".yaml")) and "secrets.yml" not in f
    ]


def identifiers(expr: str) -> list[str]:
    """Bare identifiers only: skip `.attr` access and `func(` calls.

    Both exclusions matter. Without the attribute skip, `{{ result.stdout }}`
    contributes `stdout`; without the call skip, `now(utc=True)` contributes
    `now`. Boundaries are checked on the matched span rather than with a
    lookahead, because a lookahead lets the regex backtrack and match a
    truncated prefix — `lookup(` yielding `looku`.
    """
    out = []
    for m in WORD.finditer(expr):
        start, end = m.start(), m.end()
        if start and expr[start - 1] == ".":
            continue
        # `foo(` is a call; `foo=` is a keyword argument, as in now(utc=True)
        # and namespace(total=0). Neither is a variable reference. `==` is a
        # comparison, so only a single `=` counts.
        rest = expr[end:]
        if rest[:1] == "(":
            continue
        stripped = rest.lstrip(" ")
        if stripped[:1] == "=" and stripped[1:2] != "=":
            continue
        out.append(m.group())
    return out


def scan(files: list[Path]) -> tuple[set[str], set[str]]:
    """Return (hard, defined): bare-referenced names, and names defined anywhere."""
    hard: set[str] = set()
    jinja_locals: set[str] = set()
    defined: set[str] = set()

    def collect_var_blocks(node) -> None:
        """Add names from real definition sites only.

        NOT every YAML key: `rhsm_org_id` appears as a key under a credential's
        `inputs:` in controller_credentials.yml, and treating that as a
        definition made the checker believe the variable was defined and its
        example declaration an orphan. A key only defines a variable when it is
        the top level of a vars file, or sits under `vars:` / `set_fact:`.
        """
        if isinstance(node, dict):
            for k, v in node.items():
                # Match the FQCN too: this repo writes ansible.builtin.set_fact,
                # and keying on the bare name silently misses every fact it sets.
                if isinstance(k, str) and k.split(".")[-1] in ("vars", "set_fact") and isinstance(v, dict):
                    defined.update(x for x in v if isinstance(x, str))
                collect_var_blocks(v)
        elif isinstance(node, list):
            for i in node:
                collect_var_blocks(i)

    for path in files:
        text = path.read_text(errors="replace")
        # Strip whole-line comments FIRST. This repo's headers explain Jinja in
        # prose, and `{{` inside a comment opens a match that runs to the next
        # `}}` several lines later, swallowing every English word between them
        # as a "variable". Only full-line comments are removed: a `#` inside a
        # quoted value is not a comment, and trailing comments are rare enough
        # not to be worth the parsing risk.
        code = COMMENT.sub("", text)

        for a, b in JINJA.findall(code):
            expr = a or b
            jinja_locals |= set(re.findall(r"\bset\s+(\w+)", expr))
            for loop in re.finditer(r"\bfor\s+([\w,\s]+?)\s+in\b", expr):
                jinja_locals |= {w.strip() for w in loop.group(1).split(",")}
            clean = STRLIT.sub(" ", expr)
            if "default" in clean:
                continue  # guarded: an optional override, not a required secret
            hard.update(
                n for n in identifiers(clean) if n not in KEYWORDS and n not in BUILTINS
            )

        # Top-level keys of a vars file ARE definitions: group_vars, and a role's
        # defaults/ or vars/. Anywhere else, only vars:/set_fact: blocks count.
        is_vars_file = (
            "group_vars/" in path.as_posix()
            or "/defaults/" in path.as_posix()
            or "/vars/" in path.as_posix()
        )
        try:
            for doc in yaml.safe_load_all(text):
                if is_vars_file and isinstance(doc, dict):
                    defined.update(k for k in doc if isinstance(k, str))
                collect_var_blocks(doc)
        except yaml.YAMLError:
            pass  # vaulted or templated files that are not plain YAML
        defined |= set(re.findall(r"^\s*register:\s*(\w+)", text, re.M))
        defined |= set(re.findall(r"^\s*loop_var:\s*(\w+)", text, re.M))

    return hard - jinja_locals, defined


def main() -> int:
    if not EXAMPLE.is_file():
        print(f"::error::{EXAMPLE} is missing — it is the only contract a new user has")
        return 1

    declared_doc = yaml.safe_load(EXAMPLE.read_text()) or {}
    declared = set(declared_doc)

    hard, defined = scan(tracked_yaml())
    required = {
        n
        for n in hard - defined - GLOBALS - set(NOT_A_VAULT_KEY)
        if not n.startswith("ansible_")
    }

    fail = False

    # --- Direction 1: consumed but not declared. This is the rhsm_* bug. ------
    missing = sorted(required - declared)
    if missing:
        fail = True
        print("::error::secrets.yml.example is missing keys the code reads")
        for name in missing:
            print(f"    {name}")
        print("    Each is referenced bare and defined nowhere, so it can only come")
        print(f"    from the vault. Declare it in {EXAMPLE} with a CHANGEME value.")

    # --- Direction 2: declared but consumed nowhere. -------------------------
    orphans = sorted(declared - required - set(STAGED))
    if orphans:
        fail = True
        print("::error::secrets.yml.example declares keys nothing reads")
        for name in orphans:
            print(f"    {name}")
        print("    Either wire it up, delete it, or add it to STAGED in this script")
        print("    with the reason it is being kept.")

    # --- env_secrets: both environments must carry the same keys. ------------
    # Adding a credential to sandbox and forgetting demo produces a file that
    # works right up until someone runs against the environment customers see.
    envs = declared_doc.get("env_secrets")
    if isinstance(envs, dict) and len(envs) > 1:
        shapes = {name: set(vals or {}) for name, vals in envs.items()}
        union = set().union(*shapes.values())
        for name, keys in shapes.items():
            gap = sorted(union - keys)
            if gap:
                fail = True
                print(f"::error::env_secrets.{name} is missing: {', '.join(gap)}")
                print("    Every environment must declare the same credential keys.")

    if fail:
        print()
        print("See CLAUDE.md -> 'Secrets: exactly one mechanism'.")
        return 1

    kept = ", ".join(sorted(STAGED)) or "none"
    print(
        f"secrets.yml.example matches what the code reads "
        f"({len(required)} required keys; staged and not yet consumed: {kept})."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
