#!/usr/bin/env bats
#
# gnome-extensions.bats - Tests for gnome-extensions.sh
#

load '../test_helper'

setup() {
  TEST_TEMP_DIR=$(mktemp -d)
  export TEST_TEMP_DIR
  ORIG_PATH="${PATH}"
  export PATH="${TEST_TEMP_DIR}:${PATH}"
  LIST_FILE="${TEST_TEMP_DIR}/gnome-list"
  export LIST_FILE

  cat > "${TEST_TEMP_DIR}/gnome-extensions" << 'EOF'
#!/usr/bin/env bash
if [[ "${1}" == "list" ]]; then
  cat "${LIST_FILE}"
fi
EOF
  chmod +x "${TEST_TEMP_DIR}/gnome-extensions"

  mock_logging
  load_lib "gnome-extensions.sh"
}

teardown() {
  PATH="${ORIG_PATH}"
  rm -rf "${TEST_TEMP_DIR}"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

@test "gnome_extension_is_installed does not match similar UUIDs" {
  printf '%s\n' "Vitals@CoreCodingXcom" > "${LIST_FILE}"
  run gnome_extension_is_installed "Vitals@CoreCoding.com"
  [ "$status" -eq 1 ]
}

@test "gnome_extension_is_installed matches exact UUID" {
  printf '%s\n' "Vitals@CoreCoding.com" > "${LIST_FILE}"
  run gnome_extension_is_installed "Vitals@CoreCoding.com"
  [ "$status" -eq 0 ]
}
