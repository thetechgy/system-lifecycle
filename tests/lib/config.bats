#!/usr/bin/env bats
#
# config.bats - Tests for config.sh
#

load '../test_helper'

setup() {
  TEST_TEMP_DIR=$(mktemp -d)
  export TEST_TEMP_DIR
  mock_logging
  load_lib "config.sh"
  config_reset
}

teardown() {
  rm -rf "${TEST_TEMP_DIR}"
}

@test "config_load parses key/value and quoted values" {
  local config_file="${TEST_TEMP_DIR}/config"
  cat > "${config_file}" << 'EOF'
# Example config
foo=bar
baz="hello world"
EOF

  config_load "${config_file}"
  [ "$(config_get "foo")" = "bar" ]
  [ "$(config_get "baz")" = "hello world" ]
}

@test "config_get_bool handles truthy and falsy values" {
  config_set "flag" "yes"
  run config_get_bool "flag"
  [ "$status" -eq 0 ]

  config_set "flag" "no"
  run config_get_bool "flag"
  [ "$status" -eq 1 ]
}

@test "config_save writes file with restrictive permissions" {
  local config_file="${TEST_TEMP_DIR}/saved-config"

  config_set "token" "abc123"
  config_set "spaced" "hello world"

  run config_save "${config_file}"
  [ "$status" -eq 0 ]

  local perms
  perms=$(stat -c '%a' "${config_file}" 2>/dev/null || stat -f '%Lp' "${config_file}" 2>/dev/null)
  [ "${perms}" = "600" ]

  local contents
  contents=$(cat "${config_file}")
  [[ "${contents}" == *'spaced="hello world"'* ]]
}
