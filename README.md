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

## Bootstrap Helper

The only supported Linux shell entrypoint is `linux/ansible/scripts/ensure-ansible.sh`. It installs the runtime packages needed to run the Ansible playbooks and is called automatically by the managed aliases.

`linux/lib/` is intentionally minimal and exists only for that bootstrap script: `colors.sh`, `logging.sh`, and `utils.sh`.

## Requirements

- Ubuntu 24.04 LTS (or compatible Debian-based distribution)
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
