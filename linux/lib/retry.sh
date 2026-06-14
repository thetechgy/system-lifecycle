#!/usr/bin/env bash
#
# retry.sh - Retry logic with exponential backoff
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/retry.sh"
#   retry_with_backoff 3 apt-get update
#   retry_command 5 2 curl -fsSL https://example.com
#
# Dependencies:
#   - logging.sh (must be sourced first for log_info, log_warning, log_error)

# Default retry settings
RETRY_MAX_ATTEMPTS="${RETRY_MAX_ATTEMPTS:-3}"
RETRY_INITIAL_DELAY="${RETRY_INITIAL_DELAY:-1}"
RETRY_MAX_DELAY="${RETRY_MAX_DELAY:-60}"
RETRY_BACKOFF_MULTIPLIER="${RETRY_BACKOFF_MULTIPLIER:-2}"

# Retry a command with exponential backoff
# Arguments:
#   $1 - Maximum number of attempts
#   $@ - Command to execute (remaining arguments)
# Returns:
#   Exit code of the command on success, 1 on all retries exhausted
retry_with_backoff() {
  local max_attempts="${1}"
  shift
  local cmd=("$@")

  local attempt=1
  local delay="${RETRY_INITIAL_DELAY}"
  local exit_code=0

  while [[ ${attempt} -le ${max_attempts} ]]; do
    log_info "Attempt ${attempt}/${max_attempts}: ${cmd[*]}"

    # Execute command and capture exit code immediately
    "${cmd[@]}" && exit_code=0 || exit_code=$?

    if [[ ${exit_code} -eq 0 ]]; then
      if [[ ${attempt} -gt 1 ]]; then
        log_success "Command succeeded on attempt ${attempt}"
      fi
      return 0
    fi

    if [[ ${attempt} -eq ${max_attempts} ]]; then
      log_error "Command failed after ${max_attempts} attempts: ${cmd[*]}"
      return ${exit_code}
    fi

    log_warning "Attempt ${attempt} failed (exit code: ${exit_code}), retrying in ${delay}s..."
    sleep "${delay}"

    # Calculate next delay with exponential backoff
    delay=$((delay * RETRY_BACKOFF_MULTIPLIER))
    if [[ ${delay} -gt ${RETRY_MAX_DELAY} ]]; then
      delay="${RETRY_MAX_DELAY}"
    fi

    ((attempt++))
  done

  return 1
}

# Simple retry without exponential backoff
# Arguments:
#   $1 - Maximum number of attempts
#   $2 - Delay between attempts (seconds)
#   $@ - Command to execute (remaining arguments)
# Returns:
#   Exit code of the command on success, 1 on all retries exhausted
retry_command() {
  local max_attempts="${1}"
  local delay="${2}"
  shift 2
  local cmd=("$@")

  local attempt=1
  local exit_code=0

  while [[ ${attempt} -le ${max_attempts} ]]; do
    log_info "Attempt ${attempt}/${max_attempts}: ${cmd[*]}"

    # Execute command and capture exit code immediately
    "${cmd[@]}" && exit_code=0 || exit_code=$?

    if [[ ${exit_code} -eq 0 ]]; then
      if [[ ${attempt} -gt 1 ]]; then
        log_success "Command succeeded on attempt ${attempt}"
      fi
      return 0
    fi

    if [[ ${attempt} -eq ${max_attempts} ]]; then
      log_error "Command failed after ${max_attempts} attempts: ${cmd[*]}"
      return ${exit_code}
    fi

    log_warning "Attempt ${attempt} failed, retrying in ${delay}s..."
    sleep "${delay}"

    ((attempt++))
  done

  return 1
}

