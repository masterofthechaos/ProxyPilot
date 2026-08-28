#!/bin/sh
# Repo Forensics 101 · Unit 01 — Genesis
# The founding arithmetic: first commit, age, totals. Everything Observed.
# Usage: 01-genesis.sh [repo-path]
set -e
# Pin the C locale — awk's printf decimal separator, sort collation, and
# tolower() are all locale-sensitive. See almanac.sh for the full rationale.
export LC_ALL=C
cd "${1:-.}"
git rev-parse HEAD >/dev/null 2>&1 || { echo "_No commits yet — no genesis to report._"; exit 0; }

first=$(git rev-list --max-parents=0 --reverse HEAD | head -1)
first_short=$(git rev-parse --short "$first")
first_date=$(git show -s --format=%cs "$first")
first_subj=$(git show -s --format=%s "$first")
first_author=$(git show -s --format=%an "$first")
first_epoch=$(git show -s --format=%ct "$first")
head_epoch=$(git log -1 --format=%ct)
total=$(git rev-list --count HEAD)
roots=$(git rev-list --max-parents=0 HEAD | wc -l | tr -d ' ')

echo "## Genesis"
echo
awk -v fe="$first_epoch" -v he="$head_epoch" -v t="$total" \
    -v h="$first_short" -v d="$first_date" -v s="$first_subj" -v a="$first_author" -v r="$roots" 'BEGIN {
  days = int((he - fe) / 86400) + 1
  printf "- **First commit:** `%s` — \"%s\" (%s, %s)\n", h, s, d, a
  if (r > 1) printf "- **Root commits:** %d (grafted or merged histories)\n", r
  printf "- **History span:** %d days, %d commits (%.2f commits/day)\n", days, t, t / days
}'
