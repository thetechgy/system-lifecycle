#!/usr/bin/env bats
load '../test_helper'
setup() {
  command -v ansible-playbook >/dev/null || skip 'Ansible required'
  export ANSIBLE_LOCAL_TEMP="$BATS_TEST_TMPDIR/local"
  export ANSIBLE_REMOTE_TEMP="$BATS_TEST_TMPDIR/remote"
  export ANSIBLE_ROLES_PATH="$REPO_ROOT/linux/ansible/roles"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/dpkg-query" <<'SH'
#!/bin/sh
printf '%s' "${PS_PACKAGE_STATUS:-}"
exit "${PS_QUERY_RC:-0}"
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/dpkg-query"
  export PS_PACKAGE_STATUS='installed 7.4.0-1.deb'
  cat > "$BATS_TEST_TMPDIR/play.yml" <<YAML
- hosts: localhost
  connection: local
  gather_facts: false
  environment:
    PATH: "$BATS_TEST_TMPDIR/bin:/usr/bin:/bin"
    PS_PACKAGE_STATUS: "{{ fixture_status | default('installed 7.4.0-1.deb') }}"
    PS_QUERY_RC: "{{ fixture_rc | default(0) }}"
  vars:
    ansible_python_interpreter: /usr/bin/python3
    ansible_facts:
      architecture: x86_64
      distribution: Ubuntu
      distribution_version: '24.04'
      distribution_major_version: '24'
      distribution_release: noble
    update_apt: true
    update_snap: false
    update_flatpak: false
    update_npm: false
    update_nvm: false
    update_codex_cli: false
  roles: [system_updates]
YAML
}
@test 'PowerShell tagged production tasks preview without mutation or unrelated phases' {
  run ansible-playbook -i localhost, "$BATS_TEST_TMPDIR/play.yml" --tags powershell --check
  [ "$status" -eq 0 ]
  [[ "$output" == *'would ensure the official Microsoft'* ]]
  [[ "$output" != *'TASK [system_updates : Upgrade installed packages]'* ]]
}
@test 'missing PowerShell is skipped without repository changes' {
  run ansible-playbook -i localhost, "$BATS_TEST_TMPDIR/play.yml" --tags powershell -e '{"fixture_status":"","fixture_rc":1}'
  [ "$status" -eq 0 ]
  [[ "$output" == *'skipping PowerShell updates'* ]]
  [[ "$output" == *'changed=0'* ]]
}
@test 'unsupported releases are skipped before repository or installer work' {
  run ansible-playbook -i localhost, "$BATS_TEST_TMPDIR/play.yml" --tags powershell -e '{"ansible_facts":{"architecture":"x86_64","distribution":"Ubuntu","distribution_version":"25.10"}}'
  [ "$status" -eq 0 ]
  [[ "$output" == *'skipping PowerShell updates'* ]]
  [[ "$output" == *'changed=0'* ]]
}
@test 'APT disable switch also disables PowerShell preparation' {
  run ansible-playbook -i localhost, "$BATS_TEST_TMPDIR/play.yml" --tags powershell -e update_apt=false
  [ "$status" -eq 0 ]
  [[ "$output" != *'would ensure the official Microsoft'* ]]
  [[ "$output" == *'changed=0'* ]]
}
@test 'package database errors fail instead of looking like missing PowerShell' {
  run ansible-playbook -i localhost, "$BATS_TEST_TMPDIR/play.yml" --tags powershell -e fixture_rc=2
  [ "$status" -ne 0 ]
}

run_package_fixture() {
  export ANSIBLE_STRATEGY_PLUGINS="$REPO_ROOT/tests/fixtures/powershell/strategy_plugins"
  export ANSIBLE_ACTION_PLUGINS="$REPO_ROOT/tests/fixtures/powershell/action_plugins"
  export ANSIBLE_STRATEGY=powershell_fixture
  export PS_FIXTURE_LOG="$BATS_TEST_TMPDIR/operations.jsonl"
  run ansible-playbook -i localhost, "$BATS_TEST_TMPDIR/play.yml" --tags powershell "$@"
  printf '%s\n' "$output" > "$BATS_TEST_TMPDIR/output.log"
}
@test 'missing repository loads signing key tasks even when selected by PowerShell tag' {
  run_package_fixture
  [ "$status" -eq 0 ]
  python3 - "$PS_FIXTURE_LOG" <<'PYTEST'
import json,sys
calls=[json.loads(x) for x in open(sys.argv[1])]
assert any(x['operation']=='get_url' for x in calls)
repo=next(x['arguments'] for x in calls if x['operation']=='apt_repository')
assert '/ubuntu/24.04/prod noble main' in repo['repo']
upgrade=next(x['arguments'] for x in calls if x['operation']=='apt' and x['arguments'].get('name')=='powershell')
assert upgrade['state']=='latest' and upgrade['only_upgrade'] is True and upgrade['update_cache'] is True
PYTEST
}
@test 'existing Microsoft repository is retained and current package reports no change' {
  export PS_FIXTURE_SOURCE=True PS_FIXTURE_CURRENT=1
  run_package_fixture
  [ "$status" -eq 0 ]
  [[ "$output" == *'changed=0'* ]]
  ! grep -q 'apt_repository\|get_url' "$PS_FIXTURE_LOG"
}
@test 'held packages or repository failures propagate through the production task' {
  export PS_FIXTURE_SOURCE=True PS_FIXTURE_FAILURE=1
  run_package_fixture
  [ "$status" -ne 0 ]
  [[ "$output" == *'package hold or repository failure'* ]]
}
@test 'Debian source uses the detected major release and codename' {
  run_package_fixture -e '{"ansible_facts":{"architecture":"x86_64","distribution":"Debian","distribution_version":"13.1","distribution_major_version":"13","distribution_release":"trixie"}}'
  [ "$status" -eq 0 ]
  grep -q '/debian/13/prod trixie main' "$PS_FIXTURE_LOG"
}
