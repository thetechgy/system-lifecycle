#!/usr/bin/env bats
#
# Tests for linux/lib/version-check.sh
#

load '../test_helper'

setup() {
  load_lib "colors.sh"
  load_lib "version-check.sh"
}

# -----------------------------------------------------------------------------
# check_for_updates tests
# -----------------------------------------------------------------------------

@test "check_for_updates returns 0 (never fails)" {
  run check_for_updates
  [ "$status" -eq 0 ]
}

@test "check_for_updates succeeds when git is not installed" {
  # Temporarily hide git
  PATH="" run check_for_updates
  [ "$status" -eq 0 ]
}

@test "_get_repo_root returns a valid path" {
  run _get_repo_root
  [ "$status" -eq 0 ]
  [ -d "$output" ]
}

@test "_get_repo_root points to repository root" {
  run _get_repo_root
  [ "$status" -eq 0 ]
  # Should contain the linux directory
  [ -d "${output}/linux" ]
}
