# System Lifecycle Management

[![ShellCheck](https://github.com/thetechgy/system-lifecycle/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/thetechgy/system-lifecycle/actions/workflows/shellcheck.yml)
[![Bats Tests](https://github.com/thetechgy/system-lifecycle/actions/workflows/test.yml/badge.svg)](https://github.com/thetechgy/system-lifecycle/actions/workflows/test.yml)

Personal scripts for building, configuring, and maintaining Linux and Windows systems across their lifecycle.

> **Note**: These scripts are created for my own use and reflect my personal preferences. You're welcome to use them or fork and adapt them to your needs, but **please review the code thoroughly before running** to understand what it will do to your system. I accept no liability for any damage or issues that may result from using these scripts.

## Repository Structure

```
system-lifecycle/
├── linux/                  # Linux scripts
│   ├── lib/                # Shared bash utilities
│   │   ├── colors.sh       # Terminal color definitions
│   │   ├── logging.sh      # Logging utilities
│   │   └── utils.sh        # Common utility functions
│   ├── ubuntu/             # Ubuntu-specific scripts
│   │   ├── update/         # System update scripts
│   │   ├── configure/      # Configuration scripts
│   │   └── install/        # Installation scripts
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

Configure shell aliases for easy access to scripts:

```bash
./linux/ubuntu/configure/configure-bashrc.sh
source ~/.bashrc
```

### Ubuntu System Update

```bash
# Using the alias (after setup)
update-system              # Full update (apt, snap, flatpak, npm)
update-system --dry-run    # Preview changes
update-system --no-snap    # Skip snap updates
update-system --firmware   # Include firmware updates

# Or run directly
sudo ./linux/ubuntu/update/update-system.sh
```

### Update Script Options

| Flag | Description |
|------|-------------|
| `-d, --dry-run` | Preview changes without applying |
| `-q, --quiet` | Suppress non-essential output |
| `-n, --no-npm` | Skip npm global package updates |
| `--no-snap` | Skip snap package updates |
| `--no-flatpak` | Skip flatpak package updates |
| `--firmware` | Enable firmware updates (auto-installs fwupd if needed) |
| `--clean` | Use apt-get clean (remove ALL cached packages) |
| `-h, --help` | Display help message |
| `-v, --version` | Display script version |

## Update Script Details

The Ubuntu update script performs the following operations in order:

1. `apt-get update` - Refresh package lists
2. `apt-get upgrade` - Upgrade installed packages
3. `apt-get dist-upgrade` - Smart upgrade with dependency handling
4. `snap refresh` - Update snap packages (if installed)
5. `flatpak update` - Update flatpak packages (if installed)
6. `npm update -g` - Update global npm packages (if installed)
7. `fwupdmgr update` - Update firmware (only with --firmware flag, skipped on WSL)
8. `apt-get autoremove` - Remove unused packages
9. `apt-get autoclean` - Clean package cache (or `apt-get clean` with --clean)

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Invalid arguments |
| 3 | Not running as root |
| 4 | Apt update failed |
| 5 | Apt upgrade failed |
| 6 | Npm update failed |

### Logging

Logs are written to `/var/log/system-lifecycle/update-system-YYYYMMDD-HHMMSS.log`

### Notes

- **WSL**: Firmware updates are automatically skipped on WSL environments (detected via `/proc/version`)
- **fwupd**: The `--firmware` flag will auto-install fwupd if not already present

## Configure Script

The `configure-bashrc.sh` script manages shell aliases in `~/.bashrc`:

```bash
# Add/update aliases
./linux/ubuntu/configure/configure-bashrc.sh

# Preview changes
./linux/ubuntu/configure/configure-bashrc.sh --dry-run

# Remove aliases
./linux/ubuntu/configure/configure-bashrc.sh --remove
```

The script adds a managed section with markers, making it safe to run multiple times and easy to remove.

## Workstation Installation

The `install-workstation.sh` script provides complete workstation provisioning:

```bash
# Full installation (prompts for Ubuntu Pro token)
sudo ./linux/ubuntu/install/install-workstation.sh

# Preview changes
sudo ./linux/ubuntu/install/install-workstation.sh --dry-run

# Skip security hardening
sudo ./linux/ubuntu/install/install-workstation.sh --skip-security

# Security hardening only
sudo ./linux/ubuntu/install/install-workstation.sh --security-only
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
sudo ./linux/ubuntu/install/install-workstation.sh --cis-profile=cis_level2_workstation
```

## Shared Libraries

The `linux/lib/` directory contains reusable bash utilities:

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
- Root/sudo privileges
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
