#!/usr/bin/env bash
#
# logging.sh - Logging utilities
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
#   init_logging "my-script"
#   log_info "Starting process"
#
# Dependencies:
#   - colors.sh (must be sourced first)

# Default log directory (can be overridden before sourcing)
LOG_DIR="${LOG_DIR:-${HOME}/logs/system-lifecycle}"
LOG_FILE=""
QUIET="${QUIET:-false}"

# Initialize logging - creates log directory and sets log file path
# Arguments:
#   $1 - Script name prefix for log file (e.g., "update-system")
init_logging() {
  local script_name="${1:-script}"
  local timestamp
  timestamp="$(date +%Y%m%d-%H%M%S)"

  if [[ ! -d "${LOG_DIR}" ]]; then
    mkdir -p "${LOG_DIR}"
  fi

  LOG_FILE="${LOG_DIR}/${script_name}-${timestamp}.log"
  touch "${LOG_FILE}"
  chmod 640 "${LOG_FILE}"

  log_info "Log file: ${LOG_FILE}"
}

# Core logging function
# Arguments:
#   $1 - Log level (INFO, SUCCESS, WARNING, ERROR)
#   $2 - Message to log
log() {
  local level="${1}"
  local message="${2}"
  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

  # Log to file (always, if initialized)
  if [[ -n "${LOG_FILE}" ]]; then
    printf '[%s] [%s] %s\n' "${timestamp}" "${level}" "${message}" >> "${LOG_FILE}"
  fi

  # Log to console (unless quiet mode)
  if [[ "${QUIET}" != true ]]; then
    case "${level}" in
      INFO)    printf "${BLUE:-}[%s]${NC:-} %s\n" "${level}" "${message}" ;;
      SUCCESS) printf "${GREEN:-}[%s]${NC:-} %s\n" "${level}" "${message}" ;;
      WARNING) printf "${YELLOW:-}[%s]${NC:-} %s\n" "${level}" "${message}" >&2 ;;
      ERROR)   printf "${RED:-}[%s]${NC:-} %s\n" "${level}" "${message}" >&2 ;;
      *)       printf "[%s] %s\n" "${level}" "${message}" ;;
    esac
  fi
}

# Convenience logging functions
log_info()    { log "INFO" "${1}"; }
log_success() { log "SUCCESS" "${1}"; }
log_warning() { log "WARNING" "${1}"; }
log_error()   { log "ERROR" "${1}"; }

# Display a section header
# Arguments:
#   $1 - Section title
section() {
  local title="${1}"

  if [[ "${QUIET}" != true ]]; then
    printf "\n${BLUE:-}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC:-}\n"
    printf "${BLUE:-}  %s${NC:-}\n" "${title}"
    printf "${BLUE:-}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC:-}\n"
  fi

  log_info "=== ${title} ==="
}
