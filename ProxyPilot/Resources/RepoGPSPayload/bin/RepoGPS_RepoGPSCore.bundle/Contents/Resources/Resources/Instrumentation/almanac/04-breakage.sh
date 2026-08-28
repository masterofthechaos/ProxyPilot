#!/bin/sh
# Repo Forensics 101 · Unit 04 — Breakage proxy
# For each release: fix/revert/hotfix-typed commits landing within the window
# after it, and the latency to the first one. THIS IS A PROXY — it measures
# what the commit subjects admit, not what production experienced. A release
# followed by silent suffering scores clean; an honestly-labeled hotfix chain
# scores dirty. The honesty of the metric is downstream of commit discipline.
# Config: ALMANAC_FIX_PATTERN (ERE, default '^(fix|hotfix|revert)'),
#         ALMANAC_FIX_WINDOW_DAYS (default 14). Set them in the analyzed repo's
#         scripts/almanac/config.sh — the commit gate runs with a bare
#         environment, so only a committed file survives it. Env still wins.
# Usage: 04-breakage.sh [repo-path]
set -e
# Pin the C locale — awk's printf decimal separator, sort collation, and
# tolower() are all locale-sensitive. See almanac.sh for the full rationale.
export LC_ALL=C
cd "${1:-.}"
git rev-parse HEAD >/dev/null 2>&1 || { echo "_No commits yet._"; exit 0; }

# Config comes from the repo being ANALYZED, not from wherever this script lives:
# the canonical copy is run against other repos, so `dirname $0` would read the
# wrong repo's settings — or none at all.
_cfg="$(git rev-parse --show-toplevel)/scripts/almanac/config.sh"
if [ -r "$_cfg" ]; then . "$_cfg"; fi

pattern="${ALMANAC_FIX_PATTERN:-^(fix|hotfix|revert)}"
window="${ALMANAC_FIX_WINDOW_DAYS:-14}"

echo "## Breakage proxy (per release)"
echo
# Order tags by the date of the COMMIT each points at, not by tag-creation time —
# see 03-eras.sh for the full rationale. A repo that tags retroactively in a batch
# gives every tag the same creatordate, and the resulting order is not topological.
# LC_ALL=C is load-bearing — see 03-eras.sh: without it, tags sharing a timestamp
# are ordered by the ambient locale's collation and the output stops being
# machine-independent.
tags=$(git for-each-ref --format='%(*committerdate:unix)%(committerdate:unix)	%(refname:short)' refs/tags \
       | LC_ALL=C sort -n | cut -f2)
if [ -z "$tags" ]; then
  echo "_No tags — nothing released, nothing measurably broken._"
  exit 0
fi
echo "Fix-typed commits (\`$pattern\`, case-insensitive) landing within $window days after each tag, inside that tag's window. Proxy metric: measures admitted fixes, not actual breakage."
echo
echo "| Release | Tagged | Fixes in window | First fix after |"
echo "|---------|--------|----------------:|----------------:|"

# tags plus HEAD sentinel as the final boundary
boundaries=$(printf '%s\nHEAD' "$tags")
prev=""
for t in $boundaries; do
  if [ -n "$prev" ]; then
    tag_date=$(git log -1 --format=%cs "$prev")
    # Only measure a window whose endpoints are actually in ancestry order;
    # otherwise `prev..t` is a cross-branch set, and counting fixes in it would
    # attribute another line's commits to this release. Decline the row instead.
    if ! git merge-base --is-ancestor "$prev" "$t" 2>/dev/null; then
      echo "| $prev | $tag_date | — | — |"
      prev=$t
      continue
    fi
    tag_epoch=$(git log -1 --format=%ct "$prev")
    git log --reverse --format='%ct%x09%s' "$prev".."$t" \
      | awk -F'\t' -v te="$tag_epoch" -v w="$window" -v p="$pattern" \
            -v tag="$prev" -v td="$tag_date" '
        BEGIN { IGNORECASE = 1 }  # gawk only; harmless elsewhere, tolower() below is the real guard
        tolower($2) ~ p && $1 <= te + w * 86400 {
          n++
          if (first == 0) first = $1
        }
        END {
          if (first > 0) {
            hrs = (first - te) / 3600
            if (hrs < 0) hrs = 0
            printf "| %s | %s | %d | %.1f h |\n", tag, td, n, hrs
          } else {
            printf "| %s | %s | 0 | — |\n", tag, td
          }
        }'
  fi
  prev=$t
done
