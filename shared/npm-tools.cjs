'use strict';
// Shared by both production updaters. Always execute npm with the selected Node.
const fs = require('fs');
const path = require('path');
const cp = require('child_process');
const packageName = /^(?:@(?![._])[a-z0-9_.-]+\/)?(?![._])[a-z0-9_.-]+$/i;
const version = /^\d+\.\d+\.\d+(?:-[\w.-]+)?(?:\+[\w.-]+)?$/;
function run(cli, args) {
  const result = cp.spawnSync(process.execPath, [cli, ...args], {
    encoding: 'utf8', cwd: require('os').homedir(), env: process.env,
  });
  if (result.error || result.status !== 0) throw new Error(`npm ${args[0]} failed`);
  return result.stdout.trim();
}
function inventory(cli) {
  const data = JSON.parse(run(cli, ['ls', '--global', '--depth=0', '--long', '--json']));
  if (!data || typeof data !== 'object' || Array.isArray(data) || data.problems || data.error ||
      (data.dependencies !== undefined && (!data.dependencies || typeof data.dependencies !== 'object' || Array.isArray(data.dependencies)))) {
    throw new Error('Malformed npm inventory');
  }
  const root = run(cli, ['root', '--global']);
  if (!path.isAbsolute(root) || root.includes('\n')) throw new Error('Invalid npm root');
  const packages = Object.create(null);
  for (const [name, entry] of Object.entries(data.dependencies || {})) {
    if (!packageName.test(name) || name === '.' || name === '..' || !entry || !version.test(entry.version || '') || entry.missing || entry.invalid) {
      throw new Error('Malformed npm package');
    }
    const location = path.join(root, name);
    const stat = fs.lstatSync(location);
    const link = stat.isSymbolicLink() ? fs.realpathSync(location) : null;
    if (entry.link && !link) throw new Error('Unverifiable npm link');
    packages[name] = {version: entry.version, link};
  }
  return packages;
}
function verify(before, after, exact = false) {
  for (const [name, entry] of Object.entries(before)) {
    if (name === 'npm') continue;
    if (!after[name] || (entry.link && entry.link !== after[name].link) ||
        (!entry.link && after[name].link) || (exact && !entry.link && entry.version !== after[name].version)) {
      throw new Error('Global package preservation verification failed');
    }
  }
}
async function linkGlobal(cli, name, entry) {
  const manifest = JSON.parse(fs.readFileSync(path.join(entry.link, 'package.json'), 'utf8'));
  if (manifest.name !== name) throw new Error('Linked package name mismatch');
  // npm's installer can run prepare for folder dependencies even when scripts
  // are disabled. Link directly, using its bundled, version-matched bin linker.
  const binLinks = require(require.resolve('bin-links', {paths: [path.dirname(cli)]}));
  const root = run(cli, ['root', '--global']);
  if (!path.isAbsolute(root) || root.includes('\n')) throw new Error('Invalid npm root');
  const location = path.join(root, name);
  const options = {path: location, pkg: manifest, global: true, top: true, force: false};
  await binLinks.checkBins(options);
  for (const relative of Object.values(manifest.bin || {})) {
    const source = fs.realpathSync(path.resolve(entry.link, relative));
    const boundary = path.relative(entry.link, source);
    if (boundary === '..' || boundary.startsWith('..' + path.sep) || path.isAbsolute(boundary)) {
      throw new Error('Linked command leaves its package directory');
    }
    if (!fs.statSync(source).isFile()) throw new Error('Linked command is missing');
  }
  if (!fs.existsSync(location)) {
    fs.mkdirSync(path.dirname(location), {recursive: true});
    fs.symlinkSync(entry.link, location, process.platform === 'win32' ? 'junction' : 'dir');
  } else if (fs.realpathSync(location) !== entry.link) {
    throw new Error('Conflicting global package link');
  }
  await binLinks(options);
  const commands = binLinks.getPaths({...options, pkg: {...manifest, man: []}});
  if (commands.some(command => !fs.existsSync(command))) throw new Error('Linked command verification failed');
}
async function migrate(cli, before) {
  const current = inventory(cli);
  for (const [name, entry] of Object.entries(before)) {
    if (name === 'npm') continue;
    if (current[name]) {
      // A destination link or registry package must never be silently replaced.
      verify({[name]: entry}, current);
      if (entry.link) await linkGlobal(cli, name, entry);
      continue;
    }
    if (entry.link) {
      await linkGlobal(cli, name, entry);
    } else {
      run(cli, ['install', '--global', '--engine-strict', '--', `${name}@${entry.version}`]);
    }
    verify({[name]: entry}, inventory(cli), true);
  }
  verify(before, inventory(cli));
}

