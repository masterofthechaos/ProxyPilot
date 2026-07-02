#!/usr/bin/env bash

pp_require_release_channel() {
  local channel="${1:-stable}"
  case "${channel}" in
    stable|alpha)
      printf '%s\n' "${channel}"
      ;;
    *)
      echo "Error: invalid release channel '${channel}'. Expected 'stable' or 'alpha'." >&2
      return 1
      ;;
  esac
}

pp_release_configuration() {
  case "$(pp_require_release_channel "${1}")" in
    stable) printf 'Release\n' ;;
    alpha) printf 'Release-Alpha\n' ;;
  esac
}

pp_app_wrapper_name() {
  case "$(pp_require_release_channel "${1}")" in
    stable) printf 'ProxyPilot.app\n' ;;
    alpha) printf 'ProxyPilot-alpha.app\n' ;;
  esac
}

pp_executable_name() {
  case "$(pp_require_release_channel "${1}")" in
    stable) printf 'ProxyPilot\n' ;;
    alpha) printf 'ProxyPilot-alpha\n' ;;
  esac
}

pp_app_display_name() {
  case "$(pp_require_release_channel "${1}")" in
    stable) printf 'ProxyPilot\n' ;;
    alpha) printf 'ProxyPilot Alpha\n' ;;
  esac
}

pp_install_path() {
  printf '/Applications/%s\n' "$(pp_app_wrapper_name "${1}")"
}

pp_dmg_name() {
  local channel
  local version
  local build

  channel="$(pp_require_release_channel "${1}")"
  version="${2}"
  build="${3}"

  case "${channel}" in
    stable) printf 'ProxyPilot-v%s.dmg\n' "${version}" ;;
    alpha) printf 'ProxyPilot-alpha-v%s+%s.dmg\n' "${version}" "${build}" ;;
  esac
}
