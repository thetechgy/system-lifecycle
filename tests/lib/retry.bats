#!/usr/bin/env bats

# Tests for retry.sh library
# Focuses on security and functionality after eval removal

setup() {
  load '../test_helper'
  mock_logging
  load_lib "colors.sh"
  load_lib "logging.sh"
  load_lib "retry.sh"
}

# Test retry_with_backoff function
@test "retry_with_backoff: succeeds on first attempt" {
  run retry_with_backoff 3 true
  [ "$status" -eq 0 ]
}

@test "retry_with_backoff: fails after max attempts" {
  run retry_with_backoff 2 /bin/false
  [ "$status" -ne 0 ]
}

@test "retry_with_backoff: succeeds on retry" {
  # Create a script that fails twice then succeeds
  local temp_script
  temp_script=$(mktemp)
  local counter_file
  counter_file=$(mktemp)
  echo "0" > "${counter_file}"

  cat > "${temp_script}" << 'EOF'
#!/bin/bash
counter_file="$1"
count=$(cat "$counter_file")
count=$((count + 1))
echo "$count" > "$counter_file"
[ "$count" -ge 3 ]
EOF
  chmod +x "${temp_script}"

  run retry_with_backoff 5 "${temp_script}" "${counter_file}"
  [ "$status" -eq 0 ]

  rm -f "${temp_script}" "${counter_file}"
}

# Test retry_command function
@test "retry_command: succeeds on first attempt" {
  run retry_command 3 1 true
  [ "$status" -eq 0 ]
}

@test "retry_command: fails after max attempts" {
  run retry_command 2 0 /bin/false
  [ "$status" -ne 0 ]
}

# Test retry_until function security
@test "retry_until: rejects shell expressions with semicolon" {
  run retry_until 3 1 "true; rm -rf /"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "must be a simple function or command name" ]]
}

@test "retry_until: rejects shell expressions with pipe" {
  run retry_until 3 1 "cat /etc/passwd | head"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "must be a simple function or command name" ]]
}

@test "retry_until: rejects shell expressions with ampersand" {
  run retry_until 3 1 "true && false"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "must be a simple function or command name" ]]
}

@test "retry_until: rejects shell expressions with backticks" {
  run retry_until 3 1 '`whoami`'
  [ "$status" -ne 0 ]
  [[ "$output" =~ "must be a simple function or command name" ]]
}

@test "retry_until: rejects shell expressions with dollar sign" {
  run retry_until 3 1 '$(whoami)'
  [ "$status" -ne 0 ]
  [[ "$output" =~ "must be a simple function or command name" ]]
}

@test "retry_until: rejects shell expressions with parentheses" {
  run retry_until 3 1 "(exit 0)"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "must be a simple function or command name" ]]
}

@test "retry_until: rejects invalid/nonexistent function" {
  run retry_until 3 1 "nonexistent_function_xyz123"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "not a valid function or command" ]]
}

@test "retry_until: accepts valid function name" {
  # Define a test function
  test_condition() { return 0; }
  export -f test_condition

  run retry_until 3 1 "test_condition"
  [ "$status" -eq 0 ]
}

@test "retry_until: accepts builtin command" {
  run retry_until 3 1 "true"
  [ "$status" -eq 0 ]
}

# Test network_available function
@test "network_available: function exists" {
  run type network_available
  [ "$status" -eq 0 ]
}

# Test wait_for_service function
@test "wait_for_service: rejects invalid service name with shell metacharacters" {
  run wait_for_service "snapd; rm -rf /" 1 1
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Invalid service name" ]]
}

@test "wait_for_service: rejects service name with spaces" {
  run wait_for_service "snapd attack" 1 1
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Invalid service name" ]]
}

@test "wait_for_service: accepts valid service name format" {
  # This should fail because service likely doesn't exist, but format is valid
  run wait_for_service "test-service.socket" 1 1
  # Format was accepted (would fail for different reason - service not found)
  [[ ! "$output" =~ "Invalid service name" ]]
}

# Test retry_with_jitter function
@test "retry_with_jitter: succeeds on first attempt" {
  run retry_with_jitter 3 1 true
  [ "$status" -eq 0 ]
}

@test "retry_with_jitter: fails after max attempts" {
  run retry_with_jitter 2 0 false
  [ "$status" -ne 0 ]
}

# Test retry_download function
@test "retry_download: function exists" {
  run type retry_download
  [ "$status" -eq 0 ]
}

@test "retry_apt_update: function exists" {
  run type retry_apt_update
  [ "$status" -eq 0 ]
}
