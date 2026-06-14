#!/usr/bin/env bash
#
# configure-bashrc.sh - Configure shell aliases for system-lifecycle scripts
#
# Description:
#   Adds managed aliases to ~/.bashrc using section markers.
#   Safe to run multiple times (idempotent).
#
# Usage:
#   ./configure-bashrc.sh [OPTIONS]
#
# Options:
#   -d, --dry-run     Show what would be done without making changes
#   -r, --remove      Remove the managed section from ~/.bashrc
#   -h, --help        Display this help message
#
# Author: Travis McDade
# License: MIT
# Version: 1.0.0

set -o errexit
set -o nounset
set -o pipefail

# -----------------------------------------------------------------------------
# Script Configuration
# -----------------------------------------------------------------------------

SCRIPT_NAME="$(basename "${0}")"
readonly SCRIPT_NAME
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
readonly SCRIPT_DIR
readonly LIB_DIR="${SCRIPT_DIR}/../../lib"
readonly REPO_ROOT="${SCRIPT_DIR}/../../.."

readonly BASHRC="${HOME}/.bashrc"
readonly BACKUP="${HOME}/.bashrc.bak"
readonly MARKER_START="# >>> system-lifecycle >>>"
readonly MARKER_END="# <<< system-lifecycle <<<"

# Default flags
DRY_RUN=false
REMOVE=false

# -----------------------------------------------------------------------------
# Source Libraries
# -----------------------------------------------------------------------------

# Helper to check library exists before sourcing
_check_lib() {
  local lib="${1}"
  if [[ ! -f "${lib}" ]]; then
    echo "ERROR: Required library not found: ${lib}" >&2
    echo "Ensure the script is run from within the system-lifecycle repository." >&2
    exit 1
  fi
}

_check_lib "${LIB_DIR}/colors.sh"
_check_lib "${LIB_DIR}/logging.sh"
_check_lib "${LIB_DIR}/utils.sh"
_check_lib "${LIB_DIR}/version-check.sh"

# shellcheck source=../../lib/colors.sh
source "${LIB_DIR}/colors.sh"

# shellcheck source=../../lib/logging.sh
source "${LIB_DIR}/logging.sh"

# shellcheck source=../../lib/utils.sh
source "${LIB_DIR}/utils.sh"

# shellcheck source=../../lib/version-check.sh
source "${LIB_DIR}/version-check.sh"

# -----------------------------------------------------------------------------
# Help
# -----------------------------------------------------------------------------

show_usage() {
  cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Configure shell aliases for system-lifecycle scripts.
Adds a managed section to ~/.bashrc that can be safely updated or removed.

Options:
    -d, --dry-run     Show what would be done without making changes
    -r, --remove      Remove the managed section from ~/.bashrc
    -h, --help        Display this help message

Examples:
    ${SCRIPT_NAME}              # Add/update aliases
    ${SCRIPT_NAME} --dry-run    # Preview changes
    ${SCRIPT_NAME} --remove     # Remove aliases

After running, reload your shell:
    source ~/.bashrc
EOF
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
      -r|--remove)
        REMOVE=true
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

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

# Generate the managed section content
generate_section() {
  local repo_path
  repo_path="$(cd "${REPO_ROOT}" && pwd)"

  cat << EOF
${MARKER_START}
# Aliases managed by system-lifecycle - do not edit manually
alias update-system='sudo ${repo_path}/linux/ubuntu/update/update-system.sh'
${MARKER_END}
EOF
}

# Check if managed section exists in bashrc
section_exists() {
  grep -q "^${MARKER_START}$" "${BASHRC}" 2>/dev/null
}

# Remove the managed section from bashrc
remove_section() {
  if [[ "${DRY_RUN}" == true ]]; then
    log_info "[DRY-RUN] Would remove managed section from ${BASHRC}"
    return 0
  fi

  if ! section_exists; then
    log_info "No managed section found in ${BASHRC}"
    return 0
  fi

  log_info "Creating backup at ${BACKUP}"
  cp "${BASHRC}" "${BACKUP}"

  log_info "Removing managed section from ${BASHRC}"
  # Remove lines between markers (inclusive)
  sed -i "/^${MARKER_START}$/,/^${MARKER_END}$/d" "${BASHRC}"

  log_success "Managed section removed from ${BASHRC}"
}

# Add or update the managed section in bashrc
add_section() {
  local new_section
  new_section="$(generate_section)"

  if [[ "${DRY_RUN}" == true ]]; then
    log_info "[DRY-RUN] Would add the following to ${BASHRC}:"
    echo ""
    echo "${new_section}"
    echo ""
    return 0
  fi

  # Create bashrc if it doesn't exist
  if [[ ! -f "${BASHRC}" ]]; then
    log_info "Creating ${BASHRC}"
    touch "${BASHRC}"
  fi

  log_info "Creating backup at ${BACKUP}"
  cp "${BASHRC}" "${BACKUP}"

  if section_exists; then
    log_info "Updating existing managed section in ${BASHRC}"
    # Remove old section first
    sed -i "/^${MARKER_START}$/,/^${MARKER_END}$/d" "${BASHRC}"
  else
    log_info "Adding managed section to ${BASHRC}"
  fi

  # Append new section
  echo "" >> "${BASHRC}"
  echo "${new_section}" >> "${BASHRC}"

  log_success "Aliases configured in ${BASHRC}"
  log_info "Run 'source ~/.bashrc' to activate"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
  check_for_updates
  parse_args "$@"

  # Don't require logging for this script (no init_logging call)
  # Just use console output

  if [[ "${REMOVE}" == true ]]; then
    remove_section
  else
    add_section
  fi
}

main "$@"
