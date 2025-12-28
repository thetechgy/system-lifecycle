#!/usr/bin/env bats
#
# Tests for linux/lib/utils.sh
#

load '../test_helper'

setup() {
  mock_logging
  load_lib "utils.sh"
}

# -----------------------------------------------------------------------------
# command_exists tests
# -----------------------------------------------------------------------------

@test "command_exists returns 0 for bash" {
  run command_exists bash
  [ "$status" -eq 0 ]
}

@test "command_exists returns 0 for ls" {
  run command_exists ls
  [ "$status" -eq 0 ]
}

@test "command_exists returns 1 for nonexistent command" {
  run command_exists this_command_does_not_exist_xyz123
  [ "$status" -eq 1 ]
}

# -----------------------------------------------------------------------------
# Exit code constants tests
# -----------------------------------------------------------------------------

@test "EXIT_SUCCESS is defined as 0" {
  [ "$EXIT_SUCCESS" -eq 0 ]
}

@test "EXIT_ERROR is defined as 1" {
  [ "$EXIT_ERROR" -eq 1 ]
}

@test "EXIT_INVALID_ARGS is defined as 2" {
  [ "$EXIT_INVALID_ARGS" -eq 2 ]
}

@test "EXIT_NOT_ROOT is defined as 3" {
  [ "$EXIT_NOT_ROOT" -eq 3 ]
}

@test "EXIT_APT_UPDATE_FAILED is defined as 4" {
  [ "$EXIT_APT_UPDATE_FAILED" -eq 4 ]
}

@test "EXIT_APT_UPGRADE_FAILED is defined as 5" {
  [ "$EXIT_APT_UPGRADE_FAILED" -eq 5 ]
}

@test "EXIT_NPM_UPDATE_FAILED is defined as 6" {
  [ "$EXIT_NPM_UPDATE_FAILED" -eq 6 ]
}

# -----------------------------------------------------------------------------
# reboot_required tests
# -----------------------------------------------------------------------------

@test "reboot_required returns 1 when file does not exist" {
  run reboot_required
  [ "$status" -eq 1 ]
}
