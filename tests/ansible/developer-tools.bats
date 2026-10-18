#!/usr/bin/env bats
load '../test_helper'

setup() {
  if ! command -v node >/dev/null || ! command -v npm >/dev/null || ! command -v ansible-playbook >/dev/null; then
    skip "Node, npm, and Ansible are required for production-task fixtures"
  fi
  export TOOL_FIXTURE="$BATS_TEST_TMPDIR/tools"
  mkdir -p "$TOOL_FIXTURE"
  python3 "$REPO_ROOT/tests/fixtures/developer-tools/setup.py" "$TOOL_FIXTURE"
  export FIXTURE_NODE_VERSION
  FIXTURE_NODE_VERSION="$(cat "$TOOL_FIXTURE/node-version")"
  export ANSIBLE_LOCAL_TEMP="$BATS_TEST_TMPDIR/ansible-local"
  export ANSIBLE_REMOTE_TEMP="$BATS_TEST_TMPDIR/ansible-remote"
  export ANSIBLE_ROLES_PATH="$REPO_ROOT/linux/ansible/roles"
  cat > "$TOOL_FIXTURE/play.yml" <<YAML
- hosts: localhost
  connection: local
  gather_facts: false
  vars:
    ansible_python_interpreter: /usr/bin/python3
    ansible_facts:
      user_id: fixture
      python:
        executable: /usr/bin/python3
    resolved_target_user: fixture
    resolved_target_home: "$TOOL_FIXTURE/home"
    nvm_dir: "$TOOL_FIXTURE/custom nvm"
    target_user_environment:
      HOME: "$TOOL_FIXTURE/home"
      PATH: "$TOOL_FIXTURE/bin"
      TOOL_FIXTURE: "$TOOL_FIXTURE"
      FIXTURE_NODE_VERSION: "$FIXTURE_NODE_VERSION"
      BASH_ENV: "$TOOL_FIXTURE/profile"
    update_apt: false
    update_snap: false
    update_flatpak: false
  roles:
    - system_updates
YAML
  mkdir -p "$TOOL_FIXTURE/home"
  printf 'touch "$TOOL_FIXTURE/profile-loaded"\n' > "$TOOL_FIXTURE/profile"
}

run_tools() {
  run ansible-playbook -i localhost, "$TOOL_FIXTURE/play.yml" "$@"
  printf '%s\n' "$output" > "$BATS_TEST_TMPDIR/ansible-output.log"
}

assert_migrated() {
  [ "$(cat "$TOOL_FIXTURE/custom nvm/default")" = "$FIXTURE_NODE_VERSION" ]
  [ -f "$TOOL_FIXTURE/custom nvm/versions/node/v20.0.0/bin/node" ]
  [ -L "$TOOL_FIXTURE/custom nvm/versions/node/$FIXTURE_NODE_VERSION/lib/node_modules/local-tool" ]
  python3 - "$TOOL_FIXTURE" "$FIXTURE_NODE_VERSION" <<'PY'
import json, pathlib, sys
root=pathlib.Path(sys.argv[1])
data=json.loads((root/'custom nvm/versions/node'/sys.argv[2]/'packages.json').read_text())
assert 'tool' in data and '@openai/codex' in data
calls=[json.loads(line) for line in (root/'npm-calls.jsonl').read_text().splitlines()]
assert all('--global' in call['args'] or call['args'][0]=='view' for call in calls)
assert not any('local-tool@' in ' '.join(call['args']) for call in calls)
PY
}

@test "developer production tasks migrate a custom nvm default and preserve links and old runtimes" {
  run_tools
  [ "$status" -eq 0 ]
  assert_migrated
  [ ! -f "$TOOL_FIXTURE/profile-loaded" ]
}

@test "developer production tasks migrate into an already installed LTS and can run repeatedly" {
  cp -a "$TOOL_FIXTURE/destination" "$TOOL_FIXTURE/custom nvm/versions/node/$FIXTURE_NODE_VERSION"
  run_tools
  [ "$status" -eq 0 ]
  assert_migrated
  : > "$TOOL_FIXTURE/npm-calls.jsonl"
  run_tools
  [ "$status" -eq 0 ]
  assert_migrated
  ! grep -q '"install"' "$TOOL_FIXTURE/npm-calls.jsonl"
  [[ "$output" == *"changed=0"* ]]
}

