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
#   -d, --dry-run      Show what would be done without making changes
#   -q, --quiet        Suppress non-essential output
#   -n, --no-npm       Skip npm package updates
#   --no-snap          Skip snap package updates
#   --no-flatpak       Skip flatpak package updates
#   --firmware         Enable firmware updates (opt-in)
#   --clean            Use apt-get clean instead of autoclean
#   -h, --help         Display this help message
#   -v, --version      Display script version
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

SCRIPT_NAME="$(basename "${0}")"
readonly SCRIPT_NAME
readonly SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
readonly SCRIPT_DIR
readonly LIB_DIR="${SCRIPT_DIR}/../../lib"

# Default flags
DRY_RUN=false
# shellcheck disable=SC2034  # Used by logging.sh
QUIET=false
SKIP_NPM=false
SKIP_SNAP=false
SKIP_FLATPAK=false
RUN_FIRMWARE=false
RUN_CLEAN=false

# -----------------------------------------------------------------------------
# Source Libraries
# -----------------------------------------------------------------------------

# shellcheck source=../../lib/colors.sh
source "${LIB_DIR}/colors.sh"

# shellcheck source=../../lib/logging.sh
source "${LIB_DIR}/logging.sh"

# shellcheck source=../../lib/utils.sh
source "${LIB_DIR}/utils.sh"

# shellcheck source=../../lib/version-check.sh
source "${LIB_DIR}/version-check.sh"

# -----------------------------------------------------------------------------
# Help and Version
# -----------------------------------------------------------------------------

show_usage() {
  cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Ubuntu 24.04 LTS System Update Script

Options:
    -d, --dry-run      Show what would be done without making changes
    -q, --quiet        Suppress non-essential output
    -n, --no-npm       Skip npm package updates
    --no-snap          Skip snap package updates
    --no-flatpak       Skip flatpak package updates
    --firmware         Enable firmware updates (requires fwupd)
    --clean            Use apt-get clean (remove ALL cached packages)
    -h, --help         Display this help message
    -v, --version      Display script version

Examples:
    sudo ${SCRIPT_NAME}              # Full update (apt, snap, flatpak, npm)
    sudo ${SCRIPT_NAME} --dry-run    # Preview changes
    sudo ${SCRIPT_NAME} --no-snap    # Skip snap updates
    sudo ${SCRIPT_NAME} --firmware   # Include firmware updates
    sudo ${SCRIPT_NAME} --clean      # Aggressive cache cleanup

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
        # shellcheck disable=SC2034  # Used by logging.sh
        QUIET=true
        shift
        ;;
      -n|--no-npm)
        SKIP_NPM=true
        shift
        ;;
      --no-snap)
        SKIP_SNAP=true
        shift
        ;;
      --no-flatpak)
        SKIP_FLATPAK=true
        shift
        ;;
      --firmware)
        RUN_FIRMWARE=true
        shift
        ;;
      --clean)
        RUN_CLEAN=true
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

