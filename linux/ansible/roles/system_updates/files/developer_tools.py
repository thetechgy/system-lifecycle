"""Internal Ansible worker; no profiles, shell interpolation, or project installs."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request


# Only fixed worker messages may leave the private subprocess output. npm and
# filesystem exceptions can include configuration, package names, or local paths.
NPM_ERRORS = {
    'Malformed npm inventory', 'Invalid npm root', 'Malformed npm package',
    'Unverifiable npm link', 'Global package preservation verification failed',
    'Linked package name mismatch', 'Linked command leaves its package directory',
    'Linked command is missing', 'Conflicting global package link',
    'Linked command verification failed', 'Invalid npm registry metadata',
    'Package requires an incompatible Node engine', 'npm update verification failed',
    'Cannot resolve selected npm CLI',
    *(f'npm {verb} failed' for verb in ('ls', 'root', 'view', 'install', 'cache')),
}


def run(args, env=None):
    result = subprocess.run(args, text=True, capture_output=True, env=env, check=False)
    if result.returncode:
        raise RuntimeError(f'{Path(args[0]).name} command failed ({result.returncode})')
    return result.stdout.strip()


def download(tag, name):
    url = f'https://raw.githubusercontent.com/nvm-sh/nvm/{tag}/{name}'
    with urllib.request.urlopen(url, timeout=60) as response:
        return response.read()


def nvm(config, *args):
    env = dict(os.environ, NVM_DIR=config['nvm_dir'])
    # nvm itself is not nounset-safe. Load only its explicit installation file.
    return run(['/bin/bash', '--noprofile', '--norc', '-c',
                'source "$NVM_DIR/nvm.sh" --no-use || exit; nvm "$@"', 'nvm', *args], env)


def update_nvm(config):
    directory = Path(config['nvm_dir'])
    target = config['nvm_release']
    current = 'v' + nvm(config, '--version')
    if not re.fullmatch(r'v\d+\.\d+\.\d+', current) or not re.fullmatch(r'v\d+\.\d+\.\d+', target):
        raise RuntimeError('Invalid stable nvm release')
    if tuple(map(int, current[1:].split('.'))) > tuple(map(int, target[1:].split('.'))):
        raise RuntimeError('Pinned nvm release is older than installed nvm; update nvm_release')
    if (directory / '.git').exists():
        git = ['git', '-C', str(directory)]
        if run(git + ['status', '--porcelain']):
            raise RuntimeError('nvm has local modifications; refusing to overwrite')
        # A clean worktree alone does not exclude locally committed changes.
        run(git + ['fetch', '--no-tags', 'https://github.com/nvm-sh/nvm.git',
                   f'refs/tags/{current}'])
        if run(git + ['rev-parse', 'HEAD']) != run(git + ['rev-parse', 'FETCH_HEAD^{commit}']):
            raise RuntimeError('nvm HEAD differs from its upstream release')
        if current != target:
            run(git + ['fetch', '--no-tags', 'https://github.com/nvm-sh/nvm.git', f'refs/tags/{target}'])
            run(git + ['checkout', '--detach', 'FETCH_HEAD'])
    else:
        # Script installs have no git history: compare all installed upstream files
        # with the reported release before replacing any of them.
        names = ['nvm.sh', 'nvm-exec', 'bash_completion']
        for name in names:
            file = directory / name
            if file.is_symlink() or not file.is_file() or file.read_bytes() != download(current, name):
                raise RuntimeError('Unrecognized or modified script nvm installation')
        if current != target:
            replacements = {name: download(target, name) for name in names}
            for name, content in replacements.items():
                file = directory / name
                with tempfile.NamedTemporaryFile(dir=directory, delete=False) as temporary:
                    temporary.write(content)
                    temporary_path = Path(temporary.name)
                temporary_path.chmod(file.stat().st_mode & 0o777)
                temporary_path.replace(file)
    if nvm(config, '--version') != target[1:]:
        raise RuntimeError('nvm release verification failed')
    return current != target


def runtime(config, alias):
    executable = nvm(config, 'which', alias)
    if not Path(executable).is_absolute() or not Path(executable).is_file():
        raise RuntimeError('Cannot resolve nvm Node executable')
    return executable


def npm_cli(node):
    candidate = Path(node).parent / 'npm'
    found = str(candidate) if candidate.exists() else shutil.which('npm')
    if not found:
        return None
    cli = str(Path(found).resolve())
    if not cli.endswith('.js'):
        raise RuntimeError('Unrecognized npm launcher')
    return cli


def packages(config, node, cli, action, **options):
    env = dict(os.environ, PATH=str(Path(node).parent) + os.pathsep + os.environ['PATH'])
    result = subprocess.run([node, '-e', config['npm_worker']],
                            input=json.dumps(dict(cli=cli, action=action, **options)),
                            text=True, capture_output=True, env=env, check=False)
    # node -e has no require.main: invoke the exported entry explicitly.
    if result.returncode:
        detail = result.stderr.strip()
        if detail not in NPM_ERRORS:
            detail = 'worker execution or response validation failed'
        raise RuntimeError(f'npm {action} failed: {detail}')
    return json.loads(result.stdout)


def update_runtime(config):
    changed = False
    has_nvm = (Path(config['nvm_dir']) / 'nvm.sh').is_file()
    node = shutil.which('node')
    if not (config['nvm'] or config['npm'] or config['codex']):
        return
    if has_nvm:
        installed = list(Path(config['nvm_dir']).glob('versions/*/*/bin/node'))
        node = runtime(config, 'default') if installed else None
    if has_nvm and config['nvm']:
        old_cli = npm_cli(node) if node else None
        before = packages(config, node, old_cli, 'inventory') if old_cli else {}
        changed = update_nvm(config) or changed
        target = nvm(config, 'version-remote', '--lts')
        if not re.fullmatch(r'v\d+\.\d+\.\d+', target):
            raise RuntimeError('Invalid LTS resolution')
        nvm(config, 'install', '--skip-default-packages', target)
        selected = runtime(config, target)
        changed = selected != node or changed
        node = selected
        cli = npm_cli(node)
        if not cli:
            raise RuntimeError('LTS npm is missing')
        destination_before = packages(config, node, cli, 'inventory')
        packages(config, node, cli, 'migrate', packages=before)
        changed = destination_before != packages(config, node, cli, 'inventory') or changed
        nvm(config, 'alias', 'default', target)
        if runtime(config, 'default') != node or run([node, '--version']) != target:
            raise RuntimeError('Node default verification failed')
    if node:
        cli = npm_cli(node)
        if cli:
            inventory = packages(config, node, cli, 'inventory')
            if has_nvm and config['npm'] and not inventory.get('npm', {}).get('link'):
                # nvm chooses the newest npm compatible with this Node runtime.
                env = dict(os.environ, NVM_DIR=config['nvm_dir'])
                run(['/bin/bash', '--noprofile', '--norc', '-c',
                     'source "$NVM_DIR/nvm.sh" --no-use || exit; '
                     'nvm use --silent default || exit; nvm install-latest-npm'], env)
            packages(config, node, cli, 'update', npm=config['npm'], codex=config['codex'],
                     compatible_npm=has_nvm)
            changed = inventory != packages(config, node, cli, 'inventory') or changed
    if changed:
        print('CHANGED')
    print('Developer runtime phase completed (missing tools skipped)')


def update_standalone(config, original):
    if not original:
        return
    resolved = Path(original).resolve()
    if 'node_modules/@openai/codex/' in str(resolved):
        return
    codex_home = Path(config['codex_home'])
    standalone_root = codex_home / 'packages/standalone'
    if standalone_root / 'releases' not in resolved.parents:
        print('Codex source is ambiguous; skipped standalone update')
        return
    env = dict(os.environ, CODEX_HOME=str(codex_home),
               CODEX_INSTALL_DIR=str(Path(original).parent), CODEX_NON_INTERACTIVE='true')
    help_text = run([original, '--help'], env)
    if re.search(r'^\s*update\s', help_text, re.MULTILINE):
        run([original, 'update'], env)
    else:
        # Official unattended fallback for recognized older standalone layouts.
        with urllib.request.urlopen('https://chatgpt.com/codex/install.sh', timeout=60) as response:
            content = response.read()
        with tempfile.TemporaryDirectory() as temporary:
            installer = Path(temporary) / 'install.sh'
            installer.write_bytes(content)
            env = dict(os.environ, CODEX_HOME=str(codex_home),
                       CODEX_INSTALL_DIR=str(Path(original).parent),
                       CODEX_NON_INTERACTIVE='true', CODEX_RELEASE='latest',
                       CODEX_INSTALL_DAEMON_ONLY='0', CODEX_INSTALL_DEFER_SELECTION='0')
            run(['/bin/sh', str(installer)], env)
    version = run([original, '--version'], env)
    if not re.fullmatch(r'codex(?:-cli)? \d+\.\d+\.\d+(?:[-+][\w.-]+)?', version):
        raise RuntimeError('Codex version verification failed')
    if standalone_root / 'releases' not in Path(original).resolve().parents:
        raise RuntimeError('Codex installation layout changed')
    print('CHANGED')
    print('Standalone Codex update verified')


def main():
    config = json.load(sys.stdin)
    # Noninteractive Bash can source BASH_ENV even with --noprofile/--norc.
    os.environ.pop('BASH_ENV', None)
    os.environ.pop('ENV', None)
    # Same shared worker as Windows; call its exported function for node -e.
    config['npm_worker'] += ('\nconst workerMain = module.exports.main;'
                             'Promise.resolve().then(() => workerMain(JSON.parse(require("fs").readFileSync(0,"utf8"))))'
                             '.then(result => process.stdout.write(JSON.stringify(result)))'
                             '.catch(error => { process.stderr.write(String(error.message)); process.exitCode = 1; });')
    original = shutil.which('codex')
    errors = []
    try:
        update_runtime(config)
    except OSError:
        errors.append('Developer runtime I/O or network operation failed')
    except (ValueError, RuntimeError) as error:
        errors.append(str(error))
    if config['codex']:
        try:
            update_standalone(config, original)
        except OSError:
            errors.append('Standalone Codex I/O or network operation failed')
        except (ValueError, RuntimeError) as error:
            errors.append(str(error))
    for error in errors:
        print(error, file=sys.stderr)
    return bool(errors)


if __name__ == '__main__':
    sys.exit(main())