@test "check mode does not load nvm or execute npm or download tools" {
  run_tools --check
  [ "$status" -eq 0 ]
  [ ! -f "$TOOL_FIXTURE/nvm-calls" ]
  [ ! -f "$TOOL_FIXTURE/npm-calls.jsonl" ]
}

@test "missing developer tools are skipped without installation" {
  rm "$TOOL_FIXTURE/custom nvm/nvm.sh"
  run_tools
  [ "$status" -eq 0 ]
  [ ! -f "$TOOL_FIXTURE/npm-calls.jsonl" ]
}

@test "npm tag selects npm updates without changing nvm or Codex" {
  run_tools --tags npm
  [ "$status" -eq 0 ]
  [ "$(cat "$TOOL_FIXTURE/custom nvm/default")" = v20.0.0 ]
  python3 - "$TOOL_FIXTURE" <<'PY'
import json, pathlib, sys
root=pathlib.Path(sys.argv[1]); data=json.loads((root/'custom nvm/versions/node/v20.0.0/packages.json').read_text())
assert data['npm']['version']=='1.0.0' # nvm's compatible updater owns npm
assert data['tool']['version']=='2.0.0'
assert data['@openai/codex']['version']=='1.0.0'
PY
}

@test "Codex control remains independent of npm updates" {
  run_tools -e '{"update_nvm":false,"update_npm":false}' --tags codex
  [ "$status" -eq 0 ]
  python3 - "$TOOL_FIXTURE" <<'PY'
import json, pathlib, sys
root=pathlib.Path(sys.argv[1]); data=json.loads((root/'custom nvm/versions/node/v20.0.0/packages.json').read_text())
assert data['tool']['version']=='1.0.0'
assert data['@openai/codex']['version']=='2.0.0'
PY
}

@test "malformed inventory stops migration before default changes" {
  touch "$TOOL_FIXTURE/malformed"
  run_tools
  [ "$status" -ne 0 ]
  [ "$(cat "$TOOL_FIXTURE/custom nvm/default")" = v20.0.0 ]
  [ ! -d "$TOOL_FIXTURE/custom nvm/versions/node/$FIXTURE_NODE_VERSION" ]
  rm "$TOOL_FIXTURE/malformed"
  touch "$TOOL_FIXTURE/invalid-package"
  run_tools
  [ "$status" -ne 0 ]
  [ "$(cat "$TOOL_FIXTURE/custom nvm/default")" = v20.0.0 ]
  [ ! -d "$TOOL_FIXTURE/custom nvm/versions/node/$FIXTURE_NODE_VERSION" ]
}

@test "failed npm migration keeps the old default" {
  touch "$TOOL_FIXTURE/fail-install"
  run_tools
  [ "$status" -ne 0 ]
  [[ "$output" == *"npm migrate failed: npm install failed"* ]]
  [ "$(cat "$TOOL_FIXTURE/custom nvm/default")" = v20.0.0 ]
}

@test "incompatible package engines fail without registry installs" {
  touch "$TOOL_FIXTURE/incompatible"
  run_tools -e '{"update_nvm":false}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"npm update failed: Package requires an incompatible Node engine"* ]]
  ! grep -q '"install"' "$TOOL_FIXTURE/npm-calls.jsonl"
}

@test "packages without engines update through production tasks" {
  for metadata in '"2.0.0"' '["2.0.0"]' '[{"version":"2.0.0","engines":{"node":">=14"}}]'; do
    printf '%s\n' "$metadata" > "$TOOL_FIXTURE/metadata-response"
    run_tools -e '{"update_nvm":false}'
    [ "$status" -eq 0 ]
  done
  python3 - "$TOOL_FIXTURE" <<'PY'
import json, pathlib, sys
root=pathlib.Path(sys.argv[1])
data=json.loads((root/'custom nvm/versions/node/v20.0.0/packages.json').read_text())
assert data['tool']['version']=='2.0.0'
assert data['@openai/codex']['version']=='2.0.0'
assert data['local-tool']['link']
PY
}

@test "malformed registry metadata stops updates without installs" {
  touch "$TOOL_FIXTURE/bad-metadata"
  run_tools -e '{"update_nvm":false}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"npm update failed: Invalid npm registry metadata"* ]]
  ! grep -q '"install"' "$TOOL_FIXTURE/npm-calls.jsonl"
}

