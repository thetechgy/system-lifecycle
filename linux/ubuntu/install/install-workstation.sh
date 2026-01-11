#!/usr/bin/env bash
#
# install-workstation.sh - Ubuntu 24.04 LTS Workstation Installation Script
#
# Description:
#   Comprehensive installation script for new Ubuntu 24.04 LTS workstation builds.
#   Includes security hardening (CIS benchmarks via USG), application installation
#   (MS Edge, VS Code), GNOME extensions, and system configuration (fastfetch).
#
# Usage:
#   sudo ./install-workstation.sh [OPTIONS]
#
# Options:
#   -d, --dry-run              Preview changes without executing
#   -q, --quiet                Suppress non-essential output
#   --skip-security            Skip USG/CIS hardening
#   --skip-apps                Skip MS Edge and VS Code installation
#   --skip-extensions          Skip GNOME extension installation
#   --skip-fastfetch           Skip fastfetch installation
#   --security-only            Only run security hardening
#   --apps-only                Only install applications
#   --cis-profile=PROFILE      CIS profile (default: cis_level1_workstation)
#   --no-audit                 Skip audit, only apply fixes
#   -h, --help                 Display this help message
#   -v, --version              Display script version
#
# Available CIS Profiles:
#   cis_level1_workstation     CIS Level 1 Workstation (default, recommended)
#   cis_level2_workstation     CIS Level 2 Workstation (stricter)
#   cis_level1_server          CIS Level 1 Server
#   cis_level2_server          CIS Level 2 Server
#
# Exit Codes:
#   0  - Success
#   1  - General error
#   2  - Invalid arguments
#   3  - Not running as root
#   7  - USG/CIS hardening failed
#   8  - Application installation failed
#   9  - Extension installation failed
#   10 - Prerequisites check failed
#
# Author: Travis McDade
# License: MIT
# Version: 1.0.0

set -o errexit   # Exit on error
set -o nounset   # Exit on undefined variable
set -o pipefail  # Catch pipeline failures

# -----------------------------------------------------------------------------
# Script Configuration
# -----------------------------------------------------------------------------

SCRIPT_NAME="$(basename "${0}")"
readonly SCRIPT_NAME
readonly SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
readonly SCRIPT_DIR
readonly LIB_DIR="${SCRIPT_DIR}/../../lib"
readonly CONFIG_DIR="${SCRIPT_DIR}/configs"

# Default flags
DRY_RUN=false
# shellcheck disable=SC2034  # Used by logging.sh
QUIET=false
SKIP_SECURITY=false
SKIP_APPS=false
SKIP_EXTENSIONS=false
SKIP_FASTFETCH=false
SECURITY_ONLY=false
APPS_ONLY=false
CIS_PROFILE="cis_level1_workstation"
NO_AUDIT=false

# State tracking
REBOOT_REQUIRED=false
GNOME_AVAILABLE=false
GNOME_EXTENSIONS_INSTALLED=false

# -----------------------------------------------------------------------------
# Source Libraries
# -----------------------------------------------------------------------------

# shellcheck source=../../lib/colors.sh
source "${LIB_DIR}/colors.sh"

# shellcheck source=../../lib/logging.sh
source "${LIB_DIR}/logging.sh"

# shellcheck source=../../lib/utils.sh
source "${LIB_DIR}/utils.sh"

# shellcheck source=../../lib/version-check.sh
source "${LIB_DIR}/version-check.sh"

# -----------------------------------------------------------------------------
# Additional Exit Codes
# -----------------------------------------------------------------------------

readonly EXIT_USG_FAILED=7
readonly EXIT_APP_INSTALL_FAILED=8
readonly EXIT_EXTENSION_FAILED=9
readonly EXIT_PREREQ_FAILED=10

# -----------------------------------------------------------------------------
# Help and Version
# -----------------------------------------------------------------------------

