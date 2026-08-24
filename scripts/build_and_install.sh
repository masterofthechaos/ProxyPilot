#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

source scripts/release_channel.sh

CHANNEL="$(pp_require_release_channel "${1:-stable}")"
DERIVED_DATA="$(pp_derived_data_path "${CHANNEL}")"
mkdir -p "$(dirname "$DERIVED_DATA")"
CONFIGURATION="$(pp_release_configuration "${CHANNEL}")"
APP_WRAPPER_NAME="$(pp_app_wrapper_name "${CHANNEL}")"
APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_WRAPPER_NAME"
DEST="$(pp_install_path "${CHANNEL}")"

# 1. Regenerate Xcode project (picks up new/removed files)
echo "Regenerating Xcode project..."
zsh scripts/update_xcodeproj.sh

# 2. Build Release
echo "Building ${CHANNEL} Release..."
xcodebuild \
  -project ProxyPilot.xcodeproj \
  -scheme ProxyPilot-macOS \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  build \
  2>&1 | tail -1

if [[ ! -d "$APP_PATH" ]]; then
  echo "ERROR: Missing build output: $APP_PATH" >&2
  exit 1
fi

# 3. Read version from built app
NEW_VER=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
NEW_BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP_PATH/Contents/Info.plist")
EXECUTABLE_NAME=$(/usr/libexec/PlistBuddy -c "Print CFBundleExecutable" "$APP_PATH/Contents/Info.plist")

# 4. Quit running instance if present
if pgrep -xq "$EXECUTABLE_NAME"; then
  echo "Stopping running $EXECUTABLE_NAME..."
  killall "$EXECUTABLE_NAME" 2>/dev/null || true
  sleep 1
fi

# 5. Install to /Applications
echo "Installing to $DEST ..."
rm -rf "$DEST"
ditto "$APP_PATH" "$DEST"

echo "Installed $(pp_app_display_name "${CHANNEL}") v${NEW_VER} (build ${NEW_BUILD}) to $DEST"