@test "unexpected npm errors do not disclose private subprocess output" {
  cat >> "$TOOL_FIXTURE/custom nvm/versions/node/v20.0.0/npm-cli.js" <<'JS'
process.stderr.write('private-package private-path private-token');
process.exitCode = 7;
JS
  run_tools
  [ "$status" -ne 0 ]
  [[ "$output" == *"npm inventory failed: npm ls failed"* ]]
  [[ "$output" != *"private-package"* ]]
  [[ "$output" != *"private-path"* ]]
  [[ "$output" != *"private-token"* ]]
}

@test "unexpected worker exceptions do not disclose filesystem paths" {
  rm -r "$TOOL_FIXTURE/custom nvm/versions/node/v20.0.0/lib/node_modules/tool"
  run_tools
  [ "$status" -ne 0 ]
  [[ "$output" == *"npm inventory failed: worker execution or response validation failed"* ]]
  [[ "$output" != *"ENOENT"* ]]
  [[ "$output" != *"$TOOL_FIXTURE"* ]]
}

@test "skipping npm tag retains nvm migration and independent Codex updates" {
  run_tools --skip-tags npm
  [ "$status" -eq 0 ]
  assert_migrated
  python3 - "$TOOL_FIXTURE" "$FIXTURE_NODE_VERSION" <<'PY'
import json, pathlib, sys
root=pathlib.Path(sys.argv[1]); data=json.loads((root/'custom nvm/versions/node'/sys.argv[2]/'packages.json').read_text())
assert data['tool']['version']=='1.0.0'
assert data['@openai/codex']['version']=='2.0.0'
PY
}

@test "npm without nvm updates itself and preserves linked tools" {
  rm "$TOOL_FIXTURE/custom nvm/nvm.sh"
  ln -s "$TOOL_FIXTURE/custom nvm/versions/node/v20.0.0/bin/node" "$TOOL_FIXTURE/bin/node"
  ln -s "$TOOL_FIXTURE/custom nvm/versions/node/v20.0.0/npm-cli.js" "$TOOL_FIXTURE/bin/npm"
  run_tools --tags npm
  [ "$status" -eq 0 ]
  python3 - "$TOOL_FIXTURE" <<'PY'
import json, pathlib, sys
root=pathlib.Path(sys.argv[1]); data=json.loads((root/'custom nvm/versions/node/v20.0.0/packages.json').read_text())
assert data['npm']['version']=='2.0.0'
assert data['tool']['version']=='2.0.0'
calls=[json.loads(line) for line in (root/'npm-calls.jsonl').read_text().splitlines()]
assert any(call['cli'].endswith('/lib/node_modules/npm/bin/npm-cli.js') and call['args'][0]=='view' and call['args'][1]=='tool@latest' for call in calls)
assert data['@openai/codex']['version']=='1.0.0'
assert data['local-tool']['link']
PY
}

@test "nvm refuses local changes before installing LTS" {
  cat > "$TOOL_FIXTURE/bin/git" <<'SH'
#!/bin/sh
case "$*" in *status*) echo modified;; esac
SH
  run_tools
  [ "$status" -ne 0 ]
  [ "$(cat "$TOOL_FIXTURE/custom nvm/default")" = v20.0.0 ]
  ! grep -q '^install ' "$TOOL_FIXTURE/nvm-calls"
}

@test "conflicting destination links fail without overwriting them" {
  cp -a "$TOOL_FIXTURE/destination" "$TOOL_FIXTURE/custom nvm/versions/node/$FIXTURE_NODE_VERSION"
  mkdir -p "$TOOL_FIXTURE/custom nvm/versions/node/$FIXTURE_NODE_VERSION/lib/node_modules/local-tool"
  python3 - "$TOOL_FIXTURE" "$FIXTURE_NODE_VERSION" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1])/'custom nvm/versions/node'/sys.argv[2]/'packages.json'
data=json.loads(p.read_text()); data['local-tool']={'version':'1.0.0'}; p.write_text(json.dumps(data))
PY
  run_tools
  [ "$status" -ne 0 ]
  [ "$(cat "$TOOL_FIXTURE/custom nvm/default")" = v20.0.0 ]
  [ ! -L "$TOOL_FIXTURE/custom nvm/versions/node/$FIXTURE_NODE_VERSION/lib/node_modules/local-tool" ]
}

