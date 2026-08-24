#!/bin/sh
# Fail-closed punch-card Index gate. Unlike the self-referential Almanac, the
# Index can exactly describe the proposed commit because it reads Git's index.
set -eu
[ "${PUNCHCARD_INDEX_GATE:-stage}" = "off" ] && exit 0

root=$(git rev-parse --show-toplevel)
generator="${PROXYPILOT_TRUSTED_GENERATORS:-$root/scripts}/gen-punchcard-index.mjs"
output="$root/docs/session-punch-cards/INDEX.md"
[ -f "$generator" ] || {
  echo "punch-card-index-gate: missing $generator" >&2
  exit 1
}

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
node "$generator" --repo "$root" --staged --stdout > "$tmp" || {
  echo "punch-card-index-gate: generation failed; commit stopped" >&2
  exit 1
}
[ -s "$tmp" ] && grep -q '^# Session Punch-Card Index$' "$tmp" || {
  echo "punch-card-index-gate: refusing empty or invalid generated output" >&2
  exit 1
}

cmp -s "$tmp" "$output" 2>/dev/null || cp "$tmp" "$output"
git add -- "$output"
exit 0