# Retry a command until a condition is met
# Arguments:
#   $1 - Maximum number of attempts
#   $2 - Delay between attempts (seconds)
#   $3 - Condition function name (must return 0 when satisfied)
#        Must be a simple function/command name - no shell expressions
#   $@ - Command to execute (remaining arguments)
# Returns:
#   0 when condition is met, 1 on timeout
retry_until() {
  local max_attempts="${1}"
  local delay="${2}"
  local condition="${3}"
  shift 3
  local cmd=("$@")

  # Security: Validate condition is a simple function/command name
  # Reject anything that looks like shell injection
  if [[ "${condition}" =~ [[:space:]\;\|\&\$\`\(\)\<\>\"\'\!] ]]; then
    log_error "Invalid condition '${condition}': must be a simple function or command name"
    log_error "Shell expressions are not allowed for security reasons"
    return 1
  fi

  # Verify the condition is callable
  if ! type "${condition}" &>/dev/null; then
    log_error "Condition '${condition}' is not a valid function or command"
    return 1
  fi

  local attempt=1

  while [[ ${attempt} -le ${max_attempts} ]]; do
    # Execute the main command
    if [[ ${#cmd[@]} -gt 0 ]]; then
      "${cmd[@]}" || true
    fi

    # Check condition - call directly without eval for security
    if "${condition}"; then
      log_success "Condition met on attempt ${attempt}"
      return 0
    fi

    if [[ ${attempt} -eq ${max_attempts} ]]; then
      log_error "Condition not met after ${max_attempts} attempts"
      return 1
    fi

    log_info "Waiting for condition (attempt ${attempt}/${max_attempts})..."
    sleep "${delay}"

    ((attempt++))
  done

  return 1
}

# Retry APT update with intelligent handling
# Returns:
#   0 on success, non-zero on failure
retry_apt_update() {
  local max_attempts="${1:-3}"

  retry_with_backoff "${max_attempts}" apt-get update
}

# Retry a download with curl
# Arguments:
#   $1 - URL to download
#   $2 - Output file path
#   $3 - (optional) Maximum attempts (default: 3)
# Returns:
#   0 on success, non-zero on failure
retry_download() {
  local url="${1}"
  local output="${2}"
  local max_attempts="${3:-3}"

  retry_with_backoff "${max_attempts}" curl -fsSL -o "${output}" "${url}"
}

# Wait for a service to become available
# Arguments:
#   $1 - Service name (e.g., "snapd")
#   $2 - (optional) Maximum wait time in seconds (default: 60)
#   $3 - (optional) Check interval in seconds (default: 5)
# Returns:
#   0 when service is available, 1 on timeout
wait_for_service() {
  local service_name="${1}"
  local max_wait="${2:-60}"
  local interval="${3:-5}"

  # Validate service name - only allow alphanumeric, dash, underscore, @ and .
  if [[ ! "${service_name}" =~ ^[a-zA-Z0-9@._-]+$ ]]; then
    log_error "Invalid service name '${service_name}'"
    return 1
  fi

  local max_attempts=$((max_wait / interval))
  if [[ ${max_attempts} -lt 1 ]]; then
    max_attempts=1
  fi

  log_info "Waiting for service '${service_name}' to become active..."

  local attempt=1
  while [[ ${attempt} -le ${max_attempts} ]]; do
    if systemctl is-active --quiet "${service_name}" 2>/dev/null; then
      log_success "Service '${service_name}' is active"
      return 0
    fi

    if [[ ${attempt} -eq ${max_attempts} ]]; then
      log_error "Service '${service_name}' not available after ${max_wait}s"
      return 1
    fi

    log_info "Waiting for service (attempt ${attempt}/${max_attempts})..."
    sleep "${interval}"
    ((attempt++))
  done

  return 1
}

# Check if network is available
# Returns:
#   0 if network is available, 1 otherwise
network_available() {
  ping -c 1 -W 2 8.8.8.8 &>/dev/null || \
  ping -c 1 -W 2 1.1.1.1 &>/dev/null
}

# Wait for network connectivity
# Arguments:
#   $1 - (optional) Maximum wait time in seconds (default: 30)
# Returns:
#   0 when network is available, 1 on timeout
wait_for_network() {
  local max_wait="${1:-30}"

  log_info "Waiting for network connectivity..."

  local interval=2
  local max_attempts=$((max_wait / interval))

  retry_until "${max_attempts}" "${interval}" "network_available"
}

# Retry with jitter (randomized delay to avoid thundering herd)
# Arguments:
#   $1 - Maximum number of attempts
#   $2 - Base delay (seconds)
#   $@ - Command to execute (remaining arguments)
# Returns:
#   Exit code of the command on success, 1 on all retries exhausted
retry_with_jitter() {
  local max_attempts="${1}"
  local base_delay="${2}"
  shift 2
  local cmd=("$@")

  local attempt=1
  local exit_code=0

  while [[ ${attempt} -le ${max_attempts} ]]; do
    log_info "Attempt ${attempt}/${max_attempts}: ${cmd[*]}"

    # Execute command and capture exit code immediately
    "${cmd[@]}" && exit_code=0 || exit_code=$?

    if [[ ${exit_code} -eq 0 ]]; then
      if [[ ${attempt} -gt 1 ]]; then
        log_success "Command succeeded on attempt ${attempt}"
      fi
      return 0
    fi

    if [[ ${attempt} -eq ${max_attempts} ]]; then
      log_error "Command failed after ${max_attempts} attempts: ${cmd[*]}"
      return ${exit_code}
    fi

    # Add jitter: random value between 0 and base_delay
    local jitter=$((RANDOM % base_delay))
    local delay=$((base_delay + jitter))

    log_warning "Attempt ${attempt} failed, retrying in ${delay}s (with jitter)..."
    sleep "${delay}"

    ((attempt++))
  done

  return 1
}
