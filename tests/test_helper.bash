#!/usr/bin/env bash
#
# test_helper.bash - Common setup and helpers for Bats tests
#

# Get the repository root directory
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

# Library paths
export LIB_DIR="${REPO_ROOT}/linux/lib"

# Source a library file safely (for testing)
load_lib() {
  local lib_name="${1}"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/${lib_name}"
}

# Mock log functions to prevent output during tests
mock_logging() {
  log_info() { :; }
  log_success() { :; }
  log_warning() { :; }
  log_error() { :; }
  section() { :; }
  export -f log_info log_success log_warning log_error section
}
