#!/usr/bin/env bash
#
# rollback.sh - Backup and rollback utilities
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/rollback.sh"
#   rollback_create_restore_point "pre-hardening"
#   rollback_backup_file "/etc/ssh/sshd_config"
#   rollback_restore "pre-hardening"
#
# Dependencies:
#   - logging.sh (must be sourced first for log_info, log_success, log_error, log_warning)
#   - utils.sh (for command_exists)

# Default backup directory
ROLLBACK_DIR="${ROLLBACK_DIR:-/var/backups/system-lifecycle}"

# Create a restore point (snapshot of key system files)
# Arguments:
#   $1 - Restore point name (e.g., "pre-hardening")
#   $2 - (optional) Additional directories to backup (space-separated)
# Returns:
#   0 on success, non-zero on failure
rollback_create_restore_point() {
  local name="${1}"
  local extra_dirs="${2:-}"

  local timestamp
  timestamp=$(date +%Y%m%d-%H%M%S)
  local restore_point_dir="${ROLLBACK_DIR}/restore-points/${name}-${timestamp}"

  log_info "Creating restore point: ${name}"

  # Create restore point directory
  if ! mkdir -p "${restore_point_dir}"; then
    log_error "Failed to create restore point directory: ${restore_point_dir}"
    return 1
  fi

  # Backup /etc directory
  log_info "Backing up /etc directory..."
  if tar czf "${restore_point_dir}/etc.tar.gz" /etc/ 2>/dev/null; then
    log_success "Backed up /etc"
  else
    log_warning "Failed to backup /etc (non-critical)"
  fi

  # Backup APT sources
  log_info "Backing up APT sources..."
  if tar czf "${restore_point_dir}/apt-sources.tar.gz" /etc/apt/sources.list.d/ 2>/dev/null; then
    log_success "Backed up APT sources"
  else
    log_warning "Failed to backup APT sources"
  fi

  # Backup GPG keys
  log_info "Backing up GPG keyrings..."
  if tar czf "${restore_point_dir}/keyrings.tar.gz" /usr/share/keyrings/ 2>/dev/null; then
    log_success "Backed up GPG keyrings"
  else
    log_warning "Failed to backup GPG keyrings"
  fi

  # Backup additional directories if specified
  if [[ -n "${extra_dirs}" ]]; then
    for dir in ${extra_dirs}; do
      if [[ -d "${dir}" ]]; then
        local dir_name
        dir_name=$(echo "${dir}" | tr '/' '_')
        log_info "Backing up ${dir}..."
        if tar czf "${restore_point_dir}/${dir_name}.tar.gz" "${dir}" 2>/dev/null; then
          log_success "Backed up ${dir}"
        else
          log_warning "Failed to backup ${dir}"
        fi
      fi
    done
  fi

  # Save restore point metadata
  cat > "${restore_point_dir}/metadata" << EOF
name=${name}
timestamp=${timestamp}
created=$(date -Iseconds)
hostname=$(hostname)
os=$(lsb_release -ds 2>/dev/null || echo "Unknown")
EOF

  log_success "Restore point created: ${restore_point_dir}"
  echo "${restore_point_dir}"
}

# Backup a single file
# Arguments:
#   $1 - File path to backup
#   $2 - (optional) Backup name/label
# Returns:
#   0 on success, non-zero on failure
rollback_backup_file() {
  local file="${1}"
  local label="${2:-$(date +%Y%m%d-%H%M%S)}"

  if [[ ! -f "${file}" ]]; then
    log_warning "File does not exist, nothing to backup: ${file}"
    return 0
  fi

  local backup_dir="${ROLLBACK_DIR}/files"
  mkdir -p "${backup_dir}"

  local filename
  filename=$(basename "${file}")
  local backup_path="${backup_dir}/${filename}.${label}.bak"

  if cp "${file}" "${backup_path}"; then
    log_success "Backed up: ${file} -> ${backup_path}"
    return 0
  fi

  log_error "Failed to backup file: ${file}"
  return 1
}

# Backup a directory
# Arguments:
#   $1 - Directory path to backup
#   $2 - (optional) Backup name/label
# Returns:
#   0 on success, non-zero on failure
rollback_backup_directory() {
  local dir="${1}"
  local label="${2:-$(date +%Y%m%d-%H%M%S)}"

  if [[ ! -d "${dir}" ]]; then
    log_warning "Directory does not exist, nothing to backup: ${dir}"
    return 0
  fi

  local backup_dir="${ROLLBACK_DIR}/directories"
  mkdir -p "${backup_dir}"

  local dirname
  dirname=$(echo "${dir}" | tr '/' '_')
  local backup_path="${backup_dir}/${dirname}.${label}.tar.gz"

  if tar czf "${backup_path}" "${dir}" 2>/dev/null; then
    log_success "Backed up: ${dir} -> ${backup_path}"
    return 0
  fi

  log_error "Failed to backup directory: ${dir}"
  return 1
}

