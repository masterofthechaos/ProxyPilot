#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

source scripts/release_channel.sh

CHANNEL="$(pp_require_release_channel "${1:-stable}")"
DERIVED_DATA="$(pp_derived_data_path "${CHANNEL}")"
mkdir -p "$(dirname "$DERIVED_DATA")"
CONFIGURATION="$(pp_release_configuration "${CHANNEL}")"
APP_WRAPPER_NAME="$(pp_app_wrapper_name "${CHANNEL}")"

echo "Building ${CHANNEL} Release to $DERIVED_DATA ..."
xcodebuild \
  -project ProxyPilot.xcodeproj \
  -scheme ProxyPilot-macOS \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  build \
  >/dev/null

APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_WRAPPER_NAME"
echo "Built: $APP_PATH"