@test "standalone Codex updates independently after a malformed npm inventory" {
  mkdir -p "$TOOL_FIXTURE/home/.codex/packages/standalone/releases/fixture/bin"
  cat > "$TOOL_FIXTURE/home/.codex/packages/standalone/releases/fixture/bin/codex" <<'SH'
#!/bin/sh
case "$1" in
  --help) printf '  update    Apply update\n';;
  --version) printf 'codex-cli 1.0.0\n';;
  update) touch "$TOOL_FIXTURE/codex-updated";;
  *) exit 2;;
esac
SH
  chmod +x "$TOOL_FIXTURE/home/.codex/packages/standalone/releases/fixture/bin/codex"
  ln -s "$TOOL_FIXTURE/home/.codex/packages/standalone/releases/fixture/bin/codex" "$TOOL_FIXTURE/bin/codex"
  touch "$TOOL_FIXTURE/malformed"
  run_tools
  [ "$status" -ne 0 ]
  [ -f "$TOOL_FIXTURE/codex-updated" ]
}

@test "ambiguous Codex binaries are skipped without invocation" {
  cat > "$TOOL_FIXTURE/bin/codex" <<'SH'
#!/bin/sh
touch "$TOOL_FIXTURE/codex-invoked"
exit 3
SH
  chmod +x "$TOOL_FIXTURE/bin/codex"
  run_tools --tags codex
  [ "$status" -eq 0 ]
  [ ! -f "$TOOL_FIXTURE/codex-invoked" ]
}

@test "real installed npm preserves linked project files and global executable without registry access" {
  local project="$TOOL_FIXTURE/real-project"
  mkdir -p "$project" "$TOOL_FIXTURE/real-prefix/lib/node_modules"
  cat > "$project/package.json" <<'JSON'
{"name":"fixture-linked-tool","version":"1.0.0","bin":{"fixture-linked-tool":"cli.js"},"scripts":{"prepare":"node -e \"require('fs').writeFileSync('prepare-ran','bad')\""}}
JSON
  printf '#!/usr/bin/env node\nconsole.log("linked fixture");\n' > "$project/cli.js"
  printf 'retained lock sentinel\n' > "$project/package-lock.json"
  cp "$project/package.json" "$TOOL_FIXTURE/manifest-before"
  python3 - "$TOOL_FIXTURE" <<'PY'
import json, pathlib, sys
r=pathlib.Path(sys.argv[1])
(r/'request.json').write_text(json.dumps({'action':'migrate', 'cli':(r/'real-npm-cli').read_text(), 'packages':{'fixture-linked-tool':{'version':'1.0.0','link':str(r/'real-project')}}}))
PY
  run bash -c 'env HOME="$1/home" npm_config_prefix="$1/real-prefix" npm_config_cache="$1/cache" npm_config_offline=true npm_config_audit=false npm_config_fund=false npm_config_userconfig="$1/empty-user-npmrc" npm_config_globalconfig="$1/empty-global-npmrc" "$(cat "$1/real-node")" "$2/shared/npm-tools.cjs" < "$1/request.json"' fixture "$TOOL_FIXTURE" "$REPO_ROOT"
  [ "$status" -eq 0 ]
  cmp "$project/package.json" "$TOOL_FIXTURE/manifest-before"
  [ "$(cat "$project/package-lock.json")" = 'retained lock sentinel' ]
  [ ! -e "$project/prepare-ran" ]
  [ ! -e "$project/node_modules" ]
  [ -L "$TOOL_FIXTURE/real-prefix/lib/node_modules/fixture-linked-tool" ]
  [ -L "$TOOL_FIXTURE/real-prefix/bin/fixture-linked-tool" ]
}

@test "real npm accepts a release without engines from an isolated registry" {
  run python3 - "$TOOL_FIXTURE" "$REPO_ROOT" <<'PY'
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from threading import Thread
import json, os, subprocess, sys

root, repo = map(Path, sys.argv[1:])
package = root/'metadata-prefix/lib/node_modules/@openai/codex'
package.mkdir(parents=True)
manifest = {'name':'@openai/codex', 'version':'1.0.0'}
(package/'package.json').write_text(json.dumps(manifest))
requests = []
class Registry(BaseHTTPRequestHandler):
    def do_GET(self):
        requests.append(self.path)
        if self.path.lower() not in ('/@openai%2fcodex', '/@openai/codex'):
            self.send_error(404)
            return
        payload = json.dumps({'name':'@openai/codex', 'dist-tags':{'latest':'1.0.0'},
                              'versions':{'1.0.0':manifest}}).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)
    def log_message(self, *_):
        pass
