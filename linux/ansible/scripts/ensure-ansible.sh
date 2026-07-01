#!/usr/bin/env bash
#
# ensure-ansible.sh - Ensure Ansible runtime packages are installed
#
# Usage:
#   ./ensure-ansible.sh [OPTIONS]
#
# Options:
#   -d, --dry-run  Show what would be installed without making changes
#   -h, --help     Display this help message
#
# Author: Travis McDade
# License: MIT

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_NAME="$(basename "${0}")"
readonly SCRIPT_NAME
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
readonly SCRIPT_DIR
readonly LIB_DIR="${SCRIPT_DIR}/../../lib"

DRY_RUN=false
readonly REQUIRED_PACKAGES=(ansible-core python3-apt python3-yaml)

# shellcheck source=linux/lib/colors.sh
source "${LIB_DIR}/colors.sh"

# shellcheck source=linux/lib/logging.sh
source "${LIB_DIR}/logging.sh"

# shellcheck source=linux/lib/utils.sh
source "${LIB_DIR}/utils.sh"

show_usage() {
  cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Ensure Ansible runtime packages are installed for system-lifecycle.

Options:
    -d, --dry-run  Show what would be installed without making changes
    -h, --help     Display this help message
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "${1}" in
      -d|--dry-run)
        DRY_RUN=true
        shift
        ;;
      -h|--help)
        show_usage
        exit "${EXIT_SUCCESS}"
        ;;
      -*)
        log_error "Unknown option: ${1}"
        show_usage
        exit "${EXIT_INVALID_ARGS}"
        ;;
      *)
        log_error "Unexpected argument: ${1}"
        show_usage
        exit "${EXIT_INVALID_ARGS}"
        ;;
    esac
  done
}

missing_packages() {
  local package

  for package in "${REQUIRED_PACKAGES[@]}"; do
    if ! dpkg-query -W -f='${Status}' "${package}" 2>/dev/null | grep -q "^install ok installed$"; then
      printf "%s\n" "${package}"
    fi
  done
}

main() {
  parse_args "$@"

  local missing=()
  mapfile -t missing < <(missing_packages)

  if [[ ${#missing[@]} -eq 0 ]]; then
    log_success "Ansible runtime packages are installed"
    return "${EXIT_SUCCESS}"
  fi

  if [[ "${DRY_RUN}" == true ]]; then
    log_info "[DRY-RUN] Would install packages: ${missing[*]}"
    log_info "[DRY-RUN] Would run: sudo apt-get update"
    log_info "[DRY-RUN] Would run: sudo apt-get install --no-install-recommends -y ${missing[*]}"
    return "${EXIT_SUCCESS}"
  fi

  log_info "Installing Ansible runtime packages: ${missing[*]}"
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y "${missing[@]}"
}

main "$@"
