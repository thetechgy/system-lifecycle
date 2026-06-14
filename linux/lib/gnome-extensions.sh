#!/usr/bin/env bash
#
# gnome-extensions.sh - GNOME Shell extension management utilities
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/gnome-extensions.sh"
#   gnome_extension_install "Vitals@CoreCoding.com"
#   gnome_extension_enable "Vitals@CoreCoding.com"
#
# Dependencies:
#   - logging.sh (must be sourced first for log_info, log_success, log_error, log_warning)
#   - utils.sh (for command_exists)

# Check if GNOME Shell is running
# Returns:
#   0 if running, 1 if not
gnome_shell_is_running() {
  pgrep -x gnome-shell >/dev/null 2>&1
}

# Get GNOME Shell major version
# Returns:
#   Prints major version number to stdout (e.g., "46")
gnome_shell_version() {
  gnome-shell --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | cut -d. -f1
}

# Check if a GNOME extension is installed
# Arguments:
#   $1 - Extension UUID (e.g., "Vitals@CoreCoding.com")
# Returns:
#   0 if installed, 1 if not
gnome_extension_is_installed() {
  local uuid="${1}"

  if command_exists gnome-extensions; then
    gnome-extensions list 2>/dev/null | grep -Fxq -- "${uuid}"
  else
    return 1
  fi
}

# Enable a GNOME extension
# Arguments:
#   $1 - Extension UUID
#   $2 - (optional) Log file path
# Returns:
#   0 on success, 1 on failure
gnome_extension_enable() {
  local uuid="${1}"
  local log_file="${2:-}"

  if ! command_exists gnome-extensions; then
    log_warning "gnome-extensions command not found"
    return 1
  fi

  log_info "Enabling extension: ${uuid}"

  if [[ -n "${log_file}" ]]; then
    if gnome-extensions enable "${uuid}" 2>&1 | tee -a "${log_file}"; then
      log_success "Extension enabled: ${uuid}"
      return 0
    fi
  else
    if gnome-extensions enable "${uuid}"; then
      log_success "Extension enabled: ${uuid}"
      return 0
    fi
  fi

  log_warning "Failed to enable extension: ${uuid} (may need manual activation)"
  return 1
}

# Disable a GNOME extension
# Arguments:
#   $1 - Extension UUID
#   $2 - (optional) Log file path
# Returns:
#   0 on success, 1 on failure
gnome_extension_disable() {
  local uuid="${1}"
  local log_file="${2:-}"

  if ! command_exists gnome-extensions; then
    log_warning "gnome-extensions command not found"
    return 1
  fi

  log_info "Disabling extension: ${uuid}"

  if [[ -n "${log_file}" ]]; then
    if gnome-extensions disable "${uuid}" 2>&1 | tee -a "${log_file}"; then
      log_success "Extension disabled: ${uuid}"
      return 0
    fi
  else
    if gnome-extensions disable "${uuid}"; then
      log_success "Extension disabled: ${uuid}"
      return 0
    fi
  fi

  log_warning "Failed to disable extension: ${uuid}"
  return 1
}

# Query GNOME Extensions API for extension info
# Arguments:
#   $1 - Extension UUID
# Returns:
#   Prints JSON response to stdout, empty on failure
gnome_extension_api_query() {
  local uuid="${1}"
  local url="https://extensions.gnome.org/extension-info/?uuid=${uuid}"

  if ! command_exists curl; then
    log_error "curl is required to query GNOME Extensions API"
    return 1
  fi

  curl -s "${url}" 2>/dev/null
}

# Get extension version tag for current GNOME Shell version
# Arguments:
#   $1 - Extension UUID
#   $2 - GNOME Shell major version
# Returns:
#   Prints version tag (pk) to stdout, empty if not available
gnome_extension_get_version_tag() {
  local uuid="${1}"
  local gnome_version="${2}"

  if ! command_exists jq; then
    log_error "jq is required to parse extension metadata"
    return 1
  fi

  local info
  info=$(gnome_extension_api_query "${uuid}")

  if [[ -z "${info}" ]]; then
    return 1
  fi

  local version_tag
  version_tag=$(echo "${info}" | jq -r ".shell_version_map.\"${gnome_version}\".pk" 2>/dev/null)

  if [[ -z "${version_tag}" || "${version_tag}" == "null" ]]; then
    return 1
  fi

  echo "${version_tag}"
}

