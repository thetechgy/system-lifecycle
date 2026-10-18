'use strict';
// Local registry and prefix fixture. No command reaches a package registry.
const fs = require('fs');
const path = require('path');
const root = __dirname;
const args = process.argv.slice(2);
const statePath = path.join(root, 'packages.json');
const state = JSON.parse(fs.readFileSync(statePath));
const globals = path.join(root, 'globals');
fs.appendFileSync(process.env.TOOL_FIXTURE + '/npm-calls.jsonl', JSON.stringify({root, cli: process.argv[1], args}) + '\n');
if (fs.existsSync(process.env.TOOL_FIXTURE + '/fail-' + args[0])) process.exit(7);
function save() { fs.writeFileSync(statePath, JSON.stringify(state)); }
if (args[0] === 'ls') {
  if (fs.existsSync(process.env.TOOL_FIXTURE + '/malformed')) console.log('{');
  else if (fs.existsSync(process.env.TOOL_FIXTURE + '/invalid-package')) console.log(JSON.stringify({dependencies: {'@scope/..': {version: '1.0.0'}}}));
  else console.log(JSON.stringify({dependencies: state}));
} else if (args[0] === 'root') console.log(globals);
else if (args[0] === 'view') {
  console.log(JSON.stringify({version: '2.0.0', engines: {node: fs.existsSync(process.env.TOOL_FIXTURE + '/incompatible') ? '>=999' : '>=14'}}));
} else if (args[0] === 'install') {
  const spec = args[args.length - 1];
  if (path.isAbsolute(spec)) {
    const manifest = JSON.parse(fs.readFileSync(path.join(spec, 'package.json')));
    fs.mkdirSync(path.dirname(path.join(globals, manifest.name)), {recursive: true});
    fs.symlinkSync(spec, path.join(globals, manifest.name), 'dir');
    state[manifest.name] = {version: manifest.version, link: true};
    save();
    process.exit(0);
  }
  const index = spec.lastIndexOf('@');
  const name = spec.slice(0, index);
  const version = spec.slice(index + 1);
  state[name] = {version};
  fs.mkdirSync(path.join(globals, name), {recursive: true});
  if (name === 'npm') {
    fs.mkdirSync(path.join(globals, name, 'bin'), {recursive: true});
    fs.writeFileSync(path.join(globals, name, 'bin/npm-cli.js'), "require('../../../npm-cli.js');\n");
  }
  save();
} else process.exit(8);
