#!/bin/sh
set -e
root=$(git rev-parse --show-toplevel)
[ -x "$root/scripts/repogps/waypoint-index.sh" ] || exit 0
"$root/scripts/repogps/waypoint-index.sh" "$root"
git add "$root/docs/WAYPOINTS.md"
