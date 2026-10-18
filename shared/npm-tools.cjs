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
function migrate(cli, before) {
  const current = inventory(cli);
  for (const [name, entry] of Object.entries(before)) {
    if (name === 'npm') continue;
    if (current[name]) {
      // A destination link or registry package must never be silently replaced.
      verify({[name]: entry}, current);
      continue;
    }
    if (entry.link) {
      const manifest = JSON.parse(fs.readFileSync(path.join(entry.link, 'package.json'), 'utf8'));
      if (manifest.name !== name) throw new Error('Linked package name mismatch');
      run(cli, ['install', '--global', '--install-links=false', '--ignore-scripts', '--package-lock=false', '--no-save', '--', entry.link]);
    } else {
      run(cli, ['install', '--global', '--engine-strict', '--', `${name}@${entry.version}`]);
    }
    verify({[name]: entry}, inventory(cli), true);
  }
  verify(before, inventory(cli));
}
function installLatest(cli, name) {
  const info = JSON.parse(run(cli, ['view', `${name}@latest`, 'version', 'engines', '--json']));
  if (!info || !version.test(info.version || '')) throw new Error('Invalid npm registry metadata');
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
function main(input) {
  let cli = input.cli;
  if (!path.isAbsolute(cli) || !fs.existsSync(cli)) throw new Error('Cannot resolve selected npm CLI');
  if (input.action === 'inventory') return inventory(cli);
  if (input.action === 'migrate') { migrate(cli, input.packages); return {}; }
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
  try { process.stdout.write(JSON.stringify(main(JSON.parse(fs.readFileSync(0, 'utf8'))))); }
  catch (error) { process.stderr.write(`${error.message}\n`); process.exitCode = 1; }
}
module.exports = {main};
