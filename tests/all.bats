#!/usr/bin/env bats
#
# all.bats - Run all Bats suites in subdirectories
#

load './test_helper'

@test "run all subdirectory test suites" {
  run bats "${REPO_ROOT}/tests/lib" "${REPO_ROOT}/tests/ubuntu"
  [ "$status" -eq 0 ]
}
