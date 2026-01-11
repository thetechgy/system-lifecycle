#!/usr/bin/env bats
#
# progress.bats - Tests for progress.sh
#

load '../test_helper'

setup() {
  load_lib "progress.sh"
}

@test "format_duration formats seconds" {
  run format_duration 45
  [ "$status" -eq 0 ]
  [ "$output" = "45s" ]
}

@test "format_duration formats minutes and seconds" {
  run format_duration 125
  [ "$status" -eq 0 ]
  [ "$output" = "2m 5s" ]
}

@test "format_duration formats hours and minutes" {
  run format_duration 3661
  [ "$status" -eq 0 ]
  [ "$output" = "1h 1m" ]
}
