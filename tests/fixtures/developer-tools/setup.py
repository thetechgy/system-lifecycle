"""Build isolated runtimes; use installed Node only as a JS interpreter."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(sys.argv[1])
fixtures = Path(__file__).parent
real_node = shutil.which('node')
real_npm = Path(shutil.which('npm')).resolve()
semver = subprocess.check_output([real_node, '-e', 'console.log(require.resolve("semver", {paths:[process.argv[1]]}))', str(real_npm.parent)], text=True).strip()
semver_root = Path(semver).parent
while not (semver_root / 'package.json').exists():
    semver_root = semver_root.parent
version = subprocess.check_output([real_node, '--version'], text=True).strip()
(root / 'node-version').write_text(version)
(root / 'real-node').write_text(real_node)
(root / 'real-npm-cli').write_text(str(real_npm))
(root / 'bin').mkdir()
# Expose only the non-tool commands needed by the nvm/Codex fixtures.
# A runner's system node/npm must never be discovered by missing-tool tests.
for name in ('cat', 'cp', 'touch', 'uname'):
    (root / 'bin' / name).symlink_to(shutil.which(name))
(root / 'bin/git').write_text('#!/bin/sh\ncase "$*" in *rev-parse*) echo fixture-head;; esac\n')
(root / 'bin/git').chmod(0o755)
nvm_dir = root / 'custom nvm'
(nvm_dir / '.git').mkdir(parents=True)
(nvm_dir / 'versions/node').mkdir(parents=True)
shutil.copy(fixtures / 'nvm.sh', nvm_dir / 'nvm.sh')
(nvm_dir / 'default').write_text('v20.0.0')
(root / 'linked').mkdir()
(root / 'linked/package.json').write_text('{"name":"local-tool","version":"1.0.0"}')
for destination, runtime_version in [(nvm_dir / 'versions/node/v20.0.0', 'v20.0.0'), (root / 'destination', version)]:
    (destination / 'bin').mkdir(parents=True)
    # Quote the already-resolved interpreter for paths containing spaces.
    import shlex
    (destination / 'bin/node').write_text('#!/bin/sh\nif [ "$1" = --version ]; then echo ' + runtime_version + '; else exec ' + shlex.quote(real_node) + ' "$@"; fi\n')
    (destination / 'bin/node').chmod(0o755)
    shutil.copy(fixtures / 'npm-cli.cjs', destination / 'npm-cli.js')
    (destination / 'bin/npm').symlink_to('../npm-cli.js')
    (destination / 'node_modules').mkdir()
    (destination / 'node_modules/semver').symlink_to(semver_root)
    packages = {'npm': {'version': '1.0.0'}}
    if runtime_version == 'v20.0.0':
        packages.update({'tool': {'version': '1.0.0'}, '@openai/codex': {'version': '1.0.0'}, 'local-tool': {'version': '1.0.0', 'link': True}})
    (destination / 'packages.json').write_text(json.dumps(packages))
    for name, entry in packages.items():
        location = destination / 'globals' / name
        location.parent.mkdir(parents=True, exist_ok=True)
        if entry.get('link'):
            location.symlink_to(root / 'linked')
        else:
            location.mkdir()
