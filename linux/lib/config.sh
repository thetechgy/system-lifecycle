#!/usr/bin/env bash
#
# config.sh - Configuration file management
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
#   config_load "/etc/system-lifecycle/config"
#   value=$(config_get "key" "default_value")
#   config_set "key" "value"
#
# Config File Format:
#   # Comments start with #
#   key=value
#   key_with_spaces="value with spaces"
#
# Dependencies:
#   - logging.sh (must be sourced first for log_info, log_warning, log_error)

# Configuration search paths (in order of precedence)
CONFIG_SEARCH_PATHS=(
  "${HOME}/.config/system-lifecycle/config"
  "/etc/system-lifecycle/config"
)

# Associative array to store configuration
declare -gA _CONFIG_VALUES

# Load configuration from a file
# Arguments:
#   $1 - (optional) Path to config file. If not provided, searches default paths.
# Returns:
#   0 on success (or no config file found), 1 on parse error
config_load() {
  local config_file="${1:-}"

  # If no file specified, search default paths
  if [[ -z "${config_file}" ]]; then
    for path in "${CONFIG_SEARCH_PATHS[@]}"; do
      if [[ -f "${path}" && -r "${path}" ]]; then
        config_file="${path}"
        break
      fi
    done
  fi

  # No config file found - not an error
  if [[ -z "${config_file}" || ! -f "${config_file}" ]]; then
    return 0
  fi

  log_info "Loading configuration from: ${config_file}"

  local line_num=0
  while IFS= read -r line || [[ -n "${line}" ]]; do
    ((line_num++))

    # Skip empty lines and comments
    [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue

    # Remove leading/trailing whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    # Skip if still empty after trimming
    [[ -z "${line}" ]] && continue

    # Parse key=value
    if [[ "${line}" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)=(.*)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local value="${BASH_REMATCH[2]}"

      # Remove quotes if present
      if [[ "${value}" =~ ^\"(.*)\"$ ]] || [[ "${value}" =~ ^\'(.*)\'$ ]]; then
        value="${BASH_REMATCH[1]}"
      fi

      _CONFIG_VALUES["${key}"]="${value}"
    else
      log_warning "Invalid config line ${line_num}: ${line}"
    fi
  done < "${config_file}"

  log_success "Configuration loaded (${#_CONFIG_VALUES[@]} values)"
  return 0
}

# Get a configuration value
# Arguments:
#   $1 - Key name
#   $2 - (optional) Default value if key not found
# Returns:
#   Prints value to stdout
config_get() {
  local key="${1}"
  local default="${2:-}"

  if [[ -v "_CONFIG_VALUES[${key}]" ]]; then
    echo "${_CONFIG_VALUES[${key}]}"
  else
    echo "${default}"
  fi
}

# Set a configuration value (in memory only)
# Arguments:
#   $1 - Key name
#   $2 - Value
config_set() {
  local key="${1}"
  local value="${2}"

  _CONFIG_VALUES["${key}"]="${value}"
}

# Check if a configuration key exists
# Arguments:
#   $1 - Key name
# Returns:
#   0 if key exists, 1 otherwise
config_has() {
  local key="${1}"

  [[ -v "_CONFIG_VALUES[${key}]" ]]
}

# Get a boolean configuration value
# Arguments:
#   $1 - Key name
#   $2 - (optional) Default value (default: false)
# Returns:
#   0 if true, 1 if false
config_get_bool() {
  local key="${1}"
  local default="${2:-false}"

  local value
  value=$(config_get "${key}" "${default}")

  case "${value,,}" in
    true|yes|1|on)
      return 0
      ;;
    false|no|0|off)
      return 1
      ;;
    *)
      log_warning "Invalid boolean value for ${key}: ${value}, using default: ${default}"
      [[ "${default,,}" =~ ^(true|yes|1|on)$ ]]
      ;;
  esac
}

# Get an integer configuration value
# Arguments:
#   $1 - Key name
#   $2 - (optional) Default value (default: 0)
# Returns:
#   Prints integer value to stdout
config_get_int() {
  local key="${1}"
  local default="${2:-0}"

  local value
  value=$(config_get "${key}" "${default}")

  if [[ "${value}" =~ ^-?[0-9]+$ ]]; then
    echo "${value}"
  else
    log_warning "Invalid integer value for ${key}: ${value}, using default: ${default}"
    echo "${default}"
  fi
}

# List all configuration keys
# Returns:
#   Prints all keys to stdout, one per line
config_keys() {
  for key in "${!_CONFIG_VALUES[@]}"; do
    echo "${key}"
  done
}

# Dump all configuration (for debugging)
config_dump() {
  log_info "Configuration dump:"
  for key in "${!_CONFIG_VALUES[@]}"; do
    echo "  ${key}=${_CONFIG_VALUES[${key}]}"
  done
}

# Save configuration to a file
# Arguments:
#   $1 - Path to config file
# Returns:
#   0 on success, non-zero on failure
config_save() {
  local config_file="${1}"

  local config_dir
  config_dir=$(dirname "${config_file}")

  # Create directory if needed
  if [[ ! -d "${config_dir}" ]]; then
    mkdir -p "${config_dir}" || return 1
  fi

  # Write configuration
  {
    echo "# System Lifecycle Configuration"
    echo "# Generated on $(date -Iseconds)"
    echo ""
    for key in "${!_CONFIG_VALUES[@]}"; do
      local value="${_CONFIG_VALUES[${key}]}"
      # Quote values with spaces
      if [[ "${value}" =~ [[:space:]] ]]; then
        echo "${key}=\"${value}\""
      else
        echo "${key}=${value}"
      fi
    done
  } > "${config_file}"

  log_success "Configuration saved to: ${config_file}"
  return 0
}

# Reset configuration (clear all values)
config_reset() {
  _CONFIG_VALUES=()
}

# Apply configuration to script variables
# Maps config keys to uppercase variable names
# Arguments:
#   $@ - List of key names to apply
# Example:
#   config_apply dry_run quiet cis_profile
#   # Sets DRY_RUN, QUIET, CIS_PROFILE from config values
config_apply() {
  for key in "$@"; do
    local var_name
    var_name=$(echo "${key}" | tr '[:lower:]' '[:upper:]')

    if config_has "${key}"; then
      local value
      value=$(config_get "${key}")
      # Export while preserving the resolved variable name/value.
      export "${var_name}=${value}"
    fi
  done
}

# Create a default configuration file
# Arguments:
#   $1 - Path to config file
# Returns:
#   0 on success, non-zero on failure
config_create_default() {
  local config_file="${1}"

  local config_dir
  config_dir=$(dirname "${config_file}")

  # Create directory if needed
  if [[ ! -d "${config_dir}" ]]; then
    mkdir -p "${config_dir}" || return 1
  fi

  cat > "${config_file}" << 'EOF'
# System Lifecycle Configuration File
#
# This file configures default behavior for system-lifecycle scripts.
# Values can be overridden by command-line arguments.
#
# Format: key=value or key="value with spaces"

# General settings
# dry_run=false
# quiet=false

# Update settings
# skip_npm=false
# skip_snap=false
# skip_flatpak=false
# run_firmware=false

# Installation settings
# skip_security=false
# skip_apps=false
# skip_devtools=false
# skip_extensions=false
# skip_fastfetch=false

# CIS hardening
# cis_profile=cis_level1_workstation
# no_audit=false

# Ubuntu Pro
# skip_ubuntu_pro=false
# ubuntu_pro_token=

# Node.js
# nodejs_version=20
EOF

  log_success "Default configuration created: ${config_file}"
  return 0
}
