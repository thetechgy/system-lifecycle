#!/usr/bin/env bats

# Tests for rollback.sh library
# Focuses on backup/restore functionality

setup() {
  load '../test_helper'
  mock_logging

  # Create a temporary directory for tests
  TEST_BACKUP_DIR=$(mktemp -d)
  export ROLLBACK_DIR="${TEST_BACKUP_DIR}"

  # Load required libraries
  load_lib "colors.sh"
  load_lib "logging.sh"
  load_lib "utils.sh"
  load_lib "rollback.sh"
}

teardown() {
  # Clean up test directory
  rm -rf "${TEST_BACKUP_DIR}"
}

# Test rollback_create_restore_point function
@test "rollback_create_restore_point: creates restore point directory" {
  run rollback_create_restore_point "test-restore"
  [ "$status" -eq 0 ]

  # Verify directory was created
  local restore_point_dir
  restore_point_dir=$(ls -d "${ROLLBACK_DIR}/restore-points/test-restore-"* 2>/dev/null | head -1)
  [ -d "${restore_point_dir}" ]
}

@test "rollback_create_restore_point: creates metadata file" {
  run rollback_create_restore_point "test-restore"
  [ "$status" -eq 0 ]

  local restore_point_dir
  restore_point_dir=$(ls -d "${ROLLBACK_DIR}/restore-points/test-restore-"* 2>/dev/null | head -1)
  [ -f "${restore_point_dir}/metadata" ]
}

@test "rollback_create_restore_point: metadata contains name" {
  rollback_create_restore_point "my-backup" > /dev/null

  local restore_point_dir
  restore_point_dir=$(ls -d "${ROLLBACK_DIR}/restore-points/my-backup-"* 2>/dev/null | head -1)
  grep -q "^name=my-backup$" "${restore_point_dir}/metadata"
}

@test "rollback_create_restore_point: handles extra directories" {
  # Create test directories
  local test_extra_dir="${TEST_BACKUP_DIR}/extra_test"
  mkdir -p "${test_extra_dir}"
  echo "test content" > "${test_extra_dir}/testfile.txt"

  # Create restore point with extra directory
  run rollback_create_restore_point "with-extra" "${test_extra_dir}"
  [ "$status" -eq 0 ]
}

# Test rollback_backup_file function
@test "rollback_backup_file: backs up existing file" {
  # Create test file
  local test_file="${TEST_BACKUP_DIR}/testfile.txt"
  echo "test content" > "${test_file}"

  run rollback_backup_file "${test_file}" "test-label"
  [ "$status" -eq 0 ]

  # Verify backup was created
  [ -f "${ROLLBACK_DIR}/files/testfile.txt.test-label.bak" ]
}

@test "rollback_backup_file: handles non-existent file gracefully" {
  run rollback_backup_file "/nonexistent/file.txt" "test-label"
  # Should return 0 (success) with warning, not fail
  [ "$status" -eq 0 ]
}

@test "rollback_backup_file: preserves file content" {
  local test_file="${TEST_BACKUP_DIR}/content_test.txt"
  echo "important content" > "${test_file}"

  rollback_backup_file "${test_file}" "content-test"

  local backup_content
  backup_content=$(cat "${ROLLBACK_DIR}/files/content_test.txt.content-test.bak")
  [ "${backup_content}" = "important content" ]
}

# Test rollback_backup_directory function
@test "rollback_backup_directory: backs up directory as tarball" {
  # Create test directory with content
  local test_dir="${TEST_BACKUP_DIR}/backup_dir_test"
  mkdir -p "${test_dir}"
  echo "file1" > "${test_dir}/file1.txt"
  echo "file2" > "${test_dir}/file2.txt"

  run rollback_backup_directory "${test_dir}" "dir-label"
  [ "$status" -eq 0 ]

  # Verify backup exists
  [ -f "${ROLLBACK_DIR}/directories/_"*"backup_dir_test.dir-label.tar.gz" ] || \
    ls "${ROLLBACK_DIR}/directories/"*.tar.gz 2>/dev/null | grep -q "backup_dir_test"
}

@test "rollback_backup_directory: handles non-existent directory gracefully" {
  run rollback_backup_directory "/nonexistent/directory" "test-label"
  [ "$status" -eq 0 ]
}

# Test rollback_list_restore_points function
@test "rollback_list_restore_points: handles empty restore points" {
  run rollback_list_restore_points
  [ "$status" -eq 0 ]
}

@test "rollback_list_restore_points: lists created restore points" {
  # Create a restore point
  rollback_create_restore_point "list-test" > /dev/null

  run rollback_list_restore_points
  [ "$status" -eq 0 ]
}

# Test rollback_cleanup function
@test "rollback_cleanup: handles empty restore points directory" {
  run rollback_cleanup 5
  [ "$status" -eq 0 ]
}

@test "rollback_cleanup: keeps specified number of restore points" {
  # Create multiple restore points
  for i in 1 2 3; do
    rollback_create_restore_point "cleanup-test-${i}" > /dev/null
    sleep 1  # Ensure different timestamps
  done

  # Verify we have 3 restore points
  local count
  count=$(find "${ROLLBACK_DIR}/restore-points" -maxdepth 1 -mindepth 1 -type d | wc -l)
  [ "${count}" -eq 3 ]

  # Cleanup keeping only 2
  run rollback_cleanup 2

  # Verify we now have 2 or fewer
  count=$(find "${ROLLBACK_DIR}/restore-points" -maxdepth 1 -mindepth 1 -type d | wc -l)
  [ "${count}" -le 2 ]
}

# Test rollback_restore function
@test "rollback_restore: handles non-existent restore point" {
  run rollback_restore "nonexistent-restore-point"
  [ "$status" -ne 0 ]
}

# Test array handling (security fix verification)
@test "rollback_create_restore_point: handles multiple extra directories" {
  # Create test directories
  local test_dir1="${TEST_BACKUP_DIR}/extra1"
  local test_dir2="${TEST_BACKUP_DIR}/extra2"
  mkdir -p "${test_dir1}" "${test_dir2}"
  echo "content1" > "${test_dir1}/file1.txt"
  echo "content2" > "${test_dir2}/file2.txt"

  # Call with multiple directories as separate arguments (new API)
  run rollback_create_restore_point "multi-extra" "${test_dir1}" "${test_dir2}"
  [ "$status" -eq 0 ]
}

@test "rollback_create_restore_point: handles directory with spaces" {
  # Create test directory with spaces in name
  local test_dir="${TEST_BACKUP_DIR}/dir with spaces"
  mkdir -p "${test_dir}"
  echo "content" > "${test_dir}/file.txt"

  # This should work with the array fix
  run rollback_create_restore_point "space-test" "${test_dir}"
  [ "$status" -eq 0 ]
}
