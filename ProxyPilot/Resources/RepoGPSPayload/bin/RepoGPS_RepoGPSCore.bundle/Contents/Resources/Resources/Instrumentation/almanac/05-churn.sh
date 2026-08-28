#!/bin/sh
# Repo Forensics 101 · Unit 05 — Churn
# Most-rewritten files, and the oldest untouched survivors still tracked.
# One pass over history; "last touched" = newest commit naming the file.
# Usage: 05-churn.sh [repo-path]
set -e
# Pin the C locale — awk's printf decimal separator, sort collation, and
# tolower() are all locale-sensitive. See almanac.sh for the full rationale.
export LC_ALL=C
cd "${1:-.}"
git rev-parse HEAD >/dev/null 2>&1 || { echo "_No commits yet._"; exit 0; }

echo "## Churn"
echo
echo "### Most-rewritten files (top 10, by commits touching)"
echo
echo "| Touches | File |"
echo "|--------:|------|"
# Truncate in awk, not with `head` — see 02-cadence.sh: `sort | head` makes sort
# die on SIGPIPE and BSD sort announces it on stderr during every gated commit.
git log --name-only --format= | grep -v '^$' | sort | uniq -c | sort -rn \
  | awk 'NR <= 10 { c = $1; $1 = ""; sub(/^ /, ""); printf "| %s | `%s` |\n", c, $0 }'
echo
echo "### Longest-untouched survivors (top 10 tracked files, oldest last-touch first)"
echo
echo "| Last touched | File |"
echo "|--------------|------|"
{
  git ls-files | sed 's/^/T\t/'
  git log --format='C%x09%cs' --name-only | awk -F'\t' '
    /^C\t/ { d = $2; next }
    NF && $0 !~ /^C\t/ { if (!($0 in seen)) { seen[$0] = 1; print "L\t" d "\t" $0 } }'
} | awk -F'\t' '
  $1 == "T" { tracked[$2] = 1 }
  $1 == "L" { last[$3] = $2 }
  END {
    for (f in tracked) if (f in last) print last[f] "\t" f
  }' | sort \
  | awk -F'\t' 'NR <= 10 { printf "| %s | `%s` |\n", $1, $2 }'
