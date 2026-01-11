#!/usr/bin/env bash
#
# repositories.sh - APT repository management utilities
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/repositories.sh"
#   repo_add_gpg_key "https://example.com/key.asc" "/usr/share/keyrings/example.gpg"
#   repo_add_deb822 "example" "https://example.com/repo" "/usr/share/keyrings/example.gpg"
#
# Dependencies:
#   - logging.sh (must be sourced first for log_info, log_success, log_error)
#   - utils.sh (for command_exists)

# Download and install a GPG key for APT repository signing
# Arguments:
#   $1 - URL of the GPG key (ASCII armored)
#   $2 - Destination path for the dearmored key (e.g., /usr/share/keyrings/example.gpg)
#   $3 - (optional) Log file path
# Returns:
#   0 on success, non-zero on failure
repo_add_gpg_key() {
  local key_url="${1}"
  local dest_path="${2}"
  local log_file="${3:-}"

  # Check if already installed
  if [[ -f "${dest_path}" ]]; then
    log_info "GPG key already installed: ${dest_path}"
    return 0
  fi

  # Check prerequisites
  if ! command_exists curl; then
    log_error "curl is required to download GPG key"
    return 1
  fi

  if ! command_exists gpg; then
    log_error "gpg is required to process GPG key"
    return 1
  fi

  log_info "Downloading GPG key from: ${key_url}"

  # Create temp files securely
  local temp_raw temp_gpg
  if ! temp_raw=$(mktemp); then
    log_error "Failed to create temporary file for GPG key download"
    return 1
  fi
  if ! temp_gpg=$(mktemp); then
    log_error "Failed to create temporary file for GPG key processing"
    rm -f "${temp_raw}"
    return 1
  fi

  # Download the key (separate step for better error handling)
  local curl_exit=0
  if [[ -n "${log_file}" ]]; then
    curl -fsSL -o "${temp_raw}" "${key_url}" 2>>"${log_file}" || curl_exit=$?
  else
    curl -fsSL -o "${temp_raw}" "${key_url}" 2>/dev/null || curl_exit=$?
  fi

  if [[ ${curl_exit} -ne 0 ]]; then
    log_error "Failed to download GPG key from: ${key_url} (exit code: ${curl_exit})"
    rm -f "${temp_raw}" "${temp_gpg}"
    return 1
  fi

  # Verify we downloaded something
  if [[ ! -s "${temp_raw}" ]]; then
    log_error "Downloaded GPG key is empty"
    rm -f "${temp_raw}" "${temp_gpg}"
    return 1
  fi

  # Dearmor the key (separate step for better error handling)
  local gpg_exit=0
  if [[ -n "${log_file}" ]]; then
    gpg --dearmor < "${temp_raw}" > "${temp_gpg}" 2>>"${log_file}" || gpg_exit=$?
  else
    gpg --dearmor < "${temp_raw}" > "${temp_gpg}" 2>/dev/null || gpg_exit=$?
  fi

  if [[ ${gpg_exit} -ne 0 ]]; then
    log_error "Failed to dearmor GPG key (exit code: ${gpg_exit})"
    rm -f "${temp_raw}" "${temp_gpg}"
    return 1
  fi

  # Install the key with proper permissions
  if install -D -o root -g root -m 644 "${temp_gpg}" "${dest_path}"; then
    rm -f "${temp_raw}" "${temp_gpg}"
    log_success "GPG key installed: ${dest_path}"
    return 0
  fi

  rm -f "${temp_raw}" "${temp_gpg}"
  log_error "Failed to install GPG key: ${dest_path}"
  return 1
}

