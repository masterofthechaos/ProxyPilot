#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

source scripts/release_channel.sh

CHANNEL="$(pp_require_release_channel "${1:-stable}")"
zsh scripts/build_release.sh "$CHANNEL" >/dev/null

DERIVED_DATA="$(pp_derived_data_path "${CHANNEL}")"
CONFIGURATION="$(pp_release_configuration "${CHANNEL}")"
APP_WRAPPER_NAME="$(pp_app_wrapper_name "${CHANNEL}")"
APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_WRAPPER_NAME"
DEST="$(pp_install_path "${CHANNEL}")"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing build output: $APP_PATH" 1>&2
  exit 1
fi

echo "Installing to $DEST ..."
ditto "$APP_PATH" "$DEST"
echo "Installed: $DEST"
