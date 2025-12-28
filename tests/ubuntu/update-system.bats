#!/usr/bin/env bats
#
# Tests for linux/ubuntu/update/update-system.sh
#

load '../test_helper'

UPDATE_SCRIPT="${REPO_ROOT}/linux/ubuntu/update/update-system.sh"

# -----------------------------------------------------------------------------
# Help and version tests
# -----------------------------------------------------------------------------

@test "--help shows usage and exits 0" {
  run bash "$UPDATE_SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"--dry-run"* ]]
}

@test "-h shows usage and exits 0" {
  run bash "$UPDATE_SCRIPT" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "--version shows version and exits 0" {
  run bash "$UPDATE_SCRIPT" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"update-system.sh version"* ]]
}

@test "-v shows version and exits 0" {
  run bash "$UPDATE_SCRIPT" -v
  [ "$status" -eq 0 ]
  [[ "$output" == *"version"* ]]
}

# -----------------------------------------------------------------------------
# Argument parsing tests
# -----------------------------------------------------------------------------

@test "unknown flag exits with code 2" {
  run bash "$UPDATE_SCRIPT" --unknown-flag
  [ "$status" -eq 2 ]
}

@test "unexpected argument exits with code 2" {
  run bash "$UPDATE_SCRIPT" unexpected_arg
  [ "$status" -eq 2 ]
}

# -----------------------------------------------------------------------------
# Root requirement tests
# -----------------------------------------------------------------------------

@test "script requires root (exits 3 without sudo)" {
  # Skip if already running as root
  if [ "$EUID" -eq 0 ]; then
    skip "Test must run as non-root user"
  fi

  run bash "$UPDATE_SCRIPT" --dry-run
  [ "$status" -eq 3 ]
  [[ "$output" == *"root"* ]] || [[ "$output" == *"sudo"* ]]
}