# Add a DEB822 format repository (modern .sources format)
# Arguments:
#   $1 - Repository name (used for filename)
#   $2 - Repository URI
#   $3 - GPG keyring path
#   $4 - (optional) Suite/distribution (default: "stable")
#   $5 - (optional) Components (default: "main")
#   $6 - (optional) Architectures (default: "amd64")
# Returns:
#   0 on success, non-zero on failure
repo_add_deb822() {
  local name="${1}"
  local uri="${2}"
  local keyring="${3}"
  local suite="${4:-stable}"
  local components="${5:-main}"
  local arch="${6:-amd64}"

  # Validate repository name (alphanumeric, hyphens, underscores only)
  if [[ ! "${name}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    log_error "Invalid repository name: ${name} (must be alphanumeric with hyphens/underscores)"
    return 1
  fi

  # Validate URI format (basic check for protocol)
  if [[ ! "${uri}" =~ ^https?:// ]]; then
    log_error "Invalid repository URI: ${uri} (must start with http:// or https://)"
    return 1
  fi

  # Validate keyring path exists
  if [[ ! -f "${keyring}" ]]; then
    log_error "GPG keyring not found: ${keyring}"
    return 1
  fi

  # Validate suite/components/arch (no newlines or special chars that could break format)
  local field
  for field in "${suite}" "${components}" "${arch}"; do
    if [[ "${field}" =~ [[:cntrl:]] ]]; then
      log_error "Invalid characters in repository configuration field"
      return 1
    fi
  done

  local repo_file="/etc/apt/sources.list.d/${name}.sources"

  # Check if already configured
  if [[ -f "${repo_file}" ]]; then
    log_info "Repository already configured: ${repo_file}"
    return 0
  fi

  log_info "Creating repository configuration: ${repo_file}"

  # Use quoted heredoc to prevent any expansion, then substitute safely
  cat > "${repo_file}" <<EOF
Types: deb
URIs: ${uri}
Suites: ${suite}
Components: ${components}
Architectures: ${arch}
Signed-By: ${keyring}
EOF

  if [[ -f "${repo_file}" ]]; then
    log_success "Repository configured: ${name}"
    return 0
  fi

  log_error "Failed to create repository configuration: ${repo_file}"
  return 1
}

# Add a traditional deb line repository (legacy format)
# Arguments:
#   $1 - Repository name (used for filename)
#   $2 - Full deb line (e.g., "deb [arch=amd64] https://... focal main")
# Returns:
#   0 on success, non-zero on failure
repo_add_traditional() {
  local name="${1}"
  local deb_line="${2}"

  # Validate repository name (alphanumeric, hyphens, underscores only)
  if [[ ! "${name}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    log_error "Invalid repository name: ${name} (must be alphanumeric with hyphens/underscores)"
    return 1
  fi

  # Validate deb line starts with deb or deb-src
  if [[ ! "${deb_line}" =~ ^deb(-src)?[[:space:]] ]]; then
    log_error "Invalid deb line format: must start with 'deb' or 'deb-src'"
    return 1
  fi

  # Check for control characters that could corrupt the file
  if [[ "${deb_line}" =~ [[:cntrl:]] ]]; then
    log_error "Invalid characters in deb line"
    return 1
  fi

  local repo_file="/etc/apt/sources.list.d/${name}.list"

  # Check if already configured
  if [[ -f "${repo_file}" ]]; then
    log_info "Repository already configured: ${repo_file}"
    return 0
  fi

  log_info "Creating repository configuration: ${repo_file}"

  printf '%s\n' "${deb_line}" > "${repo_file}"

  if [[ -f "${repo_file}" ]]; then
    log_success "Repository configured: ${name}"
    return 0
  fi

  log_error "Failed to create repository configuration: ${repo_file}"
  return 1
}

# Remove a repository configuration
# Arguments:
#   $1 - Repository name
# Returns:
#   0 on success, non-zero on failure
repo_remove() {
  local name="${1}"
  local removed=false

  # Try DEB822 format first
  local deb822_file="/etc/apt/sources.list.d/${name}.sources"
  if [[ -f "${deb822_file}" ]]; then
    rm -f "${deb822_file}"
    log_success "Removed repository: ${deb822_file}"
    removed=true
  fi

  # Try legacy format
  local legacy_file="/etc/apt/sources.list.d/${name}.list"
  if [[ -f "${legacy_file}" ]]; then
    rm -f "${legacy_file}"
    log_success "Removed repository: ${legacy_file}"
    removed=true
  fi

  if [[ "${removed}" == true ]]; then
    return 0
  fi

  log_warning "Repository not found: ${name}"
  return 1
}

# Remove a GPG key
# Arguments:
#   $1 - Path to GPG key file
# Returns:
#   0 on success, non-zero on failure
repo_remove_gpg_key() {
  local key_path="${1}"

  if [[ -f "${key_path}" ]]; then
    rm -f "${key_path}"
    log_success "Removed GPG key: ${key_path}"
    return 0
  fi

  log_warning "GPG key not found: ${key_path}"
  return 1
}

# Check if a repository is configured
# Arguments:
#   $1 - Repository name
# Returns:
#   0 if configured, 1 if not
repo_is_configured() {
  local name="${1}"

  [[ -f "/etc/apt/sources.list.d/${name}.sources" ]] || \
  [[ -f "/etc/apt/sources.list.d/${name}.list" ]]
}

# Add Microsoft GPG key and repository (common pattern)
# Arguments:
#   $1 - Repository name (e.g., "microsoft-edge", "vscode")
#   $2 - Repository URI
#   $3 - (optional) Suite (default: "stable")
#   $4 - (optional) Components (default: "main")
# Returns:
#   0 on success, non-zero on failure
repo_add_microsoft() {
  local name="${1}"
  local uri="${2}"
  local suite="${3:-stable}"
  local components="${4:-main}"

  local gpg_key="/usr/share/keyrings/microsoft.gpg"
  local gpg_url="https://packages.microsoft.com/keys/microsoft.asc"

  # Add GPG key first
  if ! repo_add_gpg_key "${gpg_url}" "${gpg_key}"; then
    return 1
  fi

  # Add repository
  repo_add_deb822 "${name}" "${uri}" "${gpg_key}" "${suite}" "${components}"
}
