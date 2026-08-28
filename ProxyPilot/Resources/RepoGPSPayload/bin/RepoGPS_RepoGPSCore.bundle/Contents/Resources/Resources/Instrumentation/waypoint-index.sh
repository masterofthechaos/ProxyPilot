#!/bin/sh
set -e
export LC_ALL=C
repo="${1:-.}"
repo=$(cd "$repo" && pwd)
output="$repo/docs/WAYPOINTS.md"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
{
  echo "# Waypoints"
  echo
  echo "_Deterministic index of repository Waypoint records. Generated; do not hand-edit._"
  echo
  echo "| Kind | Record |"
  echo "|---|---|"
  find "$repo/docs/waypoints" -type f -name '*.md' ! -path '*/templates/*' ! -name README.md 2>/dev/null \
    | sed "s#^$repo/docs/waypoints/##" \
    | LC_ALL=C sort \
    | while IFS= read -r item; do
        kind=$(printf '%s' "$item" | awk -F/ '{print NF > 1 ? $1 : "record"}')
        printf '| %s | `%s` |\n' "$kind" "$item"
      done
} > "$tmp"
mkdir -p "$repo/docs"
cmp -s "$tmp" "$output" 2>/dev/null || cp "$tmp" "$output"