show_usage() {
  cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Ubuntu 24.04 LTS Workstation Installation Script

Installs and configures:
  - Ubuntu Security Guide (USG) with CIS benchmarks
  - Microsoft Edge and Visual Studio Code
  - GNOME dash-to-panel extension
  - Fastfetch system information tool

Options:
    -d, --dry-run              Preview changes without executing
    -q, --quiet                Suppress non-essential output
    --skip-security            Skip USG/CIS hardening
    --skip-apps                Skip MS Edge and VS Code installation
    --skip-extensions          Skip GNOME extension installation
    --skip-fastfetch           Skip fastfetch installation
    --security-only            Only run security hardening
    --apps-only                Only install applications
    --cis-profile=PROFILE      CIS profile (default: cis_level1_workstation)
    --no-audit                 Skip audit, only apply fixes
    -h, --help                 Display this help message
    -v, --version              Display script version

Available CIS Profiles:
    cis_level1_workstation     CIS Level 1 Workstation (default, recommended)
    cis_level2_workstation     CIS Level 2 Workstation (stricter)
    cis_level1_server          CIS Level 1 Server
    cis_level2_server          CIS Level 2 Server

Examples:
    sudo ${SCRIPT_NAME}                      # Full installation
    sudo ${SCRIPT_NAME} --dry-run            # Preview changes
    sudo ${SCRIPT_NAME} --skip-security      # Skip CIS hardening
    sudo ${SCRIPT_NAME} --security-only      # Only run CIS hardening
    sudo ${SCRIPT_NAME} --apps-only          # Only install Edge and VS Code

Exit Codes:
    0  - Success
    1  - General error
    2  - Invalid arguments
    3  - Not running as root
    7  - USG/CIS hardening failed
    8  - Application installation failed
    9  - Extension installation failed
    10 - Prerequisites check failed
EOF
}

show_version() {
  printf "%s version %s\n" "${SCRIPT_NAME}" "${SCRIPT_VERSION}"
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
      -q|--quiet)
        # shellcheck disable=SC2034  # Used by logging.sh
        QUIET=true
        shift
        ;;
      --skip-security)
        SKIP_SECURITY=true
        shift
        ;;
      --skip-apps)
        SKIP_APPS=true
        shift
        ;;
      --skip-extensions)
        SKIP_EXTENSIONS=true
        shift
        ;;
      --skip-fastfetch)
        SKIP_FASTFETCH=true
        shift
        ;;
      --security-only)
        SECURITY_ONLY=true
        shift
        ;;
      --apps-only)
        APPS_ONLY=true
        shift
        ;;
      --cis-profile=*)
        CIS_PROFILE="${1#*=}"
        shift
        ;;
      --no-audit)
        NO_AUDIT=true
        shift
        ;;
      -h|--help)
        show_usage
        exit "${EXIT_SUCCESS}"
        ;;
      -v|--version)
        show_version
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
# Cleanup Handler
# -----------------------------------------------------------------------------

cleanup() {
  local exit_code=$?

  if [[ ${exit_code} -eq 0 ]]; then
    log_success "Workstation installation completed successfully"
  else
    log_error "Workstation installation failed with exit code ${exit_code}"
  fi

  if [[ -n "${LOG_FILE:-}" ]]; then
    log_info "Log saved to: ${LOG_FILE}"
  fi
}

trap cleanup EXIT

# -----------------------------------------------------------------------------
# Prerequisites Check
# -----------------------------------------------------------------------------

check_prerequisites() {
  section "Checking Prerequisites"

  # Verify Ubuntu 24.04 LTS
  log_info "Checking Ubuntu version..."
  local ubuntu_version
  ubuntu_version=$(lsb_release -rs 2>/dev/null || echo "unknown")

  if [[ "${ubuntu_version}" != "24.04" ]]; then
    log_error "This script requires Ubuntu 24.04 LTS (found: ${ubuntu_version})"
    return "${EXIT_PREREQ_FAILED}"
  fi
  log_success "Ubuntu 24.04 LTS detected"

  # Check internet connectivity
  log_info "Checking internet connectivity..."
  if ping -c1 -W2 8.8.8.8 &>/dev/null; then
    log_success "Internet connectivity verified"
  else
    log_error "No internet connectivity - required for package installation"
    return "${EXIT_PREREQ_FAILED}"
  fi

  # Check if running in WSL
  if grep -qi microsoft /proc/version 2>/dev/null; then
    log_warning "WSL detected - CIS hardening will be skipped (not applicable in virtualized environment)"
    SKIP_SECURITY=true
  fi

  # Check GNOME Shell
  if pgrep -x gnome-shell >/dev/null 2>&1; then
    GNOME_AVAILABLE=true
    local gnome_version
    gnome_version=$(gnome-shell --version 2>/dev/null | grep -oP '\d+\.\d+' || echo "unknown")
    log_success "GNOME Shell ${gnome_version} detected"
  else
    log_warning "GNOME Shell not running - extension installation will be skipped"
    SKIP_EXTENSIONS=true
  fi

  log_success "Prerequisites check completed"
}

