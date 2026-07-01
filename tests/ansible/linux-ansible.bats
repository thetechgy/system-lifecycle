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
  run grep -R "snap" "${ANSIBLE_DIR}/roles/system_updates/tasks/nodejs.yml"
  [ "$status" -eq 0 ]

  run grep -R "node" "${ANSIBLE_DIR}/roles/system_updates/tasks/nodejs.yml"
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

@test "shell aliases do not change the caller directory" {
  local alias_file="${ANSIBLE_DIR}/roles/shell_aliases/tasks/main.yml"

  run grep -F "cd {{ ansible_root }}" "${alias_file}"
  [ "$status" -ne 0 ]

  run grep -c -F 'ANSIBLE_CONFIG="{{ ansible_root }}/ansible.cfg"' "${alias_file}"
  [ "$status" -eq 0 ]
  [ "$output" -eq 8 ]

  run grep -c -F '"{{ ansible_root }}/scripts/ensure-ansible.sh"' "${alias_file}"
  [ "$status" -eq 0 ]
  [ "$output" -eq 8 ]

  run grep -c -F '"{{ ansible_root }}/playbooks/' "${alias_file}"
  [ "$status" -eq 0 ]
  [ "$output" -eq 8 ]
}

@test "workstation role has expected phase tags" {
  local role_file="${ANSIBLE_DIR}/roles/workstation/tasks/main.yml"

  run grep -E "security|apps|devtools|extensions|fastfetch" "${role_file}"
  [ "$status" -eq 0 ]
}

@test "workstation devtools do not manage Claude CLI" {
  local devtools_file="${ANSIBLE_DIR}/roles/workstation/tasks/devtools.yml"

  run grep -Ri "claude" "${devtools_file}"
  [ "$status" -ne 0 ]
}

@test "workstation AI CLIs update installed tools and gate first installs" {
  local devtools_file="${ANSIBLE_DIR}/roles/workstation/tasks/devtools.yml"

  run grep -n "Update installed Copilot CLI" "${devtools_file}"
  [ "$status" -eq 0 ]

  run grep -n "@github/copilot" "${devtools_file}"
  [ "$status" -eq 0 ]

  run grep -n "workstation_install_copilot_cli" "${devtools_file}"
  [ "$status" -eq 0 ]

  run grep -n "Update npm-managed Codex CLI" "${devtools_file}"
  [ "$status" -eq 0 ]

  run grep -n "@openai/codex" "${devtools_file}"
  [ "$status" -eq 0 ]

  run grep -n "workstation_install_codex_cli" "${devtools_file}"
  [ "$status" -eq 0 ]
}

@test "workstation apps do not assume a Discord APT source" {
  local apps_file="${ANSIBLE_DIR}/roles/workstation/tasks/apps.yml"

  run grep -n "workstation_install_discord" "${apps_file}"
  [ "$status" -eq 0 ]

  run grep -n "apt-cache" "${apps_file}"
  [ "$status" -eq 0 ]

  run grep -n "Install Discord from configured APT sources" "${apps_file}"
  [ "$status" -eq 0 ]
}

@test "variable-bearing Ansible command tasks use argv or stdin" {
  run grep -R 'pro attach {{' "${ANSIBLE_DIR}/roles/workstation/tasks"
  [ "$status" -ne 0 ]

  run grep -R 'usg audit {{' "${ANSIBLE_DIR}/roles/workstation/tasks"
  [ "$status" -ne 0 ]

  run grep -R 'gnome-extensions enable {{' "${ANSIBLE_DIR}/roles/workstation/tasks"
  [ "$status" -ne 0 ]

  run grep -R 'dconf load .*<' "${ANSIBLE_DIR}/roles/workstation/tasks"
  [ "$status" -ne 0 ]

  run grep -R 'snap refresh node --channel={{' "${ANSIBLE_DIR}/roles/system_updates/tasks/nodejs.yml"
  [ "$status" -ne 0 ]
}

@test "ansible syntax check passes when ansible is installed" {
  if ! command -v ansible-playbook >/dev/null 2>&1; then
    skip "ansible-playbook is not installed"
  fi

  run env ANSIBLE_LOCAL_TEMP="${BATS_TEST_TMPDIR}/ansible-local" bash -c "cd '${ANSIBLE_DIR}' && ansible-playbook --syntax-check playbooks/update-system.yml playbooks/install-workstation.yml playbooks/configure-shell.yml"
  [ "$status" -eq 0 ]
}
