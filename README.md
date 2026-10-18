# System Lifecycle Management

[![ShellCheck](https://github.com/thetechgy/system-lifecycle/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/thetechgy/system-lifecycle/actions/workflows/shellcheck.yml)
[![Bats Tests](https://github.com/thetechgy/system-lifecycle/actions/workflows/test.yml/badge.svg)](https://github.com/thetechgy/system-lifecycle/actions/workflows/test.yml)

Personal automation for building, configuring, and maintaining Linux and Windows systems across their lifecycle. Linux automation is implemented with native Ansible playbooks; Windows automation remains PowerShell-based.

> **Note**: These scripts are created for my own use and reflect my personal preferences. You're welcome to use them or fork and adapt them to your needs, but **please review the code thoroughly before running** to understand what it will do to your system. I accept no liability for any damage or issues that may result from using these scripts.

## Repository Structure

```
system-lifecycle/
├── linux/                  # Linux automation
│   ├── ansible/            # Native Ansible playbooks and roles
│   ├── lib/                # Bootstrap Bash helpers used by ensure-ansible.sh
│   ├── ubuntu/             # Ansible-consumed Ubuntu config assets
│   ├── debian/             # Debian-specific scripts
│   └── common/             # Cross-distro scripts
├── windows/                # Windows scripts (PowerShell)
│   ├── lib/                # Shared PowerShell utilities
│   ├── update/             # System update scripts
│   ├── configure/          # Configuration scripts
│   └── install/            # Installation scripts
├── docs/                   # Documentation
└── tests/                  # Test scripts
```

## Quick Start

### First-Time Setup

Configure shell aliases for easy access to the Linux playbooks:

```bash
cd linux/ansible
./scripts/ensure-ansible.sh
ansible-playbook playbooks/configure-shell.yml
source ~/.bashrc
```

### Ubuntu System Update

```bash
# Using aliases after setup
linux-update
linux-update-check
linux-update-firmware

# Or run Ansible directly
cd linux/ansible
ansible-playbook -K playbooks/update-system.yml
ansible-playbook -K playbooks/update-system.yml --check
ansible-playbook -K playbooks/update-system.yml -e update_firmware=true
```

On Ubuntu 26.04, the shared playbook context detects sudo-rs and uses the installed
classic `sudo.ws` executable for Ansible password authentication. Ubuntu 24.04
continues using its default sudo. Explicit Ansible executable overrides take
precedence. Non-sudo become methods, including CLI-selected methods, bypass
detection. See [sudo compatibility and authentication checks](linux/ansible/README.md#sudo-compatibility)
for recovery instructions.

## Linux Ansible Model

The Linux playbooks use Ansible tags and extra variables instead of Bash flags.

### Update Playbook

`playbooks/update-system.yml` performs APT update/upgrade/dist-upgrade, Snap refresh, Flatpak system and user updates, target-user nvm/Node LTS, npm/global package, and Codex updates, optional Snap-based Node.js management, optional firmware updates, and APT cleanup.

```bash
ansible-playbook -K playbooks/update-system.yml --tags apt
ansible-playbook -K playbooks/update-system.yml -e update_snap=false
ansible-playbook -K playbooks/update-system.yml -e update_nodejs=true
ansible-playbook -K playbooks/update-system.yml -e apt_full_clean=true
```

### Workstation Playbook

`playbooks/install-workstation.yml` provides complete workstation provisioning:

```bash
linux-workstation
linux-workstation-check
linux-workstation-apps
linux-workstation-devtools
linux-security

ansible-playbook -K playbooks/install-workstation.yml
ansible-playbook -K playbooks/install-workstation.yml --check
ansible-playbook -K playbooks/install-workstation.yml --tags apps
ansible-playbook -K playbooks/install-workstation.yml -e workstation_security=false
ansible-playbook -K playbooks/install-workstation.yml -e workstation_install_copilot_cli=true
ansible-playbook -K playbooks/install-workstation.yml -e ubuntu_pro_token=TOKEN
```

### CIS Security Profiles

The installer supports Ubuntu Security Guide (USG) with CIS benchmarks. Choose the appropriate profile:

| Profile | Description | Use Case |
|---------|-------------|----------|
| `cis_level1_workstation` | Basic security hardening (default, recommended) | Personal workstations |
| `cis_level2_workstation` | Stricter security controls | High-security workstations |
| `cis_level1_server` | Basic server hardening | Personal servers |
| `cis_level2_server` | Maximum server security | Production servers |

```bash
# Use Level 2 workstation profile
ansible-playbook -K playbooks/install-workstation.yml -e cis_profile=cis_level2_workstation
```

See `linux/ansible/README.md` for the complete Linux Ansible command reference.

## Developer-tool updates

`linux-update` updates installed nvm, moves its existing default Node runtime to the latest LTS, migrates global tools, and makes LTS the default. Older runtimes and linked packages are retained. npm without nvm is supported. Missing tools are skipped; project dependencies are untouched. Snap Node.js remains opt-in and workstation provisioning is unchanged.

| Operation | Linux variable (default) | Windows skip switch |
|---|---|---|
| nvm and Node LTS | `update_nvm: true` | `-NoNvm` |
| npm and general global packages | `update_npm: true` | `-NoNpm` |
| npm-managed and standalone Codex | `update_codex_cli: true` | `-NoCodex` |

Linux discovers nvm at `{{ resolved_target_home }}/.nvm`; override `nvm_dir` for a custom location. The reviewed upstream release is pinned by `nvm_release` (currently `v0.40.8`). Git and script installations retain their method; modified or unrecognized installations fail without overwriting local changes. No shell profiles are loaded. Use `--check` to preview without upgrades, downloads, or runtime switches.

### Windows launch and migration

Launch `windows/update/Update-System.ps1` from **unelevated** Windows PowerShell 5.1 or PowerShell 7. It requests UAC for system updates in a child using the current PowerShell executable, waits, then updates developer tools in the original user session. UAC cancellation and child failures remain failures in the final exit code while independent user phases still run. The orchestrator and Codex fallback pass no execution-policy overrides; the signed nvm installer controls its own internal migration commands. An elevated full invocation is rejected; `-SystemOnly` explicitly runs system phases from an elevated session.

```powershell
.\windows\update\Update-System.ps1 -DryRun
.\windows\update\Update-System.ps1 -WhatIf
.\windows\update\Update-System.ps1 -NoNvm -NoCodex
```

Existing nvm-windows 2.x installations use `nvm upgrade` when its updater is installed. Legacy/manual installations use the official stable community installer with Authenticode validation and upstream 1.x migration. Running processes under affected program/runtime directories defer migration; close developer tools before retrying. Process inspection failures also stop migration. No process is deliberately terminated by this script. Upstream silent setup can terminate processes that start after the final preflight scan, so keep the disposable acceptance environment quiescent.

Before migration, configuration, runtime hashes, and each runtime's global packages are saved in a user/SYSTEM-only directory under `%LOCALAPPDATA%\SystemLifecycle\recovery`. Retained runtimes and packages are verified before installing LTS. Treat these recovery files as private: they may contain configuration credentials and local paths. Keep them until recovery is no longer needed, then delete them yourself.

### Failures and recovery

A failed runtime migration, malformed inventory, incompatible Node engine, or preservation check stops dependent npm updates and returns a failure. Independent standalone Codex updates can still run. npm and Codex have dedicated phases; linked packages are never replaced by registry packages. General global tools update to registry `latest` subject to Node engine checks. With nvm on Linux, npm uses `nvm install-latest-npm`; other installations enforce npm's declared Node engine before installation. npm cache verification/cleanup runs in the original Windows user session, with `-Clean` requesting aggressive cleanup when npm updates are enabled.

Releases without a declared Node engine are supported. Linux failures identify the npm operation and a fixed diagnostic when available; raw npm output and local paths remain private.

If migration fails, retain the recovery inventory and existing runtime directories. On Linux, restore the previous default with `nvm alias default <old-version>` and `nvm use <old-version>`. On Windows, inspect the private inventory locally and use `nvm use <old-version>` after verifying that version exists. For incomplete installer migration, follow the [upstream installer guidance](https://docs.nvm-windows.com/install/installers/) rather than deleting old directories or reinstalling global packages blindly.

Codex installations are updated explicitly through npm when present there. Recognized official standalone installations use the documented [`codex update`](https://learn.chatgpt.com/docs/developer-commands?surface=cli) self-updater when available, preserving their directory. Ambiguous package-manager/custom installations are reported and skipped; older recognized standalone builds use the official unattended installer in the same visible command directory. `-DryRun`, `-WhatIf`, and Ansible check mode perform no tool updates, installer downloads, switches, or elevation.

Real nvm-windows migration, installer behavior, UAC, and Windows PowerShell 5.1 runtime acceptance require a disposable Windows machine. Linux-host fixture tests do not establish those guarantees; see [architecture and acceptance guidance](docs/architecture.md).

## Bootstrap Helper

The only supported Linux shell entrypoint is `linux/ansible/scripts/ensure-ansible.sh`. It installs the runtime packages needed to run the Ansible playbooks and is called automatically by the managed aliases.

`linux/lib/` is intentionally minimal and exists only for that bootstrap script: `colors.sh`, `logging.sh`, and `utils.sh`.

## Requirements

- Ubuntu 24.04 LTS or 26.04 LTS (or compatible Debian-based distribution)
- Ansible Core 2.15+ (`ansible-playbook`)
- Root/sudo privileges for system changes
- Optional: npm (for global package updates)

## Development

### Branching Workflow

This repository uses feature branches with `main` as the integration branch:

- **`main`**: Stable integration branch
- **Feature branches**: All active development happens here

```bash
# Start from main
git checkout main
git pull origin main
git checkout -b feature/your-feature-name

# Make changes, commit, push
git add .
git commit -m "Your message"
git push -u origin feature/your-feature-name

# Open a PR to main
```

### Pre-commit Hooks

This repository uses pre-commit hooks for code quality:

```bash
# Install pre-commit
pip install pre-commit

# Install hooks
pre-commit install

# Run manually
pre-commit run --all-files
```

### Linting

The retained bootstrap shell script and helper libraries are linted with ShellCheck:

```bash
find linux -name '*.sh' -exec shellcheck -x {} +
```

### Testing

This project uses [Bats](https://github.com/bats-core/bats-core) (Bash Automated Testing System) for testing:

```bash
# Install bats
sudo apt-get install bats

# Run all tests
bats tests/

# Run specific test file
bats tests/lib/utils.bats
```

Tests are automatically run in CI on push to `main` and PRs to `main`.

## License

MIT