# -----------------------------------------------------------------------------
# USG/CIS Functions
# -----------------------------------------------------------------------------

usg_install() {
  section "Installing Ubuntu Security Guide"

  # Check if USG is already installed
  if dpkg -l | grep -q "^ii.*usg "; then
    log_success "Ubuntu Security Guide is already installed"
    return 0
  fi

  if [[ "${DRY_RUN}" == true ]]; then
    log_info "[DRY-RUN] Would install Ubuntu Security Guide (USG)"
    log_info "[DRY-RUN] Would enable Ubuntu Pro (if needed)"
    return 0
  fi

  log_info "Installing Ubuntu Security Guide..."
  log_warning "Note: USG requires Ubuntu Pro subscription"

  # Check if Ubuntu Pro is enabled
  if ! command_exists pro; then
    log_error "ubuntu-advantage-tools not found - cannot enable Ubuntu Pro"
    return "${EXIT_USG_FAILED}"
  fi

  # Enable USG service
  log_info "Enabling USG via Ubuntu Pro..."
  if pro enable usg 2>&1 | tee -a "${LOG_FILE}"; then
    log_success "Ubuntu Pro USG service enabled"
  else
    log_error "Failed to enable USG service - ensure Ubuntu Pro is attached"
    log_info "Run: sudo pro attach <token>"
    return "${EXIT_USG_FAILED}"
  fi

  # Verify installation
  if [[ -x "/usr/sbin/usg" ]]; then
    local usg_version
    usg_version=$(/usr/sbin/usg --version 2>/dev/null || echo "unknown")
    log_success "Ubuntu Security Guide installed successfully (${usg_version})"
  else
    log_error "USG installation verification failed"
    return "${EXIT_USG_FAILED}"
  fi
}