apt_clean() {
  section "Cleaning Package Cache"

  if [[ "${RUN_CLEAN}" == true ]]; then
    # Full clean - removes ALL cached packages
    if [[ "${DRY_RUN}" == true ]]; then
      log_info "[DRY-RUN] Would run: apt-get clean"
      return 0
    fi

    log_info "Running apt-get clean (removing all cached packages)..."
    if apt-get clean 2>&1 | tee -a "${LOG_FILE}"; then
      log_success "Package cache cleaned successfully"
    else
      log_warning "Package cache cleanup had issues (non-critical)"
    fi
  else
    # Default - only removes obsolete packages
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
# Snap Functions
# -----------------------------------------------------------------------------

snap_update() {
  if [[ "${SKIP_SNAP}" == true ]]; then
    log_info "Skipping snap updates (--no-snap flag set)"
    return 0
  fi

  section "Updating Snap Packages"

  if ! command_exists snap; then
    log_info "snap is not installed, skipping snap updates"
    return 0
  fi

  if [[ "${DRY_RUN}" == true ]]; then
    log_info "[DRY-RUN] Would run: snap refresh"
    snap refresh --list 2>&1 | tee -a "${LOG_FILE}" || true
    return 0
  fi

  log_info "Running snap refresh..."
  if snap refresh 2>&1 | tee -a "${LOG_FILE}"; then
    log_success "Snap packages updated successfully"
  else
    log_warning "Some snap packages could not be updated"
  fi
}

# -----------------------------------------------------------------------------
# Flatpak Functions
# -----------------------------------------------------------------------------

flatpak_update() {
  if [[ "${SKIP_FLATPAK}" == true ]]; then
    log_info "Skipping flatpak updates (--no-flatpak flag set)"
    return 0
  fi

  section "Updating Flatpak Packages"

  if ! command_exists flatpak; then
    log_info "flatpak is not installed, skipping flatpak updates"
    return 0
  fi

  if [[ "${DRY_RUN}" == true ]]; then
    log_info "[DRY-RUN] Would run: flatpak update -y"
    return 0
  fi

  log_info "Running flatpak update..."
  if flatpak update -y 2>&1 | tee -a "${LOG_FILE}"; then
    log_success "Flatpak packages updated successfully"
  else
    log_warning "Some flatpak packages could not be updated"
  fi
}

# -----------------------------------------------------------------------------
# Firmware Functions
# -----------------------------------------------------------------------------

firmware_update() {
  if [[ "${RUN_FIRMWARE}" != true ]]; then
    return 0
  fi

  section "Updating Firmware"

  # Skip on WSL - firmware updates not applicable in virtualized environment
  if grep -qi microsoft /proc/version 2>/dev/null; then
    log_info "WSL detected - firmware updates not supported in virtualized environment"
    return 0
  fi

  if ! command_exists fwupdmgr; then
    log_info "Installing fwupd for firmware updates..."
    if DEBIAN_FRONTEND=noninteractive apt-get install -y fwupd 2>&1 | tee -a "${LOG_FILE}"; then
      log_success "fwupd installed successfully"
    else
      log_error "Failed to install fwupd"
      return 1
    fi
  fi

  if [[ "${DRY_RUN}" == true ]]; then
    log_info "[DRY-RUN] Would run: fwupdmgr update"
    log_info "Checking for firmware updates..."
    fwupdmgr get-updates 2>&1 | tee -a "${LOG_FILE}" || true
    return 0
  fi

  log_info "Refreshing firmware metadata..."
  fwupdmgr refresh --force 2>&1 | tee -a "${LOG_FILE}" || true

  log_info "Running firmware updates..."
  if fwupdmgr update -y 2>&1 | tee -a "${LOG_FILE}"; then
    log_success "Firmware updated successfully"
  else
    log_warning "Some firmware updates could not be applied"
  fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
  check_for_updates
  parse_args "$@"
  check_root
  init_logging "update-system"

  log_info "Starting system update..."
  log_info "Dry-run mode: ${DRY_RUN}"
  log_info "Skip snap: ${SKIP_SNAP}"
  log_info "Skip flatpak: ${SKIP_FLATPAK}"
  log_info "Skip npm: ${SKIP_NPM}"
  log_info "Firmware updates: ${RUN_FIRMWARE}"
  log_info "Full cache clean: ${RUN_CLEAN}"

  section "System Information"
  show_system_info

  # APT updates
  apt_update
  apt_upgrade
  apt_dist_upgrade

  # Package manager updates
  snap_update
  flatpak_update
  npm_update

  # Firmware updates (opt-in)
  firmware_update

  # Cleanup
  apt_autoremove
  apt_clean

  section "Update Complete"

  # Check if reboot is required
  if reboot_required; then
    log_warning "System reboot is required to complete updates"
  fi
}

main "$@"
