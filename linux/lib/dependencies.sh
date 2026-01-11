#!/usr/bin/env bash
#
# dependencies.sh - Dependency checking utilities
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/dependencies.sh"
#   require_commands curl gpg jq
#   require_any_command fd fdfind fd-find
#
# Dependencies:
#   - logging.sh (must be sourced first for log_error, log_warning)
#   - utils.sh (for command_exists)

# Check that required commands are available
# Arguments:
#   $@ - List of required command names
# Returns:
#   0 if all commands exist, 1 otherwise
# Side effects:
#   Logs error and exits if any command is missing
require_commands() {
  local missing=()

  for cmd in "$@"; do
    if ! command_exists "${cmd}"; then
      missing+=("${cmd}")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Missing required commands: ${missing[*]}"
    log_error "Please install the missing dependencies and try again"
    return 1
  fi

  return 0
}

# Check that at least one of the specified commands is available
# Arguments:
#   $@ - List of alternative command names (any one will satisfy the requirement)
# Returns:
#   0 if any command exists, 1 otherwise
# Side effects:
#   Logs error if no command is found
require_any_command() {
  for cmd in "$@"; do
    if command_exists "${cmd}"; then
      return 0
    fi
  done

  log_error "None of these commands found: $*"
  log_error "Please install one of the required dependencies"
  return 1
}

# Check optional commands and warn if missing
# Arguments:
#   $@ - List of optional command names
# Returns:
#   Number of missing commands
# Side effects:
#   Logs warning for each missing command
check_optional_commands() {
  local missing_count=0

  for cmd in "$@"; do
    if ! command_exists "${cmd}"; then
      log_warning "Optional command not found: ${cmd}"
      ((missing_count++))
    fi
  done

  return "${missing_count}"
}

# Check if a library file exists and is readable
# Arguments:
#   $1 - Path to library file
# Returns:
#   0 if file exists and is readable, 1 otherwise
# Side effects:
#   Logs error if file is missing
check_library_exists() {
  local lib_file="${1}"

  if [[ ! -f "${lib_file}" ]]; then
    echo "ERROR: Required library not found: ${lib_file}" >&2
    return 1
  fi

  if [[ ! -r "${lib_file}" ]]; then
    echo "ERROR: Library not readable: ${lib_file}" >&2
    return 1
  fi

  return 0
}

# Source a library file with existence check
# Arguments:
#   $1 - Path to library file
# Returns:
#   0 on success, exits on failure
# Side effects:
#   Sources the library file or exits with error
safe_source() {
  local lib_file="${1}"

  if ! check_library_exists "${lib_file}"; then
    exit 1
  fi

  # shellcheck source=/dev/null
  source "${lib_file}"
}