# Install a GNOME extension from extensions.gnome.org
# Arguments:
#   $1 - Extension UUID (e.g., "Vitals@CoreCoding.com")
#   $2 - (optional) Log file path
# Returns:
#   0 on success, non-zero on failure
gnome_extension_install() {
  local uuid="${1}"
  local log_file="${2:-}"

  # Check prerequisites
  if ! gnome_shell_is_running; then
    log_warning "GNOME Shell is not running, skipping extension installation"
    return 0
  fi

  if ! command_exists curl; then
    log_error "curl is required to download extensions"
    return 1
  fi

  if ! command_exists jq; then
    log_error "jq is required to parse extension metadata"
    return 1
  fi

  if ! command_exists gnome-extensions; then
    log_error "gnome-extensions command not found"
    return 1
  fi

  # Check if already installed
  if gnome_extension_is_installed "${uuid}"; then
    log_success "Extension already installed: ${uuid}"
    return 0
  fi

  # Get GNOME Shell version
  local gnome_version
  gnome_version=$(gnome_shell_version)

  if [[ -z "${gnome_version}" ]]; then
    log_error "Could not determine GNOME Shell version"
    return 1
  fi

  log_info "Detected GNOME Shell version: ${gnome_version}"
  log_info "Downloading extension: ${uuid}"

  # Get version tag for current GNOME version
  local version_tag
  version_tag=$(gnome_extension_get_version_tag "${uuid}" "${gnome_version}")

  if [[ -z "${version_tag}" ]]; then
    log_error "Extension ${uuid} not available for GNOME Shell ${gnome_version}"
    return 1
  fi

  log_info "Extension version tag: ${version_tag}"

  # Download extension
  local download_url="https://extensions.gnome.org/download-extension/${uuid}.shell-extension.zip?version_tag=${version_tag}"
  local temp_zip
  if ! temp_zip=$(mktemp --suffix=.zip); then
    log_error "Failed to create temporary file for extension download"
    return 1
  fi

  if ! curl -fsSL -o "${temp_zip}" "${download_url}"; then
    log_error "Failed to download extension: ${uuid}"
    rm -f "${temp_zip}"
    return 1
  fi

  # Install extension
  log_info "Installing extension: ${uuid}"

  if [[ -n "${log_file}" ]]; then
    if gnome-extensions install --force "${temp_zip}" 2>&1 | tee -a "${log_file}"; then
      log_success "Extension installed: ${uuid}"
      rm -f "${temp_zip}"
      return 0
    fi
  else
    if gnome-extensions install --force "${temp_zip}"; then
      log_success "Extension installed: ${uuid}"
      rm -f "${temp_zip}"
      return 0
    fi
  fi

  log_error "Failed to install extension: ${uuid}"
  rm -f "${temp_zip}"
  return 1
}

# Load dconf configuration for an extension
# Arguments:
#   $1 - dconf path (e.g., "/org/gnome/shell/extensions/vitals/")
#   $2 - Configuration file path
#   $3 - (optional) Log file path
# Returns:
#   0 on success, 1 on failure
gnome_extension_load_config() {
  local dconf_path="${1}"
  local config_file="${2}"
  local log_file="${3:-}"

  if ! command_exists dconf; then
    log_warning "dconf command not found - cannot load configuration"
    return 1
  fi

  if [[ ! -f "${config_file}" ]]; then
    log_warning "Configuration file not found: ${config_file}"
    return 1
  fi

  log_info "Loading extension configuration from: ${config_file}"

  if [[ -n "${log_file}" ]]; then
    if dconf load "${dconf_path}" < "${config_file}" 2>&1 | tee -a "${log_file}"; then
      log_success "Extension configuration applied"
      return 0
    fi
  else
    if dconf load "${dconf_path}" < "${config_file}"; then
      log_success "Extension configuration applied"
      return 0
    fi
  fi

  log_warning "Failed to load extension configuration"
  return 1
}
