#!/usr/bin/env bats
#
# Tests for linux/lib/logging.sh
#

load '../test_helper'

setup() {
  load_lib "colors.sh"
  load_lib "logging.sh"
}

@test "log_info writes INFO messages to a log file" {
  LOG_FILE="${BATS_TEST_TMPDIR}/system-lifecycle.log"
  QUIET=true

  run log_info "hello"

  [ "$status" -eq 0 ]
  [ -f "${LOG_FILE}" ]
  grep -q "\\[INFO\\] hello" "${LOG_FILE}"
}

@test "section writes section marker to a log file" {
  LOG_FILE="${BATS_TEST_TMPDIR}/system-lifecycle.log"
  QUIET=true

  run section "Test Section"

  [ "$status" -eq 0 ]
  grep -q "\\[INFO\\] === Test Section ===" "${LOG_FILE}"
}
