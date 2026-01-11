#!/usr/bin/env bats
#
# repositories.bats - Tests for repositories.sh
#

load '../test_helper'

setup() {
  mock_logging
  load_lib "repositories.sh"
}

@test "repo_add_deb822 rejects invalid repository name" {
  run repo_add_deb822 "bad name" "https://example.com/repo" "/nope"
  [ "$status" -eq 1 ]
}

@test "repo_add_deb822 rejects invalid URI" {
  run repo_add_deb822 "goodname" "ftp://example.com/repo" "/nope"
  [ "$status" -eq 1 ]
}

@test "repo_add_deb822 rejects missing keyring" {
  run repo_add_deb822 "goodname" "https://example.com/repo" "/nope"
  [ "$status" -eq 1 ]
}

@test "repo_add_traditional rejects invalid repository name" {
  run repo_add_traditional "bad name" "deb http://example.com focal main"
  [ "$status" -eq 1 ]
}

@test "repo_add_traditional rejects invalid deb line" {
  run repo_add_traditional "goodname" "http://example.com"
  [ "$status" -eq 1 ]
}
