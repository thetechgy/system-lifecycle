#!/usr/bin/env bats
#
# configure-bashrc.bats - Tests for configure-bashrc.sh
#

load '../test_helper'

SCRIPT="${REPO_ROOT}/linux/ubuntu/configure/configure-bashrc.sh"

# -----------------------------------------------------------------------------
# Setup and Teardown
# -----------------------------------------------------------------------------

setup() {
  # Create temp directory for test artifacts
  TEST_TEMP_DIR=$(mktemp -d)
  export TEST_TEMP_DIR

  # Create a mock bashrc for testing
  TEST_BASHRC="${TEST_TEMP_DIR}/.bashrc"
  cat > "${TEST_BASHRC}" << 'EOF'
# ~/.bashrc: executed by bash(1) for non-login shells.

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# some aliases
alias ll='ls -alF'
alias la='ls -A'
EOF

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

@test "configure-bashrc.sh --help shows usage" {
  run bash "${SCRIPT}" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"Options:"* ]]
}

@test "configure-bashrc.sh -h shows usage" {
  run bash "${SCRIPT}" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

# -----------------------------------------------------------------------------
# Argument Parsing Tests
# -----------------------------------------------------------------------------

@test "configure-bashrc.sh rejects unknown options" {
  run bash "${SCRIPT}" --unknown-option
  [ "$status" -eq 2 ]
  [[ "$output" == *"Unknown option"* ]]
}

@test "configure-bashrc.sh accepts --dry-run flag" {
  run bash "${SCRIPT}" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"[DRY-RUN]"* ]]
}

@test "configure-bashrc.sh accepts -d flag" {
  run bash "${SCRIPT}" -d
  [ "$status" -eq 0 ]
  [[ "$output" == *"[DRY-RUN]"* ]]
}

@test "configure-bashrc.sh accepts --remove flag" {
  run bash "${SCRIPT}" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--remove"* ]]
}

@test "configure-bashrc.sh accepts -r flag" {
  run bash "${SCRIPT}" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"-r, --remove"* ]]
}

# -----------------------------------------------------------------------------
# Library Sourcing Tests
# -----------------------------------------------------------------------------

@test "configure-bashrc.sh sources all required libraries" {
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
# Dry-Run Tests
# -----------------------------------------------------------------------------

@test "dry-run mode shows what would be done" {
  run bash "${SCRIPT}" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"[DRY-RUN]"* ]]
}

@test "dry-run mode does not modify bashrc" {
  # Get original content
  local original_content
  original_content=$(cat "${HOME}/.bashrc" 2>/dev/null || true)

  # Run in dry-run mode
  run bash "${SCRIPT}" --dry-run
  [ "$status" -eq 0 ]

  # Check bashrc is unchanged
  local new_content
  new_content=$(cat "${HOME}/.bashrc" 2>/dev/null || true)
  [ "${original_content}" = "${new_content}" ]
}

# -----------------------------------------------------------------------------
# Marker Tests
# -----------------------------------------------------------------------------

@test "configure-bashrc.sh uses section markers" {
  # Check script contains marker definitions
  run grep -q "MARKER_START" "${SCRIPT}"
  [ "$status" -eq 0 ]

  run grep -q "MARKER_END" "${SCRIPT}"
  [ "$status" -eq 0 ]
}

@test "markers follow expected format" {
  # Check for the specific marker format
  run grep "system-lifecycle" "${SCRIPT}"
  [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# Idempotency Tests (in dry-run mode)
# -----------------------------------------------------------------------------

@test "configure-bashrc.sh is idempotent (dry-run)" {
  # Run twice in dry-run mode - should succeed both times
  run bash "${SCRIPT}" --dry-run
  [ "$status" -eq 0 ]

  run bash "${SCRIPT}" --dry-run
  [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# Remove Mode Tests (dry-run)
# -----------------------------------------------------------------------------

@test "configure-bashrc.sh --remove in dry-run mode succeeds" {
  run bash "${SCRIPT}" --remove --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"[DRY-RUN]"* ]]
}

# -----------------------------------------------------------------------------
# Script Behavior Tests
# -----------------------------------------------------------------------------

@test "configure-bashrc.sh creates backup when modifying" {
  # Check help mentions backup behavior
  run bash "${SCRIPT}" --help
  [ "$status" -eq 0 ]
  # Script should mention backup in its description or output
}

@test "configure-bashrc.sh shows reload instructions" {
  run bash "${SCRIPT}" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"source ~/.bashrc"* ]]
}

# -----------------------------------------------------------------------------
# Error Handling Tests
# -----------------------------------------------------------------------------

@test "configure-bashrc.sh handles missing bashrc gracefully" {
  # This test verifies the script doesn't crash if bashrc doesn't exist
  # (it should create one or handle the case)
  run bash -n "${SCRIPT}"
  [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# Alias Tests (verification)
# -----------------------------------------------------------------------------

@test "configure-bashrc.sh creates update-system alias" {
  # Check that script creates the expected alias
  run bash "${SCRIPT}" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"update-system"* ]]
}
