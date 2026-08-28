#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
rgps_root=${RGPS_SOURCE_DIR:-"$repo_root/../RGPS"}
destination="$repo_root/ProxyPilot/Resources/RepoGPSPayload"

if [[ ! -f "$rgps_root/scripts/build-payload.sh" ]]; then
  echo "RepoGPS payload builder not found at $rgps_root/scripts/build-payload.sh" >&2
  exit 1
fi

bash "$rgps_root/scripts/build-payload.sh" "$destination"
echo "Staged RepoGPS payload at $destination"
