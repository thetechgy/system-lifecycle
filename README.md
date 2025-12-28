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

### First-Time Setup

Configure shell aliases for easy access to scripts:

```bash
./linux/ubuntu/configure/configure-bashrc.sh
source ~/.bashrc
```

### Ubuntu System Update

```bash
# Using the alias (after setup)
update-system              # Full update
update-system --dry-run    # Preview changes
update-system --no-npm     # Skip npm updates

# Or run directly
sudo ./linux/ubuntu/update/update-system.sh
```

### Update Script Options

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

Logs are written to `/var/log/system-lifecycle/update-system-YYYYMMDD-HHMMSS.log`

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

## License

MIT
