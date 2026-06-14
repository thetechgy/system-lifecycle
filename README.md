# System Lifecycle Management

[![ShellCheck](https://github.com/thetechgy/system-lifecycle/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/thetechgy/system-lifecycle/actions/workflows/shellcheck.yml)
[![Bats Tests](https://github.com/thetechgy/system-lifecycle/actions/workflows/test.yml/badge.svg)](https://github.com/thetechgy/system-lifecycle/actions/workflows/test.yml)

Personal automation for building, configuring, and maintaining Linux and Windows systems across their lifecycle. Linux automation is moving to native Ansible playbooks; Windows automation remains PowerShell-based.

> **Note**: These scripts are created for my own use and reflect my personal preferences. You're welcome to use them or fork and adapt them to your needs, but **please review the code thoroughly before running** to understand what it will do to your system. I accept no liability for any damage or issues that may result from using these scripts.

## Repository Structure

```
system-lifecycle/
├── linux/                  # Linux automation
│   ├── ansible/            # Native Ansible playbooks and roles
│   ├── lib/                # Legacy shared bash utilities
│   ├── ubuntu/             # Legacy Ubuntu scripts and config assets
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

## Linux Ansible Model

The Linux playbooks use Ansible tags and extra variables instead of Bash flags.

### Update Playbook

`playbooks/update-system.yml` performs APT update/upgrade/dist-upgrade, Snap refresh, Flatpak system and user updates, target-user npm global updates, optional Snap-based Node.js management, optional firmware updates, and APT cleanup.

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

## Shared Libraries

The `linux/lib/` directory contains reusable Bash utilities retained for legacy scripts and reference during the Ansible migration:

| Library | Purpose |
|---------|---------|
| `colors.sh` | Terminal color definitions |
| `logging.sh` | Structured logging to file and console |
| `utils.sh` | Common utilities and exit codes |
| `apt.sh` | APT package management helpers |
| `retry.sh` | Retry logic with exponential backoff |
| `rollback.sh` | Backup and restore functionality |
| `repositories.sh` | APT repository management |
| `gnome-extensions.sh` | GNOME extension installation |
| `config.sh` | Configuration file parsing |
| `progress.sh` | Progress bar display |

### Rollback Capability

The rollback library provides disaster recovery functionality:

```bash
# In your scripts, source the library
source "${LIB_DIR}/rollback.sh"

# Create a restore point before making changes
rollback_create_restore_point "pre-upgrade"

# Backup individual files
rollback_backup_file "/etc/ssh/sshd_config"

# List available restore points
rollback_list_restore_points

# Restore from a point (use with caution)
rollback_restore "pre-upgrade"
```

Restore points are stored in `/var/backups/system-lifecycle/`.

### Retry with Exponential Backoff

The retry library handles transient failures:

```bash
source "${LIB_DIR}/retry.sh"

# Retry a command up to 3 times with exponential backoff
retry_with_backoff 3 apt-get update

# Simple retry with fixed delay (5 attempts, 2 second delay)
retry_command 5 2 curl -fsSL https://example.com

# Wait for a service to become available
wait_for_service "snapd" 60 5  # service name, max wait, interval
```

## Requirements

- Ubuntu 24.04 LTS (or compatible Debian-based distribution)
- Ansible Core 2.15+ (`ansible-playbook`)
- Root/sudo privileges for system changes
- Optional: npm (for global package updates)

## Development

### Branching Workflow

This repository uses a `develop` → `main` workflow:

- **`develop`**: All active development happens here
- **`main`**: Stable releases only, updated via PR from `develop`

```bash
# Ensure you're on develop
git checkout develop

# Make changes, commit, push
git add .
git commit -m "Your message"
git push origin develop

# When ready to release, create PR: develop → main
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

Shell scripts are linted with ShellCheck:

```bash
shellcheck linux/**/*.sh
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

Tests are automatically run in CI on push to `develop` and PRs to `main`.

## License

MIT