usg_audit() {
  if [[ "${NO_AUDIT}" == true ]]; then
    log_info "Skipping CIS audit (--no-audit flag set)"
    return 0
  fi

  section "Running CIS Compliance Audit"

  if [[ "${DRY_RUN}" == true ]]; then
    log_info "[DRY-RUN] Would run: /usr/sbin/usg audit ${CIS_PROFILE}"
    return 0
  fi

  log_info "Running audit for profile: ${CIS_PROFILE}"
  log_info "This may take several minutes..."

  if /usr/sbin/usg audit "${CIS_PROFILE}" 2>&1 | tee -a "${LOG_FILE}"; then
    log_success "CIS compliance audit completed"
    log_info "Reports available in: /var/lib/usg/reports/"

    # Find and display latest report
    local latest_report
    latest_report=$(find /var/lib/usg/reports/ -name "*.html" -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
    if [[ -n "${latest_report}" ]]; then
      log_info "Latest report: ${latest_report}"
    fi
  else
    log_warning "CIS audit completed with warnings (non-critical)"
  fi
}

usg_fix() {
  section "Applying CIS Benchmark Hardening"

  if [[ "${DRY_RUN}" == true ]]; then
    log_info "[DRY-RUN] Would run: /usr/sbin/usg fix ${CIS_PROFILE}"
    log_info "[DRY-RUN] Would create backup of /etc directory"
    return 0
  fi

  # Create backup of /etc directory
  log_info "Creating backup of /etc directory..."
  local backup_dir="/var/backups/system-lifecycle"
  local timestamp
  timestamp=$(date +%Y%m%d-%H%M%S)

  mkdir -p "${backup_dir}"
  if tar czf "${backup_dir}/etc-backup-${timestamp}.tar.gz" /etc/ 2>&1 | tee -a "${LOG_FILE}"; then
    log_success "Backup created: ${backup_dir}/etc-backup-${timestamp}.tar.gz"
  else
    log_warning "Backup creation had issues (non-critical)"
  fi

  # Apply CIS hardening
  log_info "Applying CIS hardening for profile: ${CIS_PROFILE}"
  log_warning "This will modify system security settings"

  local fix_cmd="/usr/sbin/usg fix ${CIS_PROFILE}"
  if [[ "${NO_AUDIT}" == false ]]; then
    fix_cmd="${fix_cmd} --only-failed"
    log_info "Using --only-failed to remediate only failing controls"
  fi

  if ${fix_cmd} 2>&1 | tee -a "${LOG_FILE}"; then
    log_success "CIS hardening applied successfully"
    REBOOT_REQUIRED=true
  else
    log_error "CIS hardening failed"
    return "${EXIT_USG_FAILED}"
  fi
}

# -----------------------------------------------------------------------------
# Microsoft Applications Functions
# -----------------------------------------------------------------------------

setup_microsoft_gpg() {
  local gpg_key="/usr/share/keyrings/microsoft.gpg"

  if [[ -f "${gpg_key}" ]]; then
    log_info "Microsoft GPG key already installed"
    return 0
  fi

  if [[ "${DRY_RUN}" == true ]]; then
    log_info "[DRY-RUN] Would download and install Microsoft GPG key"
    return 0
  fi

  log_info "Installing Microsoft GPG signing key..."

  if curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/microsoft.gpg 2>&1 | tee -a "${LOG_FILE}"; then
    install -D -o root -g root -m 644 /tmp/microsoft.gpg "${gpg_key}"
    rm -f /tmp/microsoft.gpg
    log_success "Microsoft GPG key installed"
  else
    log_error "Failed to install Microsoft GPG key"
    return "${EXIT_APP_INSTALL_FAILED}"
  fi
}

install_edge() {
  section "Installing Microsoft Edge"

  # Check if already installed
  if dpkg -l | grep -q "^ii.*microsoft-edge-stable "; then
    local edge_version
    edge_version=$(microsoft-edge --version 2>/dev/null || echo "unknown")
    log_success "Microsoft Edge is already installed (${edge_version})"
    return 0
  fi

  if [[ "${DRY_RUN}" == true ]]; then
    log_info "[DRY-RUN] Would install Microsoft Edge"
    log_info "[DRY-RUN] Would create repository configuration"
    return 0
  fi

  # Setup GPG key
  setup_microsoft_gpg || return "${EXIT_APP_INSTALL_FAILED}"

  # Create repository configuration (DEB822 format)
  log_info "Creating Microsoft Edge repository configuration..."
  local repo_file="/etc/apt/sources.list.d/microsoft-edge.sources"

  cat > "${repo_file}" << EOF
Types: deb
URIs: https://packages.microsoft.com/repos/edge
Suites: stable
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/microsoft.gpg
EOF

  log_success "Repository configuration created"

  # Update package lists
  log_info "Updating package lists..."
  if apt-get update 2>&1 | tee -a "${LOG_FILE}"; then
    log_success "Package lists updated"
  else
    log_error "Failed to update package lists"
    return "${EXIT_APP_INSTALL_FAILED}"
  fi

  # Install Microsoft Edge
  log_info "Installing Microsoft Edge..."
  if DEBIAN_FRONTEND=noninteractive apt-get install -y microsoft-edge-stable 2>&1 | tee -a "${LOG_FILE}"; then
    local edge_version
    edge_version=$(microsoft-edge --version 2>/dev/null || echo "unknown")
    log_success "Microsoft Edge installed successfully (${edge_version})"
  else
    log_error "Failed to install Microsoft Edge"
    return "${EXIT_APP_INSTALL_FAILED}"
  fi
}

install_vscode() {
  section "Installing Visual Studio Code"

  # Check if already installed
  if dpkg -l | grep -q "^ii.*code "; then
    local code_version
    code_version=$(code --version 2>/dev/null | head -1 || echo "unknown")
    log_success "Visual Studio Code is already installed (${code_version})"
    return 0
  fi

  if [[ "${DRY_RUN}" == true ]]; then
    log_info "[DRY-RUN] Would install Visual Studio Code"
    log_info "[DRY-RUN] Would create repository configuration"
    return 0
  fi

  # Setup GPG key
  setup_microsoft_gpg || return "${EXIT_APP_INSTALL_FAILED}"

  # Create repository configuration (DEB822 format)
  log_info "Creating VS Code repository configuration..."
  local repo_file="/etc/apt/sources.list.d/vscode.sources"

  cat > "${repo_file}" << EOF
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/microsoft.gpg
EOF

  log_success "Repository configuration created"

  # Update package lists
  log_info "Updating package lists..."
  if apt-get update 2>&1 | tee -a "${LOG_FILE}"; then
    log_success "Package lists updated"
  else
    log_error "Failed to update package lists"
    return "${EXIT_APP_INSTALL_FAILED}"
  fi

  # Install VS Code
  log_info "Installing Visual Studio Code..."
  if DEBIAN_FRONTEND=noninteractive apt-get install -y code 2>&1 | tee -a "${LOG_FILE}"; then
    local code_version
    code_version=$(code --version 2>/dev/null | head -1 || echo "unknown")
    log_success "Visual Studio Code installed successfully (${code_version})"
  else
    log_error "Failed to install Visual Studio Code"
    return "${EXIT_APP_INSTALL_FAILED}"
  fi
}

# -----------------------------------------------------------------------------
# GNOME Extension Functions
# -----------------------------------------------------------------------------

install_dash_to_panel() {
  section "Installing GNOME Dash to Panel Extension"

  if [[ "${GNOME_AVAILABLE}" != true ]]; then
    log_warning "GNOME Shell not available - skipping extension installation"
    return 0
  fi

  # Check if already installed
  if dpkg -l | grep -q "^ii.*gnome-shell-extension-dash-to-panel "; then
    log_success "Dash to Panel extension is already installed"
    GNOME_EXTENSIONS_INSTALLED=true
    return 0
  fi

  if [[ "${DRY_RUN}" == true ]]; then
    log_info "[DRY-RUN] Would install gnome-shell-extension-dash-to-panel"
    return 0
  fi

  # Install extension via apt
  log_info "Installing dash-to-panel extension..."
  if DEBIAN_FRONTEND=noninteractive apt-get install -y gnome-shell-extension-dash-to-panel 2>&1 | tee -a "${LOG_FILE}"; then
    log_success "Dash to Panel extension installed successfully"
    GNOME_EXTENSIONS_INSTALLED=true
    log_info "To enable the extension, run:"
    log_info "  gnome-extensions enable dash-to-panel@jderose9.github.com"
    log_info "Or enable it via the Extensions application"
    log_warning "Note: You may need to logout/login for the extension to be available"
  else
    log_error "Failed to install dash-to-panel extension"
    return "${EXIT_EXTENSION_FAILED}"
  fi
}

# -----------------------------------------------------------------------------
# Fastfetch Functions
# -----------------------------------------------------------------------------

install_fastfetch() {
  section "Installing Fastfetch"

  # Check if already installed
  if command_exists fastfetch; then
    local fastfetch_version
    fastfetch_version=$(fastfetch --version 2>/dev/null | head -1 || echo "unknown")
    log_success "Fastfetch is already installed (${fastfetch_version})"
    return 0
  fi

  if [[ "${DRY_RUN}" == true ]]; then
    log_info "[DRY-RUN] Would install fastfetch"
    return 0
  fi

  # Install fastfetch
  log_info "Installing fastfetch..."
  if DEBIAN_FRONTEND=noninteractive apt-get install -y fastfetch 2>&1 | tee -a "${LOG_FILE}"; then
    local fastfetch_version
    fastfetch_version=$(fastfetch --version 2>/dev/null | head -1 || echo "unknown")
    log_success "Fastfetch installed successfully (${fastfetch_version})"
  else
    log_error "Failed to install fastfetch"
    return "${EXIT_ERROR}"
  fi
}

configure_fastfetch() {
  section "Configuring Fastfetch"

  local config_src="${CONFIG_DIR}/fastfetch.jsonc"
  local config_dest="${HOME}/.config/fastfetch/config.jsonc"
  local config_dir="${HOME}/.config/fastfetch"

  if [[ ! -f "${config_src}" ]]; then
    log_warning "Fastfetch config template not found: ${config_src}"
    log_info "Skipping fastfetch configuration"
    return 0
  fi

  if [[ "${DRY_RUN}" == true ]]; then
    log_info "[DRY-RUN] Would create directory: ${config_dir}"
    log_info "[DRY-RUN] Would copy config: ${config_src} -> ${config_dest}"
    return 0
  fi

  # Create config directory
  log_info "Creating fastfetch config directory..."
  mkdir -p "${config_dir}"

  # Backup existing config if present
  if [[ -f "${config_dest}" ]]; then
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local backup="${config_dest}.bak.${timestamp}"
    log_info "Backing up existing config to: ${backup}"
    cp "${config_dest}" "${backup}"
  fi

  # Copy configuration
  log_info "Deploying fastfetch configuration..."
  if cp "${config_src}" "${config_dest}"; then
    chmod 644 "${config_dest}"
    log_success "Fastfetch configuration deployed"

    # Test fastfetch
    log_info "Testing fastfetch configuration..."
    if fastfetch 2>&1 | tee -a "${LOG_FILE}"; then
      log_success "Fastfetch is working correctly"
    else
      log_warning "Fastfetch test had issues (non-critical)"
    fi
  else
    log_error "Failed to deploy fastfetch configuration"
    return "${EXIT_ERROR}"
  fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
  check_for_updates
  parse_args "$@"
  check_root
  init_logging "install-workstation"

  log_info "Starting workstation installation..."
  log_info "Dry-run mode: ${DRY_RUN}"
  log_info "Skip security: ${SKIP_SECURITY}"
  log_info "Skip apps: ${SKIP_APPS}"
  log_info "Skip extensions: ${SKIP_EXTENSIONS}"
  log_info "Skip fastfetch: ${SKIP_FASTFETCH}"
  log_info "Security only: ${SECURITY_ONLY}"
  log_info "Apps only: ${APPS_ONLY}"
  log_info "CIS profile: ${CIS_PROFILE}"
  log_info "No audit: ${NO_AUDIT}"

  section "System Information"
  show_system_info
  check_prerequisites

  # Execution based on flags
  if [[ "${SECURITY_ONLY}" == true ]]; then
    # Security hardening only
    usg_install
    usg_audit
    usg_fix
  elif [[ "${APPS_ONLY}" == true ]]; then
    # Applications only
    setup_microsoft_gpg
    install_edge
    install_vscode
  else
    # Full installation

    # Phase 1: Security hardening (unless --skip-security)
    if [[ "${SKIP_SECURITY}" != true ]]; then
      usg_install
      usg_audit
      usg_fix
    fi

    # Phase 2: Applications (unless --skip-apps)
    if [[ "${SKIP_APPS}" != true ]]; then
      setup_microsoft_gpg
      install_edge
      install_vscode
    fi

    # Phase 3: GNOME extensions (unless --skip-extensions)
    if [[ "${SKIP_EXTENSIONS}" != true ]]; then
      install_dash_to_panel
    fi

    # Phase 4: Fastfetch (unless --skip-fastfetch)
    if [[ "${SKIP_FASTFETCH}" != true ]]; then
      install_fastfetch
      configure_fastfetch
    fi
  fi

  section "Installation Complete"

  # Display summary
  log_success "Workstation setup completed successfully"

  # Post-installation instructions
  if [[ "${REBOOT_REQUIRED}" == true ]] || reboot_required; then
    log_warning "╔════════════════════════════════════════════════════╗"
    log_warning "║  SYSTEM REBOOT REQUIRED                            ║"
    log_warning "║  CIS hardening requires a reboot to take effect    ║"
    log_warning "║  Please reboot your system when convenient         ║"
    log_warning "╚════════════════════════════════════════════════════╝"
  fi

  if [[ "${GNOME_EXTENSIONS_INSTALLED}" == true ]]; then
    log_info ""
    log_info "To enable GNOME extensions:"
    log_info "  Option 1: Open Extensions application"
    log_info "  Option 2: Run: gnome-extensions enable dash-to-panel@jderose9.github.com"
    log_info "  Note: You may need to logout/login first"
  fi

  if command_exists fastfetch && [[ "${SKIP_FASTFETCH}" != true ]]; then
    log_info ""
    log_info "Test fastfetch by running: fastfetch"
  fi
}

main "$@"
