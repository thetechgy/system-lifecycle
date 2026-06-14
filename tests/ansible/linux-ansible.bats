#!/usr/bin/env bats
#
# linux-ansible.bats - Tests for Linux Ansible migration surface
#

load '../test_helper'

ANSIBLE_DIR="${REPO_ROOT}/linux/ansible"

@test "linux ansible playbooks exist" {
  [ -f "${ANSIBLE_DIR}/playbooks/update-system.yml" ]
  [ -f "${ANSIBLE_DIR}/playbooks/install-workstation.yml" ]
  [ -f "${ANSIBLE_DIR}/playbooks/configure-shell.yml" ]
}

@test "linux ansible inventory and config exist" {
  [ -f "${ANSIBLE_DIR}/ansible.cfg" ]
  [ -f "${ANSIBLE_DIR}/inventory/localhost.yml" ]
  [ -x "${ANSIBLE_DIR}/scripts/ensure-ansible.sh" ]
}

@test "ansible bootstrap supports dry-run" {
  run bash "${ANSIBLE_DIR}/scripts/ensure-ansible.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ansible runtime packages are installed"* || "$output" == *"[DRY-RUN] Would install packages:"* ]]
}

@test "ansible bootstrap installs missing packages through apt" {
  run grep -n "sudo apt-get install --no-install-recommends -y" "${ANSIBLE_DIR}/scripts/ensure-ansible.sh"
  [ "$status" -eq 0 ]

  run grep -n "ansible-core" "${ANSIBLE_DIR}/scripts/ensure-ansible.sh"
  [ "$status" -eq 0 ]
}

@test "system update role keeps snap nodejs model" {
  run grep -R "snap .*node" "${ANSIBLE_DIR}/roles/system_updates/tasks/nodejs.yml"
  [ "$status" -eq 0 ]

  run grep -R "NodeSource" "${ANSIBLE_DIR}/roles/system_updates"
  [ "$status" -ne 0 ]
}

@test "npm update role runs in target user context" {
  run grep -n "become_user: \"{{ resolved_target_user }}\"" "${ANSIBLE_DIR}/roles/system_updates/tasks/npm.yml"
  [ "$status" -eq 0 ]

  run grep -n "target_user_environment" "${ANSIBLE_DIR}/roles/system_updates/tasks/npm.yml"
  [ "$status" -eq 0 ]
}

@test "shell aliases expose common linux scenarios" {
  local alias_file="${ANSIBLE_DIR}/roles/shell_aliases/tasks/main.yml"

  run grep -E "linux-update|linux-update-check|linux-update-firmware" "${alias_file}"
  [ "$status" -eq 0 ]

  run grep -E "linux-workstation|linux-workstation-check|linux-security" "${alias_file}"
  [ "$status" -eq 0 ]

  run grep -n "ensure-ansible.sh" "${alias_file}"
  [ "$status" -eq 0 ]
}

@test "workstation role has expected phase tags" {
  local role_file="${ANSIBLE_DIR}/roles/workstation/tasks/main.yml"

  run grep -E "security|apps|devtools|extensions|fastfetch" "${role_file}"
  [ "$status" -eq 0 ]
}

@test "ansible syntax check passes when ansible is installed" {
  if ! command -v ansible-playbook >/dev/null 2>&1; then
    skip "ansible-playbook is not installed"
  fi

  run bash -c "cd '${ANSIBLE_DIR}' && ansible-playbook --syntax-check playbooks/update-system.yml playbooks/install-workstation.yml playbooks/configure-shell.yml"
  [ "$status" -eq 0 ]
}
