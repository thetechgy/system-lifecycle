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
  [ -n "$RED" ]
}

@test "GREEN is defined" {
  [ -n "$GREEN" ]
}

@test "YELLOW is defined" {
  [ -n "$YELLOW" ]
}

@test "BLUE is defined" {
  [ -n "$BLUE" ]
}

@test "NC (no color) is defined" {
  [ -n "$NC" ]
}

@test "BOLD is defined" {
  [ -n "$BOLD" ]
}