server = HTTPServer(('127.0.0.1', 0), Registry)
thread = Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    env = {key:value for key,value in os.environ.items()
           if not key.lower().startswith('npm_config_')}
    env.update(HOME=str(root/'home'), npm_config_prefix=str(root/'metadata-prefix'),
               npm_config_cache=str(root/'metadata-cache'),
               npm_config_registry=f'http://127.0.0.1:{server.server_port}',
               npm_config_userconfig=str(root/'empty-user-npmrc'),
               npm_config_globalconfig=str(root/'empty-global-npmrc'),
               npm_config_audit='false', npm_config_fund='false', npm_config_update_notifier='false')
    node = (root/'real-node').read_text()
    cli = (root/'real-npm-cli').read_text()
    # Prove real npm emits one of the no-engines shapes used by the fixtures.
    metadata = subprocess.run([node, cli, 'view', '@openai/codex@latest', 'version', 'engines', '--json'],
                              env=env, text=True, capture_output=True, check=True, timeout=30)
    assert json.loads(metadata.stdout) in ('1.0.0', ['1.0.0']), metadata.stdout
    for engine in (None, '>=14', '>=999'):
        if engine:
            manifest['engines'] = {'node':engine}
        result = subprocess.run([node, str(repo/'shared/npm-tools.cjs')],
                                input=json.dumps({'cli':cli, 'action':'update', 'npm':False, 'codex':True}),
                                env=env, text=True, capture_output=True, timeout=30)
        if engine == '>=999':
            assert result.returncode != 0
            assert result.stderr.strip() == 'Package requires an incompatible Node engine'
        else:
            assert result.returncode == 0, result.stderr
            assert json.loads(result.stdout) == {}
    assert json.loads((package/'package.json').read_text()) == {'name':'@openai/codex', 'version':'1.0.0'}
    assert requests and all('codex' in request for request in requests)
finally:
    server.shutdown()
    server.server_close()
    thread.join()
PY
  printf '%s\n' "$output"
  [ "$status" -eq 0 ]
}

@test "script nvm upgrades preserve installation method and reject modified files before replacement" {
  run python3 - "$REPO_ROOT" "$TOOL_FIXTURE" <<'PY'
from pathlib import Path
import sys

repo, fixture = map(Path, sys.argv[1:])
worker = repo / 'linux/ansible/roles/system_updates/files/developer_tools.py'
namespace = {'__name__': 'fixture_import'}
exec(compile(worker.read_text(), str(worker), 'exec'), namespace)
assets = {}
for version in ('0.40.7', '0.40.8'):
    assets['v' + version] = {
        'nvm.sh': ('nvm() { echo ' + version + '; }\n').encode(),
        'nvm-exec': ('#!/bin/sh\n# exact fixture ' + version + '\n').encode(),
        'bash_completion': ('# completion fixture ' + version + '\n').encode(),
    }
requested = []
def download(tag, name):
    requested.append((tag, name))
    return assets[tag][name]
namespace['download'] = download
location = fixture / 'script-nvm'
location.mkdir()
for name, content in assets['v0.40.7'].items():
    (location / name).write_bytes(content)
    (location / name).chmod(0o755 if name == 'nvm-exec' else 0o644)
(location / 'custom-alias').write_text('retained')
config = {'nvm_dir': str(location), 'nvm_release': 'v0.40.8'}
assert namespace['update_nvm'](config)
assert not (location / '.git').exists()
assert (location / 'custom-alias').read_text() == 'retained'
for name, content in assets['v0.40.8'].items():
    assert (location / name).read_bytes() == content
assert (location / 'nvm-exec').stat().st_mode & 0o777 == 0o755
(location / 'nvm-exec').write_bytes(b'local modification')
before = {p.name:p.read_bytes() for p in location.iterdir()}
requested.clear()
try:
    namespace['update_nvm'](config)
except RuntimeError as error:
    assert 'modified' in str(error)
else:
    raise AssertionError('Modified script installation was overwritten')
assert {p.name:p.read_bytes() for p in location.iterdir()} == before
PY
  [ "$status" -eq 0 ]
}