# List available restore points
# Returns:
#   Prints list of restore points to stdout
rollback_list_restore_points() {
  local restore_points_dir="${ROLLBACK_DIR}/restore-points"

  if [[ ! -d "${restore_points_dir}" ]]; then
    log_info "No restore points found"
    return 0
  fi

  log_info "Available restore points:"
  for rp in "${restore_points_dir}"/*; do
    if [[ -d "${rp}" && -f "${rp}/metadata" ]]; then
      local name timestamp
      name=$(grep "^name=" "${rp}/metadata" | cut -d= -f2)
      timestamp=$(grep "^timestamp=" "${rp}/metadata" | cut -d= -f2)
      echo "  - ${name} (${timestamp}): ${rp}"
    fi
  done
}

# Restore from a restore point
# Arguments:
#   $1 - Restore point path or name pattern
#   $2 - (optional) What to restore: "all", "etc", "apt", "keyrings" (default: all)
# Returns:
#   0 on success, non-zero on failure
rollback_restore() {
  local restore_point="${1}"
  local what="${2:-all}"

  # Find restore point
  local restore_point_dir
  if [[ -d "${restore_point}" ]]; then
    restore_point_dir="${restore_point}"
  else
    # Try to find by name pattern
    restore_point_dir=$(find "${ROLLBACK_DIR}/restore-points" -maxdepth 1 -type d -name "${restore_point}*" | sort -r | head -1)
  fi

  if [[ -z "${restore_point_dir}" || ! -d "${restore_point_dir}" ]]; then
    log_error "Restore point not found: ${restore_point}"
    return 1
  fi

  log_warning "Restoring from: ${restore_point_dir}"
  log_warning "This will overwrite current system configuration!"

  case "${what}" in
    all)
      rollback_restore_etc "${restore_point_dir}"
      rollback_restore_apt "${restore_point_dir}"
      rollback_restore_keyrings "${restore_point_dir}"
      ;;
    etc)
      rollback_restore_etc "${restore_point_dir}"
      ;;
    apt)
      rollback_restore_apt "${restore_point_dir}"
      ;;
    keyrings)
      rollback_restore_keyrings "${restore_point_dir}"
      ;;
    *)
      log_error "Unknown restore target: ${what}"
      return 1
      ;;
  esac

  log_success "Restore completed from: ${restore_point_dir}"
}

# Internal: Restore /etc from restore point
rollback_restore_etc() {
  local restore_point_dir="${1}"
  local archive="${restore_point_dir}/etc.tar.gz"

  if [[ ! -f "${archive}" ]]; then
    log_warning "No /etc backup found in restore point"
    return 0
  fi

  log_info "Restoring /etc..."
  if tar xzf "${archive}" -C / 2>/dev/null; then
    log_success "Restored /etc"
    return 0
  fi

  log_error "Failed to restore /etc"
  return 1
}

# Internal: Restore APT sources from restore point
rollback_restore_apt() {
  local restore_point_dir="${1}"
  local archive="${restore_point_dir}/apt-sources.tar.gz"

  if [[ ! -f "${archive}" ]]; then
    log_warning "No APT sources backup found in restore point"
    return 0
  fi

  log_info "Restoring APT sources..."
  if tar xzf "${archive}" -C / 2>/dev/null; then
    log_success "Restored APT sources"
    apt-get update 2>/dev/null || true
    return 0
  fi

  log_error "Failed to restore APT sources"
  return 1
}

# Internal: Restore GPG keyrings from restore point
rollback_restore_keyrings() {
  local restore_point_dir="${1}"
  local archive="${restore_point_dir}/keyrings.tar.gz"

  if [[ ! -f "${archive}" ]]; then
    log_warning "No GPG keyrings backup found in restore point"
    return 0
  fi

  log_info "Restoring GPG keyrings..."
  if tar xzf "${archive}" -C / 2>/dev/null; then
    log_success "Restored GPG keyrings"
    return 0
  fi

  log_error "Failed to restore GPG keyrings"
  return 1
}

# Clean up old restore points
# Arguments:
#   $1 - Number of restore points to keep (default: 5)
# Returns:
#   0 on success
rollback_cleanup() {
  local keep="${1:-5}"
  local restore_points_dir="${ROLLBACK_DIR}/restore-points"

  if [[ ! -d "${restore_points_dir}" ]]; then
    return 0
  fi

  log_info "Cleaning up old restore points (keeping ${keep} most recent)..."

  local count=0
  while IFS= read -r -d '' entry; do
    local rp="${entry#* }"
    ((count++))
    if [[ ${count} -gt ${keep} ]]; then
      log_info "Removing old restore point: ${rp}"
      rm -rf "${rp}"
    fi
  done < <(find "${restore_points_dir}" -maxdepth 1 -mindepth 1 -type d -printf '%T@ %p\0' 2>/dev/null | sort -z -nr)

  log_success "Cleanup completed"
}
