#!/usr/bin/env bash
#
# utils.sh - Common utility functions
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
#   check_root
#   if command_exists npm; then echo "npm is installed"; fi
#
# Dependencies:
#   - logging.sh (must be sourced first for log_error)

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1
readonly EXIT_INVALID_ARGS=2
readonly EXIT_NOT_ROOT=3
readonly EXIT_APT_UPDATE_FAILED=4
readonly EXIT_APT_UPGRADE_FAILED=5
readonly EXIT_NPM_UPDATE_FAILED=6

# Check if a command exists
# Arguments:
#   $1 - Command name to check
# Returns:
#   0 if command exists, 1 otherwise
command_exists() {
  command -v "${1}" &>/dev/null
}

# Check if running as root (EUID 0)
# Exits with EXIT_NOT_ROOT if not running as root
check_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit "${EXIT_NOT_ROOT}"
  fi
}

# Get system information
# Prints formatted system info to stdout and logs
show_system_info() {
  local hostname
  local os_version
  local kernel

  hostname="$(hostname)"
  os_version="$(lsb_release -ds 2>/dev/null || grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2 || echo "Unknown")"
  kernel="$(uname -r)"

  log_info "Hostname: ${hostname}"
  log_info "OS: ${os_version}"
  log_info "Kernel: ${kernel}"
  log_info "Date: $(date '+%Y-%m-%d %H:%M:%S %Z')"
}

# Check if system reboot is required
# Returns:
#   0 if reboot required, 1 otherwise
reboot_required() {
  [[ -f /var/run/reboot-required ]]
}
