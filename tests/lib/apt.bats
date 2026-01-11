#!/usr/bin/env bats
#
# apt.bats - Tests for apt.sh
#

load '../test_helper'

setup() {
  TEST_TEMP_DIR=$(mktemp -d)
  export TEST_TEMP_DIR
  ORIG_PATH="${PATH}"
  export PATH="${TEST_TEMP_DIR}:${PATH}"

  cat > "${TEST_TEMP_DIR}/apt-get" << 'EOF'
#!/usr/bin/env bash
exit "${APT_GET_EXIT:-0}"
EOF
  chmod +x "${TEST_TEMP_DIR}/apt-get"

  cat > "${TEST_TEMP_DIR}/dpkg-query" << 'EOF'
#!/usr/bin/env bash
format=""
pkg=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f=*)
      format="${1#-f=}"
      shift
      ;;
    -f)
      shift
      format="${1}"
      shift
      ;;
    *)
      pkg="$1"
      shift
      ;;
  esac
done

if [[ "${format}" == *Status* ]]; then
  if [[ "${pkg}" == "presentpkg" ]]; then
    echo "install ok installed"
  else
    echo "deinstall ok config-files"
  fi
  exit 0
fi

if [[ "${format}" == *Version* ]]; then
  if [[ "${pkg}" == "presentpkg" ]]; then
    echo "1.2.3"
  fi
  exit 0
fi

exit 0
EOF
  chmod +x "${TEST_TEMP_DIR}/dpkg-query"

  mock_logging
  load_lib "apt.sh"
}

teardown() {
  PATH="${ORIG_PATH}"
  rm -rf "${TEST_TEMP_DIR}"
}

@test "apt_install fails with no packages" {
  run apt_install
  [ "$status" -eq 1 ]
}

@test "apt_install succeeds when apt-get succeeds" {
  export APT_GET_EXIT=0
  run apt_install foo bar
  [ "$status" -eq 0 ]
}

@test "apt_install fails when apt-get fails" {
  export APT_GET_EXIT=1
  run apt_install foo
  [ "$status" -eq 1 ]
}

@test "apt_is_installed detects installed package" {
  run apt_is_installed presentpkg
  [ "$status" -eq 0 ]
}

@test "apt_is_installed returns false for missing package" {
  run apt_is_installed missingpkg
  [ "$status" -eq 1 ]
}

@test "apt_get_version returns version for installed package" {
  run apt_get_version presentpkg
  [ "$status" -eq 0 ]
  [ "$output" = "1.2.3" ]
}
