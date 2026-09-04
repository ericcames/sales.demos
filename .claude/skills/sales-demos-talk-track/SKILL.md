---
name: sales-demos-talk-track
description: "Scaffold a new use-case directory under docs/demos/ from _template/, or verify an existing one: check the five required files are present, discover renderable offline artifacts, run the renderer when applicable, visually inspect the output for broken images, and verify the 'Where the words come from' table has no empty rows and every source file exists. Laptop-only, no playbook. TRIGGER when: the user asks to create, scaffold, or start a new demo talk track or use case, verify or audit an existing talk track's structure or source table, re-render demo assets for the docs, check why a talk-track image looks wrong, or asks about the docs/demos/ conventions. SKIP: if the user is writing or editing the talk track prose itself — this skill checks structure and artifacts, not content — or if they only want to run render-demo-assets.py without the surrounding checks."
---

# sales-demos-talk-track

Scaffold or verify a use-case directory under `docs/demos/`.

Like `collections-sync`, this skill has **no playbook**, and that is deliberate.
The "skill wraps a playbook" contract in `CLAUDE.md` exists so anything touching
an environment is runnable from AAP too. This checks documentation on your
laptop; it must never run from AAP, and there is nothing for a job template to
call.

## Two modes

The skill detects the mode from whether the directory exists:

- **Scaffold** (`docs/demos/<use-case>/` does not exist) — copy `_template/`,
  replace placeholders, remind the user of run-sheet-first ordering, add a Draft
  row to the hub document.
- **Verify** (`docs/demos/<use-case>/` exists) — check structure, discover
  renderable artifacts, run the renderer if applicable, visually inspect the
  output, and validate the "Where the words come from" table.

**Do not verify immediately after scaffolding.** A freshly scaffolded directory
is deliberately all placeholders. Verify is for a use case someone has been
writing.

## Collect inputs

| Variable | Default | Meaning |
|---|---|---|
| `USE_CASE` | *(none — ask the user)* | Directory name under `docs/demos/` (e.g. `openshift-virtualization`) |

## Preflight Check

```bash
USE_CASE="${USE_CASE:?provide the use-case directory name (e.g. openshift-virtualization)}"

# 1. Template directory has the five files
for f in README.md run-sheet.md talk-track.md architecture.md objections.md; do
  test -f "docs/demos/_template/$f" \
    && echo "✅ _template/$f" \
    || echo "❌ _template/$f missing"
done

# 2. Detect mode
if [ -d "docs/demos/$USE_CASE" ]; then
  echo "✅ docs/demos/$USE_CASE/ exists — VERIFY mode"
else
  echo "ℹ️  docs/demos/$USE_CASE/ does not exist — SCAFFOLD mode"
fi

# 3. jinja2 installed (only matters if this use case has renderable artifacts)
python3 -c "import jinja2" 2>/dev/null \
  && echo "✅ jinja2" \
  || echo "⚠️  jinja2 not installed — rendering will be skipped if needed"

# 4. Chrome available (only matters for PNG rendering)
{ command -v google-chrome || command -v chromium; } >/dev/null 2>&1 \
  && echo "✅ Chrome or Chromium on PATH" \
  || echo "⚠️  no Chrome — PNG rendering will use --no-png; text artifacts still render"
```

If any check marked ❌ fails, stop and tell the user exactly which one and the
fix shown beside it. Checks marked ⚠️ are warnings — they only matter if the
use case has renderable artifacts, which is discovered later.

---

## Scaffold (directory does not exist)

```bash
cp -r docs/demos/_template "docs/demos/$USE_CASE"
```

Then:

1. Replace `[Use case]` in all five file titles with the use case's display
   name.
2. Replace `[the customer role]` in `talk-track.md` with the intended audience —
   ask the user.
3. Show the user the new directory listing.
4. Add a **Draft** row to the use case table in `docs/demos/README.md`.
5. Remind the user:

> Write `run-sheet.md` first — it forces the arc into a shape that fits the
> slot. Everything else is easier afterwards.
> ([`docs/demos/README.md`](../../docs/demos/README.md) line 85)

The "Where the words come from" table in `talk-track.md` has placeholder empty
rows. They will fail the verify step until filled in — that is the point.

**Stop here.** Do not run verify on a freshly scaffolded directory.

---

## Verify (directory exists)

Run all checks below in order.

### 1. Structure

```bash
for f in README.md run-sheet.md talk-track.md architecture.md objections.md; do
  test -f "docs/demos/$USE_CASE/$f" \
    && echo "✅ $f" \
    || echo "❌ $f missing"
done

# Extra files are allowed where earned — list without judging
echo "--- all files ---"
ls "docs/demos/$USE_CASE/"
```

Check that `docs/demos/README.md` has a row for this use case in the use case
table.

### 2. Discover renderable artifacts

Two checks:

```bash
# Rendered markers in the use case's markdown files
grep -rn '<!-- rendered:' "docs/demos/$USE_CASE/" || echo "(none)"

# Whether render-demo-assets.py handles this use case
grep -l "$USE_CASE\|linux_configure" utilities/render-demo-assets.py >/dev/null 2>&1 \
  && echo "✅ render-demo-assets.py covers this use case" \
  || echo "ℹ️  render-demo-assets.py does not cover this use case — no rendered artifacts"
```

