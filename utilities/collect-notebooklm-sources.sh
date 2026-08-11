#!/usr/bin/env bash
# ===========================================================================
# collect-notebooklm-sources.sh -- stage repo docs for upload to NotebookLM.
#
# WHY THIS EXISTS
#     NotebookLM takes files, not repositories, and it answers only from the
#     sources it is given. That makes source selection the whole game: too few
#     and it cannot answer, too many and a 900-line changelog becomes the
#     citation for a question it has no business answering.
#
#     So the corpus is an explicit allowlist in notebooklm-sources.txt, and
#     this script is the thing that turns that list into a folder you can drag
#     into a browser. See issue #64.
#
# WHY IT RENAMES ON COPY
#     Filenames are the only handle NotebookLM shows -- in the source list and
#     in every citation. Five files called README.md from five repos are
#     indistinguishable at exactly the moment you want to know where an answer
#     came from. Each staged file is therefore prefixed with its repo and its
#     path: sales-demos--docs-demos-openshift-virtualization-talk-track.md
#
# WHAT IT REFUSES TO DO
#     It does not walk directories and it does not glob. Every file is named in
#     the manifest. A repo full of customer material cannot end up in a Google
#     product because a pattern was one character too wide.
#
#     It also greps what it staged before declaring success, using the same
#     real-value patterns as check-no-secrets.sh. That check is cheap and the
#     staged bundle is, by definition, about to leave this machine.
#
# USAGE
#     utilities/collect-notebooklm-sources.sh              # stage to build/notebooklm
#     utilities/collect-notebooklm-sources.sh --list       # show what would be staged
#     utilities/collect-notebooklm-sources.sh --out DIR    # stage somewhere else
#     utilities/collect-notebooklm-sources.sh --manifest F # use a different list
#
#     NOTEBOOKLM_REPOS_ROOT=~/git-repos   # where sibling repos live, if the
#                                         # manifest ever names any
# ===========================================================================
set -euo pipefail

repo_root=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
manifest="$repo_root/utilities/notebooklm-sources.txt"
out_dir="$repo_root/build/notebooklm"
repos_root="${NOTEBOOKLM_REPOS_ROOT:-$(dirname "$repo_root")}"
list_only=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --list)     list_only=1; shift ;;
    --out)      out_dir="${2:?--out needs a directory}"; shift 2 ;;
    --manifest) manifest="${2:?--manifest needs a file}"; shift 2 ;;
    -h|--help)  sed -n '2,40p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *)          echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -f "$manifest" ]] || { echo "no manifest at $manifest" >&2; exit 1; }

# Staging is not additive. A file dropped from the manifest must disappear from
# the output, or the next upload silently carries a source you meant to remove.
# Only ever remove the .md files this script writes -- never the directory, and
# never anything else that happens to be in it.
if [[ $list_only -eq 0 ]]; then
  mkdir -p "$out_dir"
  rm -f "$out_dir"/*.md
fi

staged=0
skipped_repos=()

while read -r repo rel; do
  # Strip comments and blank lines.
  [[ -z "${repo:-}" || "${repo:0:1}" == "#" ]] && continue
  [[ -n "${rel:-}" ]] || { echo "manifest line missing a path: $repo" >&2; exit 1; }

  if [[ "$repo" == "sales.demos" ]]; then
    src_root="$repo_root"
  else
    src_root="$repos_root/$repo"
  fi

  # A missing REPO is tolerated -- not every checkout has every sibling cloned,
  # and that should not stop the rest from staging. A missing FILE inside a repo
  # that does exist is a manifest error and must be loud.
  if [[ ! -d "$src_root" ]]; then
    [[ " ${skipped_repos[*]-} " == *" $repo "* ]] || skipped_repos+=("$repo")
    continue
  fi
  if [[ ! -f "$src_root/$rel" ]]; then
    echo "manifest names a file that does not exist: $repo/$rel" >&2
    exit 1
  fi

  # sales.demos -> sales-demos, docs/demos/README.md -> docs-demos-README.md
  flat="${repo//./-}--${rel//\//-}"

  if [[ $list_only -eq 1 ]]; then
    printf '%s\n  <- %s\n' "$flat" "$src_root/$rel"
  else
    [[ -e "$out_dir/$flat" ]] && { echo "name collision: $flat" >&2; exit 1; }
    cp "$src_root/$rel" "$out_dir/$flat"
  fi
  staged=$((staged + 1))
done < "$manifest"

for r in "${skipped_repos[@]-}"; do
  [[ -n "$r" ]] && echo "note: $r is not cloned under $repos_root -- skipped" >&2
done

if [[ $list_only -eq 1 ]]; then
  echo
  echo "$staged file(s) would be staged into $out_dir"
  exit 0
fi

# ---------------------------------------------------------------------------
# Last gate before this leaves the machine. Same real-value patterns as
# check-no-secrets.sh: they match genuine values, not the words, so docs that
# discuss tokens or use <angle-bracket> placeholders do not trip it.
# ---------------------------------------------------------------------------
if grep -rnEi 'sha256~[A-Za-z0-9_-]{20,}|BEGIN [A-Z ]*PRIVATE KEY|AKIA[0-9A-Z]{16}' \
     "$out_dir" 2>/dev/null; then
  # Wipe the staged copies rather than leaving a bundle sitting there ready to
  # be dragged into a browser. The line above names the file and the original is
  # what needs fixing; keeping the copy only creates a second chance to upload it.
  rm -f "$out_dir"/*.md
  echo >&2
  echo "REFUSING TO CONTINUE: a staged file contains something secret-shaped." >&2
  echo "Fix the source file above, then re-run. Staged copies have been removed." >&2
  exit 1
fi

echo "staged $staged file(s) into $out_dir"
echo
echo "Next: open notebooklm.google.com, create the notebook, and drag in the"
echo "contents of that directory. Sources are a SNAPSHOT -- when these docs"
echo "change materially, re-run this and re-upload."
