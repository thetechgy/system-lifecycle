#!/usr/bin/env bash
#
# update-system.sh - Ubuntu 24.04 LTS System Update Script
#
# Description:
#   Performs comprehensive system updates including apt packages,
#   optional npm global packages, with logging and error handling.
#
# Usage:
#   sudo ./update-system.sh [OPTIONS]
#
# Options:
#   -d, --dry-run     Show what would be done without making changes
#   -q, --quiet       Suppress non-essential output
#   -n, --no-npm      Skip npm package updates
#   -h, --help        Display this help message
#   -v, --version     Display script version
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid arguments
#   3 - Not running as root
#   4 - Apt update failed
#   5 - Apt upgrade failed
#   6 - Npm update failed
#
# Author: Travis McDade
# License: MIT
# Version: 1.0.0

set -o errexit   # Exit on error
set -o nounset   # Exit on undefined variable
set -o pipefail  # Catch pipeline failures

# -----------------------------------------------------------------------------
# Script Configuration
# -----------------------------------------------------------------------------

readonly SCRIPT_NAME="$(basename "${0}")"
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
readonly LIB_DIR="${SCRIPT_DIR}/../../lib"

# Default flags
DRY_RUN=false
QUIET=false
SKIP_NPM=false

# -----------------------------------------------------------------------------
# Source Libraries
# -----------------------------------------------------------------------------

# shellcheck source=../../lib/colors.sh
source "${LIB_DIR}/colors.sh"

# shellcheck source=../../lib/logging.sh
source "${LIB_DIR}/logging.sh"

# shellcheck source=../../lib/utils.sh
source "${LIB_DIR}/utils.sh"

# -----------------------------------------------------------------------------
# Help and Version
# -----------------------------------------------------------------------------

show_usage() {
  cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Ubuntu 24.04 LTS System Update Script

Options:
    -d, --dry-run     Show what would be done without making changes
    -q, --quiet       Suppress non-essential output
    -n, --no-npm      Skip npm package updates
    -h, --help        Display this help message
    -v, --version     Display script version

Examples:
    sudo ${SCRIPT_NAME}              # Full update
    sudo ${SCRIPT_NAME} --dry-run    # Preview changes
    sudo ${SCRIPT_NAME} --no-npm     # Skip npm updates
    sudo ${SCRIPT_NAME} -q           # Quiet mode

Exit Codes:
    0 - Success
    1 - General error
    2 - Invalid arguments
    3 - Not running as root
    4 - Apt update failed
    5 - Apt upgrade failed
    6 - Npm update failed
EOF
}

show_version() {
  printf "%s version %s\n" "${SCRIPT_NAME}" "${SCRIPT_VERSION}"
}

# -----------------------------------------------------------------------------
# Argument Parsing
# -----------------------------------------------------------------------------

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "${1}" in
      -d|--dry-run)
        DRY_RUN=true
        shift
        ;;
      -q|--quiet)
        QUIET=true
        shift
        ;;
      -n|--no-npm)
        SKIP_NPM=true
        shift
        ;;
      -h|--help)
        show_usage
        exit "${EXIT_SUCCESS}"
        ;;
      -v|--version)
        show_version
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

# -----------------------------------------------------------------------------
# Cleanup Handler
# -----------------------------------------------------------------------------

cleanup() {
  local exit_code=$?

  if [[ ${exit_code} -eq 0 ]]; then
    log_success "Update completed successfully"
  else
    log_error "Update failed with exit code ${exit_code}"
  fi

  if [[ -n "${LOG_FILE:-}" ]]; then
    log_info "Log saved to: ${LOG_FILE}"
  fi
}

trap cleanup EXIT

# -----------------------------------------------------------------------------
# APT Functions
# -----------------------------------------------------------------------------

apt_update() {
  section "Updating Package Lists"

  if [[ "${DRY_RUN}" == true ]]; then
    log_info "[DRY-RUN] Would run: apt-get update"
    return 0
  fi

  log_info "Running apt-get update..."
  if apt-get update 2>&1 | tee -a "${LOG_FILE}"; then
    log_success "Package lists updated successfully"
  else
    log_error "Failed to update package lists"
    return "${EXIT_APT_UPDATE_FAILED}"
  fi
}

