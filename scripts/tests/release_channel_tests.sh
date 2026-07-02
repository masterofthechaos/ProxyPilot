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

if pp_require_release_channel beta >/dev/null 2>&1; then
  echo "Expected invalid release channel to fail" >&2
  exit 1
fi

echo "release_channel_tests.sh: PASS"
