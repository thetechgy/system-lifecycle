#!/usr/bin/env bats
#
# all.bats - Run all Bats suites in subdirectories
#

load './test_helper'

@test "run all subdirectory test suites" {
  run bats "${REPO_ROOT}/tests/lib" "${REPO_ROOT}/tests/ansible"
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}