Three possible outcomes:

- **Renderable artifacts found** (currently only `openshift-virtualization`) —
  proceed to Render and Visual Check.
- **Rendered markers found but no renderer** — the talk track embeds rendered
  blocks but nothing regenerates them. Report this so the user knows those
  blocks are maintained by hand.
- **No renderable artifacts** (currently `private-automation-hub`,
  `mcp-servers`) — skip rendering. This is expected, not a failure.

### 3. Render (when applicable)

```bash
# With Chrome — full render including PNG
python3 utilities/render-demo-assets.py

# Without Chrome — text artifacts only
python3 utilities/render-demo-assets.py --no-png
```

Do not reimplement the renderer. `utilities/render-demo-assets.py` is the
renderer; this skill runs it and checks the output.

### 4. Visual check (when a PNG was rendered)

Read `docs/images/demo-page.png` with the Read tool.

Check for:
- The three product logos (RHEL, OpenShift, Ansible) are visible — not
  broken-image boxes. This is the documented failure mode: the logos must be
  staged beside the HTML during rendering.
- The page layout renders sensibly — no overlapping text, no missing sections.

If the logos are broken boxes, the fix is in `render-demo-assets.py`, not in
this skill.

### 5. "Where the words come from" table

Parse `docs/demos/$USE_CASE/talk-track.md` for the "Where the words come from"
section. For each row in the Markdown table:

1. **No empty Claim cell.** Every row must have text in the first column.
2. **No empty Source cell.** Every row must have text in the second column (named
   "Source" or "Backed by" depending on the use case).
3. **Source file verification.** Extract tokens that look like repo-relative file
   paths. Strip trailing line-number references (`:10-14`), annotations after
   ` — `, and issue references. Check whether each extracted path exists with
   `test -f`. Report missing files.

```bash
python3 - <<'PY'
import re, os, sys

use_case = os.environ.get("USE_CASE", "")
path = f"docs/demos/{use_case}/talk-track.md"
if not os.path.isfile(path):
    print(f"❌ {path} not found"); sys.exit(1)

content = open(path).read()
m = re.search(
    r'## Where the words come from.*?\n'
    r'(\|.*\|.*\|\n)'
    r'(\|[-| :]+\|\n)'
    r'((?:\|.*\|\n)*)',
    content)
if not m:
    print("❌ no 'Where the words come from' table found"); sys.exit(1)

rows = [r for r in m.group(3).strip().split('\n') if r.strip()]
if not rows:
    print("❌ table has no data rows"); sys.exit(1)

bad = 0
for i, row in enumerate(rows, 1):
    cols = [c.strip() for c in row.split('|')[1:-1]]
    if len(cols) < 2:
        print(f"❌ row {i}: malformed"); bad += 1; continue
    if not cols[0]:
        print(f"❌ row {i}: empty claim"); bad += 1
    if not cols[1]:
        print(f"❌ row {i}: empty source"); bad += 1
    else:
        paths = re.findall(r'`([^`]+\.\w{1,4})`', cols[1])
        for p in set(paths):
            p = re.sub(r':\d+[-–]\d+$', '', p)
            if os.path.exists(p):
                print(f"  ✅ {p}")
            elif not p.startswith('http') and '/' in p:
                print(f"  ⚠️  {p} — not found (may be partial or renamed)")

if bad:
    print(f"\n❌ {bad} row(s) need attention")
else:
    print(f"\n✅ all {len(rows)} rows filled")
PY
```

Source entries are sometimes descriptions or issue references, not file paths.
The path check extracts what looks like a path and verifies it; everything else
is left alone.

---

## Summary

After all checks, report:

| Check | Result |
|---|---|
| Mode | scaffold / verify |
| Structure | ✅ / ❌ with detail |
| Renderable artifacts | found / not applicable |
| Render | ✅ / skipped |
| Visual check | ✅ / skipped |
| Source table | ✅ / ❌ with count |

A green check here means the structure and artifacts are consistent. It does not
mean the prose is ready to present.

## Gotchas

| Symptom | Cause | Fix |
|---|---|---|
| Three broken-image boxes in `demo-page.png` | Chrome rendered the HTML without the logos directory staged beside it | Re-run `render-demo-assets.py` — the staging is automatic; if it persists, check `playbooks/roles/linux_configure/files/logos/` |
| `render-demo-assets.py` errors with "jinja2 is not installed" | Missing Python dependency | `pip install --user jinja2` |
| "no 'Where the words come from' table found" | Section heading or table format changed | Check that `talk-track.md` has `## Where the words come from` followed by a Markdown pipe table |
| Source path marked missing but exists | Path in the table is abbreviated | Use the full repo-relative path in the table |
| Renderer only handles ocpvirt | `render-demo-assets.py` is hardcoded to `linux_configure` role templates | Expected for non-ocpvirt use cases; rendering is skipped, not failed |
