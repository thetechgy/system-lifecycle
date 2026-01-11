#!/usr/bin/env bats
#
# Tests for linux/lib/colors.sh
#

load '../test_helper'

setup() {
  load_lib "colors.sh"
}

# -----------------------------------------------------------------------------
# Color variable tests
# -----------------------------------------------------------------------------

@test "RED is defined" {
  [[ -v RED ]]
}

@test "GREEN is defined" {
  [[ -v GREEN ]]
}

@test "YELLOW is defined" {
  [[ -v YELLOW ]]
}

@test "BLUE is defined" {
  [[ -v BLUE ]]
}

@test "NC (no color) is defined" {
  [[ -v NC ]]
}

@test "BOLD is defined" {
  [[ -v BOLD ]]
}
