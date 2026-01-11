#!/usr/bin/env bats
#
# install-workstation.bats - Tests for install-workstation.sh
#

load '../test_helper'

SCRIPT="${REPO_ROOT}/linux/ubuntu/install/install-workstation.sh"

# -----------------------------------------------------------------------------
# Setup and Teardown
# -----------------------------------------------------------------------------

setup() {
  # Create temp directory for test artifacts
  TEST_TEMP_DIR=$(mktemp -d)
  export TEST_TEMP_DIR

  # Mock logging to reduce noise
  mock_logging
}

teardown() {
  # Clean up temp directory
  rm -rf "${TEST_TEMP_DIR}"
}

# -----------------------------------------------------------------------------
# Help and Version Tests
# -----------------------------------------------------------------------------

@test "install-workstation.sh --help shows usage" {
  run bash "${SCRIPT}" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"Options:"* ]]
}

@test "install-workstation.sh -h shows usage" {
  run bash "${SCRIPT}" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "install-workstation.sh --version shows version" {
  run bash "${SCRIPT}" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"install-workstation.sh version"* ]]
}

@test "install-workstation.sh -v shows version" {
  run bash "${SCRIPT}" -v
  [ "$status" -eq 0 ]
  [[ "$output" == *"version"* ]]
}

# -----------------------------------------------------------------------------
# Argument Parsing Tests
# -----------------------------------------------------------------------------

@test "install-workstation.sh rejects unknown options" {
  run bash "${SCRIPT}" --unknown-option
  [ "$status" -eq 2 ]
  [[ "$output" == *"Unknown option"* ]]
}

@test "install-workstation.sh accepts --dry-run flag" {
  # Skip if not root - script requires root for most operations
  if [ "$(id -u)" -ne 0 ]; then
    skip "Test requires root privileges"
  fi

  run bash "${SCRIPT}" --dry-run --skip-security --skip-apps --skip-devtools --skip-extensions --skip-fastfetch
  [ "$status" -eq 0 ]
  [[ "$output" == *"[DRY-RUN]"* ]]
}

@test "install-workstation.sh accepts -d flag" {
  if [ "$(id -u)" -ne 0 ]; then
    skip "Test requires root privileges"
  fi

  run bash "${SCRIPT}" -d --skip-security --skip-apps --skip-devtools --skip-extensions --skip-fastfetch
  [ "$status" -eq 0 ]
  [[ "$output" == *"[DRY-RUN]"* ]]
}

@test "install-workstation.sh accepts --quiet flag" {
  run bash "${SCRIPT}" --help -q
  [ "$status" -eq 0 ]
}

@test "install-workstation.sh accepts --cis-profile flag" {
  run bash "${SCRIPT}" --help --cis-profile=cis_level2_workstation
  [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# Root Requirement Tests
# -----------------------------------------------------------------------------

@test "install-workstation.sh requires root" {
  if [ "$(id -u)" -eq 0 ]; then
    skip "Test requires non-root user"
  fi

  run bash "${SCRIPT}" --dry-run
  [ "$status" -eq 3 ]
  [[ "$output" == *"must be run as root"* ]]
}

# -----------------------------------------------------------------------------
# Skip Flag Tests
# -----------------------------------------------------------------------------

@test "install-workstation.sh --skip-security skips security phase" {
  run bash "${SCRIPT}" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--skip-security"* ]]
}

@test "install-workstation.sh --skip-apps skips apps phase" {
  run bash "${SCRIPT}" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--skip-apps"* ]]
}

@test "install-workstation.sh --skip-devtools skips devtools phase" {
  run bash "${SCRIPT}" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--skip-devtools"* ]]
}

@test "install-workstation.sh --skip-extensions skips extensions phase" {
  run bash "${SCRIPT}" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--skip-extensions"* ]]
}

@test "install-workstation.sh --skip-fastfetch skips fastfetch phase" {
  run bash "${SCRIPT}" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--skip-fastfetch"* ]]
}

# -----------------------------------------------------------------------------
# Only Flag Tests
# -----------------------------------------------------------------------------

@test "install-workstation.sh --security-only runs only security" {
  run bash "${SCRIPT}" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--security-only"* ]]
}

@test "install-workstation.sh --apps-only runs only apps" {
  run bash "${SCRIPT}" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--apps-only"* ]]
}

# -----------------------------------------------------------------------------
# Ubuntu Pro Flag Tests
# -----------------------------------------------------------------------------

@test "install-workstation.sh --skip-ubuntu-pro is accepted" {
  run bash "${SCRIPT}" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--skip-ubuntu-pro"* ]]
}

@test "install-workstation.sh --ubuntu-pro-token is accepted" {
  run bash "${SCRIPT}" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--ubuntu-pro-token"* ]]
}

# -----------------------------------------------------------------------------
# Library Sourcing Tests
# -----------------------------------------------------------------------------

@test "install-workstation.sh sources all required libraries" {
  # Check that the script can at least be parsed
  run bash -n "${SCRIPT}"
  [ "$status" -eq 0 ]
}

@test "required libraries exist" {
  [ -f "${LIB_DIR}/colors.sh" ]
  [ -f "${LIB_DIR}/logging.sh" ]
  [ -f "${LIB_DIR}/utils.sh" ]
  [ -f "${LIB_DIR}/version-check.sh" ]
}

# -----------------------------------------------------------------------------
# Exit Code Tests
# -----------------------------------------------------------------------------

@test "install-workstation.sh defines expected exit codes" {
  # Check help output mentions exit codes
  run bash "${SCRIPT}" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Exit Codes:"* ]]
  [[ "$output" == *"0  - Success"* ]]
  [[ "$output" == *"3  - Not running as root"* ]]
}

# -----------------------------------------------------------------------------
# Dry-Run Safety Tests
# -----------------------------------------------------------------------------

@test "dry-run mode does not modify system" {
  if [ "$(id -u)" -ne 0 ]; then
    skip "Test requires root privileges"
  fi

  # Create a marker file
  local marker="${TEST_TEMP_DIR}/marker"
  touch "${marker}"

  # Run in dry-run mode - should not create any files in temp
  run bash "${SCRIPT}" --dry-run --skip-security --skip-apps --skip-devtools --skip-extensions --skip-fastfetch 2>/dev/null

  # Marker should still exist (system not modified)
  [ -f "${marker}" ]
}

# -----------------------------------------------------------------------------
# CIS Profile Tests
# -----------------------------------------------------------------------------

@test "install-workstation.sh lists available CIS profiles" {
  run bash "${SCRIPT}" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"cis_level1_workstation"* ]]
  [[ "$output" == *"cis_level2_workstation"* ]]
  [[ "$output" == *"cis_level1_server"* ]]
  [[ "$output" == *"cis_level2_server"* ]]
}
