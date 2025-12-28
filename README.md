# System Lifecycle Management

Personal scripts for building, configuring, and maintaining Linux and Windows systems across their lifecycle.

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

### Ubuntu System Update

```bash
# Full system update
sudo ./linux/ubuntu/update/update-system.sh

# Preview changes (dry-run)
sudo ./linux/ubuntu/update/update-system.sh --dry-run

# Skip npm updates
sudo ./linux/ubuntu/update/update-system.sh --no-npm

# Quiet mode
sudo ./linux/ubuntu/update/update-system.sh --quiet
```

### Options

| Flag | Description |
|------|-------------|
| `-d, --dry-run` | Preview changes without applying |
| `-q, --quiet` | Suppress non-essential output |
| `-n, --no-npm` | Skip npm global package updates |
| `-h, --help` | Display help message |
| `-v, --version` | Display script version |

## Update Script Details

The Ubuntu update script performs the following operations in order:

1. `apt-get update` - Refresh package lists
2. `apt-get upgrade` - Upgrade installed packages
3. `apt-get dist-upgrade` - Smart upgrade with dependency handling
4. `apt-get autoremove` - Remove unused packages
5. `apt-get autoclean` - Clean package cache
6. `npm update -g` - Update global npm packages (if npm is installed)

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

Logs are written to `~/logs/system-lifecycle/update-system-YYYYMMDD-HHMMSS.log`

## Requirements

- Ubuntu 24.04 LTS (or compatible Debian-based distribution)
- Root/sudo privileges
- Optional: npm (for global package updates)

## Development

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

## License

MIT