apt_upgrade() {
  section "Upgrading Packages"

  if [[ "${DRY_RUN}" == true ]]; then
    log_info "[DRY-RUN] Would run: apt-get upgrade -y"
    log_info "Packages that would be upgraded:"
    apt-get upgrade --dry-run 2>&1 | tee -a "${LOG_FILE}" || true
    return 0
  fi

  log_info "Running apt-get upgrade..."
  if DEBIAN_FRONTEND=noninteractive apt-get upgrade -y 2>&1 | tee -a "${LOG_FILE}"; then
    log_success "Packages upgraded successfully"
  else
    log_error "Failed to upgrade packages"
    return "${EXIT_APT_UPGRADE_FAILED}"
  fi
}

apt_dist_upgrade() {
  section "Distribution Upgrade"

  if [[ "${DRY_RUN}" == true ]]; then
    log_info "[DRY-RUN] Would run: apt-get dist-upgrade -y"
    log_info "Packages that would be upgraded:"
    apt-get dist-upgrade --dry-run 2>&1 | tee -a "${LOG_FILE}" || true
    return 0
  fi

  log_info "Running apt-get dist-upgrade..."
  if DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y 2>&1 | tee -a "${LOG_FILE}"; then
    log_success "Distribution upgrade completed successfully"
  else
    log_error "Failed to complete distribution upgrade"
    return "${EXIT_APT_UPGRADE_FAILED}"
  fi
}

apt_autoremove() {
  section "Removing Unused Packages"

  if [[ "${DRY_RUN}" == true ]]; then
    log_info "[DRY-RUN] Would run: apt-get autoremove -y"
    log_info "Packages that would be removed:"
    apt-get autoremove --dry-run 2>&1 | tee -a "${LOG_FILE}" || true
    return 0
  fi

  log_info "Running apt-get autoremove..."
  if apt-get autoremove -y 2>&1 | tee -a "${LOG_FILE}"; then
    log_success "Unused packages removed successfully"
  else
    log_warning "Some packages could not be removed (non-critical)"
  fi
}

apt_autoclean() {
  section "Cleaning Package Cache"

  if [[ "${DRY_RUN}" == true ]]; then
    log_info "[DRY-RUN] Would run: apt-get autoclean"
    return 0
  fi

  log_info "Running apt-get autoclean..."
  if apt-get autoclean 2>&1 | tee -a "${LOG_FILE}"; then
    log_success "Package cache cleaned successfully"
  else
    log_warning "Package cache cleanup had issues (non-critical)"
  fi
}

# -----------------------------------------------------------------------------
# NPM Functions
# -----------------------------------------------------------------------------

npm_update() {
  if [[ "${SKIP_NPM}" == true ]]; then
    log_info "Skipping npm updates (--no-npm flag set)"
    return 0
  fi

  section "Updating NPM Global Packages"

  if ! command_exists npm; then
    log_info "npm is not installed, skipping npm updates"
    return 0
  fi

  log_info "Checking for outdated npm global packages..."

  # Get list of outdated packages
  local outdated_packages
  outdated_packages=$(npm outdated -g --parseable 2>/dev/null || true)

  if [[ -z "${outdated_packages}" ]]; then
    log_success "All npm global packages are up to date"
    return 0
  fi

  log_info "Outdated packages found:"
  echo "${outdated_packages}" | tee -a "${LOG_FILE}"

  if [[ "${DRY_RUN}" == true ]]; then
    log_info "[DRY-RUN] Would run: npm update -g"
    return 0
  fi

  log_info "Updating npm global packages..."
  if npm update -g 2>&1 | tee -a "${LOG_FILE}"; then
    log_success "npm global packages updated successfully"
  else
    log_warning "Some npm packages could not be updated"
    return "${EXIT_NPM_UPDATE_FAILED}"
  fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
  parse_args "$@"
  check_root
  init_logging "update-system"

  log_info "Starting system update..."
  log_info "Dry-run mode: ${DRY_RUN}"
  log_info "Skip npm: ${SKIP_NPM}"

  section "System Information"
  show_system_info

  # APT updates
  apt_update
  apt_upgrade
  apt_dist_upgrade
  apt_autoremove
  apt_autoclean

  # NPM updates
  npm_update

  section "Update Complete"

  # Check if reboot is required
  if reboot_required; then
    log_warning "System reboot is required to complete updates"
  fi
}

main "$@"
