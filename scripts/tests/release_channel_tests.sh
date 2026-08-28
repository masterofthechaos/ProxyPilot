#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${0}")/../.." && pwd)"
source "${ROOT_DIR}/scripts/release_channel.sh"

assert_eq() {
  local actual="$1"
  local expected="$2"

  if [[ "${actual}" != "${expected}" ]]; then
    echo "Assertion failed: expected '${expected}', got '${actual}'" >&2
    exit 1
  fi
}

assert_eq "$(pp_require_release_channel stable)" "stable"
assert_eq "$(pp_require_release_channel alpha)" "alpha"
assert_eq "$(pp_release_configuration stable)" "Release"
assert_eq "$(pp_release_configuration alpha)" "Release-Alpha"
assert_eq "$(pp_app_wrapper_name stable)" "ProxyPilot.app"
assert_eq "$(pp_app_wrapper_name alpha)" "ProxyPilot-alpha.app"
assert_eq "$(pp_executable_name stable)" "ProxyPilot"
assert_eq "$(pp_executable_name alpha)" "ProxyPilot-alpha"
assert_eq "$(pp_app_display_name stable)" "ProxyPilot"
assert_eq "$(pp_app_display_name alpha)" "ProxyPilot Alpha"
assert_eq "$(pp_install_path stable)" "/Applications/ProxyPilot.app"
assert_eq "$(pp_install_path alpha)" "/Applications/ProxyPilot-alpha.app"
assert_eq "$(pp_dmg_name stable 1.11.1 124)" "ProxyPilot-v1.11.1.dmg"
assert_eq "$(pp_dmg_name alpha 1.11.1 124)" "ProxyPilot-alpha-v1.11.1+124.dmg"

assert_file_contains() {
  local path="$1"
  local expected="$2"

  if ! grep -Fq -- "${expected}" "${path}"; then
    echo "Assertion failed: expected '${path}' to contain '${expected}'" >&2
    exit 1
  fi
}

assert_file_contains "${ROOT_DIR}/project.yml" 'if [[ "$CONFIGURATION" != "Release" && "$CONFIGURATION" != "Release-Alpha" ]]; then'
assert_file_contains "${ROOT_DIR}/project.yml" 'postBuildScripts:'
assert_file_contains "${ROOT_DIR}/project.yml" 'lipo -create "$ARM64_PRODUCTS/proxypilot" "$X86_64_PRODUCTS/proxypilot" -output "$HELPERS_DIR/proxypilot"'
assert_file_contains "${ROOT_DIR}/project.yml" 'lipo -create "$ARM64_PRODUCTS/proxypilot-agent" "$X86_64_PRODUCTS/proxypilot-agent" -output "$HELPERS_DIR/proxypilot-agent"'
assert_file_contains "${ROOT_DIR}/project.yml" 'REPOGPS_SOURCE_RELEASE="$(/usr/bin/plutil -extract source_release raw -o - "$REPOGPS_SOURCE/payload.json")"'
assert_file_contains "${ROOT_DIR}/project.yml" 'if [[ ! "$REPOGPS_SOURCE_RELEASE" =~ ^[0-9a-f]{7,40}$ ]]; then'
assert_file_contains "${ROOT_DIR}/project.yml" '--source-release "$REPOGPS_SOURCE_RELEASE"'
assert_file_contains "${ROOT_DIR}/scripts/build_and_install.sh" '--source-release "$REPOGPS_SOURCE_RELEASE"'
assert_file_contains "${ROOT_DIR}/scripts/build_and_install.sh" 'ERROR: Embedded RepoGPS manifest does not match the signed binary'
assert_file_contains "${ROOT_DIR}/scripts/build_and_install.sh" 'tail -80 "$BUILD_LOG" >&2'
assert_file_contains "${ROOT_DIR}/scripts/build_signed_dmg.sh" '--source-release "${REPOGPS_SOURCE_RELEASE}"'
assert_file_contains "${ROOT_DIR}/scripts/build_signed_dmg.sh" 'Error: Embedded RepoGPS manifest does not match the signed binary'
assert_file_contains "${ROOT_DIR}/ProxyPilotCLI/tests/smoke_test.sh" 'if [[ "$(uname -s)" == "Darwin" ]]; then'
assert_file_contains "${ROOT_DIR}/ProxyPilotCLI/tests/smoke_test.sh" 'agent status assertions skipped because Agent status is macOS-only'
assert_file_contains "${ROOT_DIR}/scripts/build_signed_dmg.sh" 'Authenticated CLI metadata (paste into proxypilot-versions.json)'
assert_file_contains "${ROOT_DIR}/scripts/build_signed_dmg.sh" 'ed_signature_cli:'

if pp_require_release_channel beta >/dev/null 2>&1; then
  echo "Expected invalid release channel to fail" >&2
  exit 1
fi

echo "release_channel_tests.sh: PASS"
