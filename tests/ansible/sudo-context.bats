#!/usr/bin/env bats

load '../test_helper'

ANSIBLE_DIR="${REPO_ROOT}/linux/ansible"
FIXTURE_DIR="${REPO_ROOT}/tests/ansible/fixtures"

setup() {
  if ! command -v ansible-playbook >/dev/null 2>&1; then
    skip "ansible-playbook is not installed"
  fi

  export ANSIBLE_CONFIG="${BATS_TEST_TMPDIR}/ansible.cfg"
  export ANSIBLE_LOCAL_TEMP="${BATS_TEST_TMPDIR}/ansible-local"
  export ANSIBLE_REMOTE_TEMP="${BATS_TEST_TMPDIR}/ansible-remote"
  export ANSIBLE_ROLES_PATH="${ANSIBLE_DIR}/roles"
  export ANSIBLE_INJECT_FACTS_AS_VARS=False
  export ANSIBLE_NOCOLOR=1
  unset ANSIBLE_BECOME_EXE ANSIBLE_SUDO_EXE ANSIBLE_BECOME_METHOD
  export SUDO_USER=""
  export SUDO_TEST_IMPLEMENTATION=rust
  export SUDO_TEST_CLASSIC_IMPLEMENTATION=classic
  export SUDO_PROBE_LOG="${BATS_TEST_TMPDIR}/sudo-probes"
  FIXTURE_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${FIXTURE_BIN}"
  cat > "${ANSIBLE_CONFIG}" <<'EOF'
[defaults]
nocows = True
[privilege_escalation]
become = False
become_method = sudo
EOF
  # These executables reject every operation except version queries. Tasks
  # run with only this directory on PATH, so missing sudo.ws cannot fall back
  # to the real host executable.
  cat > "${FIXTURE_BIN}/sudo" <<'EOF'
#!/bin/sh
[ "$#" -eq 1 ] && [ "$1" = --version ] || exit 86
printf '%s\n' 'sudo --version' >> "$SUDO_PROBE_LOG"
if [ "$SUDO_TEST_IMPLEMENTATION" = rust ]; then
  printf '%s\n' 'sudo-rs 0.2.13'
else
  printf '%s\n' 'Sudo version 1.9.17p2'
fi
EOF
  cat > "${FIXTURE_BIN}/sudo.ws" <<'EOF'
#!/bin/sh
[ "$#" -eq 1 ] && [ "$1" = --version ] || exit 86
printf '%s\n' 'sudo.ws --version' >> "$SUDO_PROBE_LOG"
if [ "$SUDO_TEST_CLASSIC_IMPLEMENTATION" = rust ]; then
  printf '%s\n' 'sudo-rs 0.2.13'
else
  printf '%s\n' 'Sudo version 1.9.17p2'
fi
EOF
  cat > "${FIXTURE_BIN}/getent" <<'EOF'
#!/bin/sh
[ "$#" -eq 2 ] && [ "$1" = passwd ] || exit 86
case "$2" in
  fixture_login|fixture_target)
    printf '%s:x:1001:1002:Fixture:/nonexistent/%s:/bin/sh\n' "$2" "$2"
    ;;
  *) exit 2 ;;
esac
EOF
  cat > "${FIXTURE_BIN}/id" <<'EOF'
#!/bin/sh
[ "$#" -eq 2 ] && [ "$1" = -gn ] || exit 86
printf '%s\n' fixture_group
EOF
  chmod +x "${FIXTURE_BIN}/sudo" "${FIXTURE_BIN}/sudo.ws" "${FIXTURE_BIN}/getent" "${FIXTURE_BIN}/id"
}

run_sudo_fixture() {
  run ansible-playbook -i localhost, "${FIXTURE_DIR}/sudo-context.yml" \
    -e "fixture_bin=${FIXTURE_BIN}" -e expected_executable="${1}" "${@:2}"
}

assert_unchanged_success() {
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output"
    return 1
  fi
  [[ "$output" == *"changed=0"* ]]
  [[ "$output" != *"INJECT_FACTS_AS_VARS"* ]]
}

@test "sudo-rs selects classic sudo with unprivileged probes" {
  run_sudo_fixture sudo.ws
  assert_unchanged_success
  [ "$(cat "${SUDO_PROBE_LOG}")" = $'sudo --version\nsudo.ws --version' ]
}

@test "classic sudo stays the default without probing sudo.ws" {
  export SUDO_TEST_IMPLEMENTATION=classic
  rm "${FIXTURE_BIN}/sudo.ws"
  run_sudo_fixture sudo
  assert_unchanged_success
  [ "$(cat "${SUDO_PROBE_LOG}")" = 'sudo --version' ]
}

@test "sudo-rs without classic sudo fails before privilege escalation" {
  rm "${FIXTURE_BIN}/sudo.ws"
  run_sudo_fixture sudo.ws
  [ "$status" -ne 0 ]
  [[ "$output" == *"Install Ubuntu's classic sudo package"* ]]
  [[ "$output" == *"changed=0"* ]]
  [ "$(cat "${SUDO_PROBE_LOG}")" = 'sudo --version' ]
}

@test "sudo-rs rejects unusable classic sudo" {
  chmod -x "${FIXTURE_BIN}/sudo.ws"
  run_sudo_fixture sudo.ws
  [ "$status" -ne 0 ]
  [[ "$output" == *"Install Ubuntu's classic sudo package"* ]]
}

@test "sudo-rs rejects a sudo.ws executable that also identifies as sudo-rs" {
  export SUDO_TEST_CLASSIC_IMPLEMENTATION=rust
  run_sudo_fixture sudo.ws
  [ "$status" -ne 0 ]
  [[ "$output" == *"Install Ubuntu's classic sudo package"* ]]
}