function installLatest(cli, name) {
  const response = JSON.parse(run(cli, ['view', `${name}@latest`, 'version', 'engines', '--json']));
  // npm 12 wraps a single release in an array; earlier npm versions unwrap it.
  const metadata = Array.isArray(response) && response.length === 1 ? response[0] : response;
  // npm unwraps a single returned field. Releases without engines therefore
  // produce a version string rather than {version, engines}.
  const info = typeof metadata === 'string' ? {version: metadata} : metadata;
  if (!info || Array.isArray(info) || !version.test(info.version || '') ||
      (info.engines !== undefined && (!info.engines || typeof info.engines !== 'object' || Array.isArray(info.engines)))) {
    throw new Error('Invalid npm registry metadata');
  }
  // npm ships semver; reuse the selected npm's engine evaluator, never download one.
  const semver = require(require.resolve('semver', {paths: [path.dirname(cli)]}));
  if (info.engines && info.engines.node && !semver.satisfies(process.version, info.engines.node)) {
    throw new Error('Package requires an incompatible Node engine');
  }
  const installed = inventory(cli)[name];
  if (installed && installed.version === info.version) return;
  run(cli, ['install', '--global', '--engine-strict', '--', `${name}@${info.version}`]);
  const updated = inventory(cli)[name];
  if (!updated || updated.version !== info.version) throw new Error('npm update verification failed');
}
async function main(input) {
  let cli = input.cli;
  if (!path.isAbsolute(cli) || !fs.existsSync(cli)) throw new Error('Cannot resolve selected npm CLI');
  if (input.action === 'inventory') return inventory(cli);
  if (input.action === 'migrate') { await migrate(cli, input.packages); return {}; }
  if (input.action === 'verify') { verify(input.packages, inventory(cli), true); return {}; }
  if (input.action === 'update') {
    const before = inventory(cli);
    if (input.npm) {
      if (!input.compatible_npm && !(before.npm && before.npm.link)) installLatest(cli, 'npm');
      if (!(before.npm && before.npm.link)) {
        const updatedCli = path.join(run(cli, ['root', '--global']), 'npm', 'bin', 'npm-cli.js');
        if (fs.existsSync(updatedCli)) cli = fs.realpathSync(updatedCli);
      }
      for (const [name, entry] of Object.entries(before)) {
        if (name !== 'npm' && name !== '@openai/codex' && !entry.link) installLatest(cli, name);
      }
    }
    if (input.codex && before['@openai/codex'] && !before['@openai/codex'].link) installLatest(cli, '@openai/codex');
    verify(before, inventory(cli));
    if (input.cleanup) run(cli, input.clean ? ['cache', 'clean', '--force'] : ['cache', 'verify']);
    return {};
  }
  throw new Error('Unknown npm operation');
}
if (require.main === module) {
  Promise.resolve().then(() => main(JSON.parse(fs.readFileSync(0, 'utf8'))))
    .then(result => process.stdout.write(JSON.stringify(result)))
    .catch(error => { process.stderr.write(`${error.message}\n`); process.exitCode = 1; });
}
module.exports = {main};
