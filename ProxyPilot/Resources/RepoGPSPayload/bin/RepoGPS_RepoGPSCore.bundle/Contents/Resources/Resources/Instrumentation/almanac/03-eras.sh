#!/bin/sh
# Repo Forensics 101 · Unit 03 — Eras
# Tag-to-tag release windows: where the repo's chapters actually fall.
# Usage: 03-eras.sh [repo-path]
set -e
# Pin the C locale — awk's printf decimal separator, sort collation, and
# tolower() are all locale-sensitive. See almanac.sh for the full rationale.
export LC_ALL=C
cd "${1:-.}"
git rev-parse HEAD >/dev/null 2>&1 || { echo "_No commits yet._"; exit 0; }

echo "## Eras (release windows)"
echo
# Order tags by the date of the COMMIT each one points at — not by when the tag
# object was created. `git tag --sort=creatordate` looks right until a repo tags
# retroactively in a batch: every tag then shares one creation timestamp, the
# sort key collapses, and the tiebreak has nothing to do with topology. That
# yields backwards windows (v0.9.6 → v0.9.5) whose "diff" is a reverse diff.
# %(*committerdate) is the dereferenced commit's date for annotated tags and
# empty for lightweight ones; %(committerdate) is the reverse. Concatenating
# them yields exactly one value per tag, whichever kind it is.
# LC_ALL=C is load-bearing, not decoration: when two tags share a timestamp
# (duplicate tags like 0.1.0 and v0.1.0 on one commit — ProxyPilot has 23 such
# pairs) `sort -n` falls through to a full-line comparison under the ambient
# LC_COLLATE, so the order would be locale-decided. That would break the
# "any two machines produce identical bytes" guarantee, and a determinism check
# run twice on one machine cannot detect it.
tags=$(git for-each-ref --format='%(*committerdate:unix)%(committerdate:unix)	%(refname:short)' refs/tags \
       | LC_ALL=C sort -n | cut -f2)
if [ -z "$tags" ]; then
  echo "_No tags — the whole history is one unreleased era._"
  exit 0
fi

echo "| Window | Closed | Commits | Files touched | +lines | -lines |"
echo "|--------|--------|--------:|--------------:|-------:|-------:|"
# Buffer the rows so a legend can be appended only when a declined row exists —
# an unexplained line of dashes in a do-not-hand-edit page just puzzles the reader.
body=$(
prev=""
for t in $tags; do
  date=$(git log -1 --format=%cs "$t")
  if [ -z "$prev" ]; then
    range="$t"; label="(genesis) → $t"; base=$(git rev-list --max-parents=0 --reverse "$t" | head -1)
    stat=$(git diff --shortstat "$base" "$t" 2>/dev/null)
  else
    # Even ordered by commit date, two tags can be topologically unrelated —
    # parallel release branches, or a re-tag pointing backwards. Running
    # `git diff` across such a pair prints a reverse or cross-branch diff, which
    # rendered as a release row is simply false. Decline the row instead: a
    # metric may refuse to answer, but it may not answer wrongly.
    if ! git merge-base --is-ancestor "$prev" "$t" 2>/dev/null; then
      echo "| $prev → $t (not a forward window) | $date | — | — | — | — |"
      prev=$t
      continue
    fi
    range="$prev..$t"; label="$prev → $t"
    stat=$(git diff --shortstat "$prev" "$t" 2>/dev/null)
  fi
  count=$(git rev-list --count $range)
  echo "$stat" | awk -v l="$label" -v d="$date" -v c="$count" '{
    files=0; ins=0; del=0
    for (i = 1; i <= NF; i++) {
      if ($(i+1) ~ /^file/)      files = $i
      if ($(i+1) ~ /^insertion/) ins   = $i
      if ($(i+1) ~ /^deletion/)  del   = $i
    }
    printf "| %s | %s | %s | %s | %s | %s |\n", l, d, c, files, ins, del
  }'
  prev=$t
done
unreleased=$(git rev-list --count "$prev"..HEAD)
if [ "$unreleased" -gt 0 ]; then
  echo "| $prev → HEAD (unreleased) | — | $unreleased | — | — | — |"
fi
)
printf '%s\n' "$body"
case "$body" in
  *"not a forward window"*)
    echo
    echo "_A window marked **not a forward window** has endpoints that are not in ancestry"
    echo "order — usually a tag on a branch that was never merged, or a re-tag pointing"
    echo "backwards. Diffing across such a pair reports cross-branch changes as if they"
    echo "were one release's work, so the row is declined rather than guessed._"
    ;;
esac
