#!/usr/bin/env bats
#
# dependencies.bats - Tests for dependencies.sh
#

load '../test_helper'

setup() {
  mock_logging
  load_lib "dependencies.sh"
}

command_exists() {
  [[ "$1" == "present" ]]
}

@test "require_commands succeeds when all commands exist" {
  run require_commands present
  [ "$status" -eq 0 ]
}

@test "require_commands fails when a command is missing" {
  run require_commands present missing
  [ "$status" -eq 1 ]
}

@test "require_any_command succeeds when any command exists" {
  run require_any_command missing present
  [ "$status" -eq 0 ]
}

@test "require_any_command fails when none exist" {
  run require_any_command missing another
  [ "$status" -eq 1 ]
}

@test "check_optional_commands returns count of missing commands" {
  run check_optional_commands present missing
  [ "$status" -eq 1 ]
}
