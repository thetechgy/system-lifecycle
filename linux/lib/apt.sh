#!/usr/bin/env bash
#
# apt.sh - APT package management utilities
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/apt.sh"
#   apt_update
#   apt_upgrade
#   apt_install package1 package2
#
# Dependencies:
#   - logging.sh (must be sourced first for log_info, log_success, log_error)
#   - utils.sh (for command_exists, exit codes)

# Update APT package lists
# Arguments:
#   $1 - (optional) Log file path for capturing output
# Returns:
#   0 on success, non-zero on failure
apt_update() {
  local log_file="${1:-}"

  log_info "Updating package lists..."

  if [[ -n "${log_file}" ]]; then
    if apt-get update 2>&1 | tee -a "${log_file}"; then
      log_success "Package lists updated"
      return 0
    fi
  else
    if apt-get update; then
      log_success "Package lists updated"
      return 0
    fi
  fi

  log_error "Failed to update package lists"
  return 1
}

# Perform APT upgrade
# Arguments:
#   $1 - (optional) Log file path for capturing output
# Returns:
#   0 on success, non-zero on failure
apt_upgrade() {
  local log_file="${1:-}"

  log_info "Upgrading packages..."

  if [[ -n "${log_file}" ]]; then
    if DEBIAN_FRONTEND=noninteractive apt-get upgrade -y 2>&1 | tee -a "${log_file}"; then
      log_success "Packages upgraded"
      return 0
    fi
  else
    if DEBIAN_FRONTEND=noninteractive apt-get upgrade -y; then
      log_success "Packages upgraded"
      return 0
    fi
  fi

  log_error "Failed to upgrade packages"
  return 1
}

# Perform APT dist-upgrade
# Arguments:
#   $1 - (optional) Log file path for capturing output
# Returns:
#   0 on success, non-zero on failure
apt_dist_upgrade() {
  local log_file="${1:-}"

  log_info "Performing distribution upgrade..."

  if [[ -n "${log_file}" ]]; then
    if DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y 2>&1 | tee -a "${log_file}"; then
      log_success "Distribution upgrade completed"
      return 0
    fi
  else
    if DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y; then
      log_success "Distribution upgrade completed"
      return 0
    fi
  fi

  log_error "Failed to perform distribution upgrade"
  return 1
}

# Install APT packages
# Arguments:
#   $@ - Package names to install
# Returns:
#   0 on success, non-zero on failure
apt_install() {
  if [[ $# -eq 0 ]]; then
    log_error "apt_install: No packages specified"
    return 1
  fi

  local packages=("$@")
  log_info "Installing packages: ${packages[*]}"

  if DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"; then
    log_success "Packages installed: ${packages[*]}"
    return 0
  fi

  log_error "Failed to install packages: ${packages[*]}"
  return 1
}

# Install APT packages with log file
# Arguments:
#   $1 - Log file path
#   $@ - Package names to install (remaining arguments)
# Returns:
#   0 on success, non-zero on failure
apt_install_with_log() {
  local log_file="${1}"
  shift

  if [[ $# -eq 0 ]]; then
    log_error "apt_install_with_log: No packages specified"
    return 1
  fi

  local packages=("$@")
  log_info "Installing packages: ${packages[*]}"

  if DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}" 2>&1 | tee -a "${log_file}"; then
    log_success "Packages installed: ${packages[*]}"
    return 0
  fi

  log_error "Failed to install packages: ${packages[*]}"
  return 1
}

# Remove unused packages (autoremove)
# Arguments:
#   $1 - (optional) Log file path for capturing output
# Returns:
#   0 on success, non-zero on failure
apt_autoremove() {
  local log_file="${1:-}"

  log_info "Removing unused packages..."

  if [[ -n "${log_file}" ]]; then
    if apt-get autoremove -y 2>&1 | tee -a "${log_file}"; then
      log_success "Unused packages removed"
      return 0
    fi
  else
    if apt-get autoremove -y; then
      log_success "Unused packages removed"
      return 0
    fi
  fi

  log_warning "Failed to remove unused packages"
  return 1
}

# Clean APT cache (autoclean - removes outdated packages only)
# Arguments:
#   $1 - (optional) Log file path for capturing output
# Returns:
#   0 on success, non-zero on failure
apt_autoclean() {
  local log_file="${1:-}"

  log_info "Cleaning package cache (autoclean)..."

  if [[ -n "${log_file}" ]]; then
    if apt-get autoclean 2>&1 | tee -a "${log_file}"; then
      log_success "Package cache cleaned"
      return 0
    fi
  else
    if apt-get autoclean; then
      log_success "Package cache cleaned"
      return 0
    fi
  fi

  log_warning "Failed to clean package cache"
  return 1
}

# Clean APT cache (clean - removes ALL cached packages)
# Arguments:
#   $1 - (optional) Log file path for capturing output
# Returns:
#   0 on success, non-zero on failure
apt_clean() {
  local log_file="${1:-}"

  log_info "Cleaning package cache (full clean)..."

  if [[ -n "${log_file}" ]]; then
    if apt-get clean 2>&1 | tee -a "${log_file}"; then
      log_success "Package cache fully cleaned"
      return 0
    fi
  else
    if apt-get clean; then
      log_success "Package cache fully cleaned"
      return 0
    fi
  fi

  log_warning "Failed to fully clean package cache"
  return 1
}

# Check if a package is installed
# Arguments:
#   $1 - Package name
# Returns:
#   0 if installed, 1 if not installed
apt_is_installed() {
  local package="${1}"

  # Use dpkg-query for safe, exact package name matching (no regex injection)
  if dpkg-query -W -f='${Status}' "${package}" 2>/dev/null | grep -q "^install ok installed$"; then
    return 0
  fi
  return 1
}

# Get installed package version
# Arguments:
#   $1 - Package name
# Returns:
#   Prints version string to stdout, empty if not installed
apt_get_version() {
  local package="${1}"

  dpkg-query -W -f='${Version}' "${package}" 2>/dev/null || echo ""
}
