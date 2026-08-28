#!/bin/sh
# Repo Forensics 101 · Unit 02 — Cadence
# The heartbeat: busiest days, streaks, silences. Day boundaries are UTC
# (epoch/86400) so the numbers are reproducible on any machine in any TZ.
# Usage: 02-cadence.sh [repo-path]
set -e
# Pin the C locale — awk's printf decimal separator, sort collation, and
# tolower() are all locale-sensitive. See almanac.sh for the full rationale.
export LC_ALL=C
cd "${1:-.}"
git rev-parse HEAD >/dev/null 2>&1 || { echo "_No commits yet._"; exit 0; }

echo "## Cadence"
echo
echo "### Busiest days (top 10)"
echo
echo "| Commits | Date |"
echo "|--------:|------|"
# Truncate in awk, not with `head`: `sort | head` makes sort die on SIGPIPE, and
# BSD sort prints "sort: Broken pipe" to stderr when it does. Harmless, but it
# surfaces during every commit via the gate, and a tool that prints errors while
# succeeding teaches people to ignore its errors.
git log --format=%cs | sort | uniq -c | sort -rn \
  | awk 'NR <= 10 { printf "| %s | %s |\n", $1, $2 }'
echo

git log --format='%ct %cs' | awk '
  { day = int($1 / 86400)
    if (!(day in seen)) { seen[day] = 1; dates[day] = $2; n++ } }
  END {
    # collect distinct commit-days, ascending
    m = 0
    for (d in seen) days[m++] = d + 0
    # insertion sort (portable awk has no asort)
    for (i = 1; i < m; i++) {
      v = days[i]
      for (j = i - 1; j >= 0 && days[j] > v; j--) days[j+1] = days[j]
      days[j+1] = v
    }
    streak = 1; best = 1; bs = days[0]; be = days[0]; cs = days[0]
    gap = 0; ga = days[0]; gb = days[0]
    for (i = 1; i < m; i++) {
      diff = days[i] - days[i-1]
      if (diff == 1) { streak++
        if (streak > best) { best = streak; bs = cs; be = days[i] } }
      else { streak = 1; cs = days[i] }
      if (diff > gap) { gap = diff; ga = days[i-1]; gb = days[i] }
    }
    printf "- **Days with commits:** %d\n", m
    printf "- **Longest streak:** %d consecutive days (%s to %s)\n", best, dates[bs], dates[be]
    printf "- **Longest silence:** %d days (%s to %s)\n", gap, dates[ga], dates[gb]
  }'