@test "extra-variable sudo override skips automatic selection" {
  run_sudo_fixture sudo -e ansible_become_exe=sudo -e expect_no_probes=true
  assert_unchanged_success
  [ ! -e "${SUDO_PROBE_LOG}" ]
}

@test "inventory sudo override skips automatic selection" {
  cat > "${BATS_TEST_TMPDIR}/inventory.yml" <<'EOF'
all:
  hosts:
    localhost:
      ansible_become_exe: configured-sudo
EOF
  run_sudo_fixture configured-sudo -i "${BATS_TEST_TMPDIR}/inventory.yml" -e expect_no_probes=true
  assert_unchanged_success
  [ ! -e "${SUDO_PROBE_LOG}" ]
}

@test "legacy sudo variable override skips automatic selection" {
  run_sudo_fixture configured-sudo -e ansible_sudo_exe=configured-sudo -e expect_no_probes=true
  assert_unchanged_success
  [ ! -e "${SUDO_PROBE_LOG}" ]
}

@test "environment sudo overrides skip automatic selection even when set to sudo" {
  export ANSIBLE_BECOME_EXE=sudo
  run_sudo_fixture sudo -e expect_no_probes=true
  assert_unchanged_success
  unset ANSIBLE_BECOME_EXE
  export ANSIBLE_SUDO_EXE=sudo
  run_sudo_fixture sudo -e expect_no_probes=true
  assert_unchanged_success
  [ ! -e "${SUDO_PROBE_LOG}" ]
}

@test "privilege escalation config override skips automatic selection" {
  printf '%s\n' 'become_exe = sudo' >> "${ANSIBLE_CONFIG}"
  run_sudo_fixture sudo -e expect_no_probes=true
  assert_unchanged_success
  [ ! -e "${SUDO_PROBE_LOG}" ]
}

@test "sudo plugin config override skips automatic selection" {
  printf '%s\n' '[sudo_become_plugin]' 'executable = sudo' >> "${ANSIBLE_CONFIG}"
  run_sudo_fixture sudo -e expect_no_probes=true
  assert_unchanged_success
  [ ! -e "${SUDO_PROBE_LOG}" ]
}

@test "sudo plugin config preserves executable values containing percent signs" {
  printf '%s\n' '[sudo_become_plugin]' 'executable = fixture%sudo' >> "${ANSIBLE_CONFIG}"
  run_sudo_fixture 'fixture%sudo' -e expect_no_probes=true
  assert_unchanged_success
  [ ! -e "${SUDO_PROBE_LOG}" ]
}

@test "other become methods skip sudo compatibility probes" {
  run_sudo_fixture unused -e ansible_become_method=su -e expect_no_probes=true
  assert_unchanged_success
  [ ! -e "${SUDO_PROBE_LOG}" ]
}

@test "automatic sudo selection does not change another CLI-selected plugin executable" {
  run_sudo_fixture sudo.ws --become-method su -e verify_other_plugin=true
  assert_unchanged_success
}

@test "sudo selection runs in tagged check mode without reporting changes" {
  run_sudo_fixture sudo.ws --check --tags fixture
  assert_unchanged_success
  [ "$(cat "${SUDO_PROBE_LOG}")" = $'sudo --version\nsudo.ws --version' ]
}

run_context_fixture() {
  run ansible-playbook -i localhost, "${FIXTURE_DIR}/linux-context.yml" \
    -e "fixture_bin=${FIXTURE_BIN}" "${@}"
}

@test "context resolves the login user with fact injection disabled" {
  run_context_fixture -e expected_user=fixture_login -e expected_home=/nonexistent/fixture_login
  assert_unchanged_success
}

@test "context honors target user and home overrides in tagged check mode" {
  run_context_fixture --check --tags fixture \
    -e target_user=fixture_target -e target_home=/nonexistent/override \
    -e expected_user=fixture_target -e expected_home=/nonexistent/override
  assert_unchanged_success
}

@test "context uses SUDO_USER and ignores root as a target user fallback" {
  export SUDO_USER=fixture_target
  run_context_fixture -e expected_user=fixture_target -e expected_home=/nonexistent/fixture_target
  assert_unchanged_success
  export SUDO_USER=root
  run_context_fixture -e expected_user=fixture_login -e expected_home=/nonexistent/fixture_login
  assert_unchanged_success
}

@test "context detects WSL using namespaced kernel facts" {
  run_context_fixture -e fixture_kernel=Linux-Microsoft-WSL2 -e expected_wsl=true \
    -e expected_user=fixture_login -e expected_home=/nonexistent/fixture_login
  assert_unchanged_success
}

@test "all production playbooks load shared context during tagged check runs" {
  local playbook
  for playbook in update-system install-workstation configure-shell; do
    run ansible-playbook -i localhost, "${ANSIBLE_DIR}/playbooks/${playbook}.yml" \
      --check --tags lifecycle-context-test -e ansible_become_exe=sudo.ws
    assert_unchanged_success
    [[ "$output" == *"Set target command environment"* ]]
  done
}

@test "shell alias check mode evaluates user privilege comparisons without fact injection" {
  run ansible-playbook -i localhost, "${ANSIBLE_DIR}/playbooks/configure-shell.yml" \
    --check --tags aliases -e ansible_become_exe=sudo.ws \
    -e "shell_aliases_file=${BATS_TEST_TMPDIR}/aliases"
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output"
    return 1
  fi
  [[ "$output" != *"INJECT_FACTS_AS_VARS"* ]]
  [[ "$output" == *"Configure system-lifecycle aliases"* ]]
  [ ! -e "${BATS_TEST_TMPDIR}/aliases" ]
}
