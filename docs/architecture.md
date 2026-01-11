# System Lifecycle Architecture

This document describes the architecture and design decisions of the system-lifecycle project.

## Overview

System-lifecycle is a modular automation framework for building, configuring, and maintaining Linux (Ubuntu/Debian) systems. It follows a library-based architecture where common functionality is shared across scripts.

## Directory Structure

```
system-lifecycle/
├── linux/                          # Linux-specific scripts
│   ├── lib/                        # Shared bash libraries
│   │   ├── apt.sh                  # APT package management
│   │   ├── colors.sh               # Terminal color definitions
│   │   ├── dependencies.sh         # Dependency checking utilities
│   │   ├── gnome-extensions.sh     # GNOME extension management
│   │   ├── logging.sh              # Logging system
│   │   ├── progress.sh             # Progress indicators
│   │   ├── repositories.sh         # APT repository management
│   │   ├── utils.sh                # Common utilities
│   │   └── version-check.sh        # Git version checking
│   ├── ubuntu/                     # Ubuntu-specific scripts
│   │   ├── configure/              # Configuration scripts
│   │   │   └── configure-bashrc.sh
│   │   ├── install/                # Installation scripts
│   │   │   ├── install-workstation.sh
│   │   │   └── configs/            # Configuration files
│   │   └── update/                 # Update scripts
│   │       └── update-system.sh
│   ├── debian/                     # Debian-specific (placeholder)
│   └── common/                     # Cross-distribution (placeholder)
├── windows/                        # Windows PowerShell scripts
├── tests/                          # Bats test suite
├── docs/                           # Documentation
└── Configuration files
```

## Library Architecture

### Dependency Chain

Libraries must be sourced in a specific order due to dependencies:

```
colors.sh          (no dependencies)
     ↓
logging.sh         (depends on: colors.sh)
     ↓
utils.sh           (depends on: logging.sh)
     ↓
dependencies.sh    (depends on: logging.sh, utils.sh)
apt.sh             (depends on: logging.sh, utils.sh)
repositories.sh    (depends on: logging.sh, utils.sh)
gnome-extensions.sh (depends on: logging.sh, utils.sh)
progress.sh        (depends on: colors.sh)
version-check.sh   (no dependencies)
```

### Library Descriptions

| Library | Purpose |
|---------|---------|
| `colors.sh` | Terminal color definitions (RED, GREEN, etc.) with TTY detection |
| `logging.sh` | Structured logging to file and console with timestamps |
| `utils.sh` | Common utilities: `command_exists`, `check_root`, exit codes |
| `dependencies.sh` | Command requirement checking: `require_commands` |
| `apt.sh` | APT operations: update, upgrade, install, clean |
| `repositories.sh` | Repository management: GPG keys, DEB822 format |
| `gnome-extensions.sh` | GNOME extension installation from extensions.gnome.org |
| `progress.sh` | Progress bars and phase tracking |
| `version-check.sh` | Git repository version checking |

## Script Architecture

### Standard Script Structure

All main scripts follow this structure:

```bash
#!/usr/bin/env bash
#
# script-name.sh - Description
#
# Usage, Options, Exit Codes documentation

set -o errexit   # Exit on error
set -o nounset   # Exit on undefined variable
set -o pipefail  # Catch pipeline failures

# Configuration
SCRIPT_NAME="$(basename "${0}")"
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../../lib"

# Default flags
DRY_RUN=false
QUIET=false

# Library existence check
_check_lib() { ... }

# Source libraries
source "${LIB_DIR}/colors.sh"
source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/utils.sh"

# Help and version functions
show_usage() { ... }
show_version() { ... }

# Argument parsing
parse_args() { ... }

# Cleanup handler
cleanup() { ... }
trap cleanup EXIT

# Feature functions
feature_one() { ... }
feature_two() { ... }

# Main function
main() {
  parse_args "$@"
  check_root
  init_logging

  feature_one
  feature_two
}

main "$@"
```

### Key Design Patterns

1. **Library Sourcing**: All scripts verify library existence before sourcing
2. **Exit Codes**: Standardized exit codes defined in `utils.sh`
3. **Dry-Run Mode**: All scripts support `--dry-run` for previewing changes
4. **Idempotency**: Safe to run multiple times
5. **Logging**: Dual output to file and console

## Logging System

### Log Levels

- `log_info` - Informational messages (blue)
- `log_success` - Success messages (green)
- `log_warning` - Warning messages (yellow)
- `log_error` - Error messages (red)

### Log Files

Logs are stored in `/var/log/system-lifecycle/` with naming pattern:
```
<script-name>-YYYYMMDD-HHMMSS.log
```

### Quiet Mode

When `QUIET=true`:
- Console output is suppressed
- File logging continues normally

## Error Handling

### Exit Codes

| Code | Constant | Meaning |
|------|----------|---------|
| 0 | EXIT_SUCCESS | Success |
| 1 | EXIT_ERROR | General error |
| 2 | EXIT_INVALID_ARGS | Invalid arguments |
| 3 | EXIT_NOT_ROOT | Not running as root |
| 4 | EXIT_APT_UPDATE_FAILED | APT update failed |
| 5 | EXIT_APT_UPGRADE_FAILED | APT upgrade failed |
| 6 | EXIT_NPM_UPDATE_FAILED | NPM update failed |
| 7 | EXIT_USG_FAILED | USG/CIS hardening failed |
| 8 | EXIT_APP_INSTALL_FAILED | Application installation failed |
| 9 | EXIT_EXTENSION_FAILED | Extension installation failed |
| 10 | EXIT_PREREQ_FAILED | Prerequisites check failed |
| 11 | EXIT_DEVTOOLS_FAILED | Developer tools installation failed |
| 12 | EXIT_UBUNTU_PRO_FAILED | Ubuntu Pro enrollment failed |

### Cleanup Handlers

All scripts use `trap cleanup EXIT` to:
- Log completion status
- Display log file location
- Perform any necessary cleanup

## Security Considerations

### Running as Root

Most scripts require root privileges for:
- Package installation (apt-get)
- System configuration changes
- Log file creation in /var/log

### Secure Temporary Files

- Use `mktemp` instead of hardcoded `/tmp/` paths
- Clean up temp files on exit
- Avoid race conditions

### Token Handling

- Ubuntu Pro tokens read with `-s` flag (silent)
- Tokens not logged to files
- Tokens passed via command line or environment

### Command Execution

- Commands built as arrays to prevent word splitting
- User input properly quoted
- Avoid `eval` and command injection vectors

## Extension Points

### Adding New Scripts

1. Create script in appropriate directory (ubuntu/install/, etc.)
2. Source required libraries
3. Follow standard script structure
4. Add tests in tests/ directory
5. Update documentation

### Adding New Libraries

1. Create library in linux/lib/
2. Document dependencies in header
3. Follow existing function patterns
4. Add library to _check_lib calls in scripts that need it

### Distribution Support

The architecture supports multiple distributions:
- `linux/ubuntu/` - Ubuntu-specific
- `linux/debian/` - Debian-specific (planned)
- `linux/common/` - Distribution-agnostic (planned)

## Testing

### Test Framework

Uses [Bats](https://github.com/bats-core/bats-core) (Bash Automated Testing System).

### Test Structure

```
tests/
├── lib/                    # Library function tests
│   ├── colors.bats
│   ├── utils.bats
│   └── version-check.bats
├── ubuntu/                 # Script tests
│   └── update-system.bats
└── test_helper.bash        # Common test utilities
```

### Running Tests

```bash
# Run all tests
bats tests/

# Run specific test file
bats tests/lib/utils.bats
```

## CI/CD

### GitHub Actions

- ShellCheck linting on all shell scripts
- Bats tests on pull requests
- Pre-commit hooks for local development

### Pre-commit Hooks

Configured in `.pre-commit-config.yaml`:
- ShellCheck
- Trailing whitespace
- End of file fixer
- Gitleaks (secret detection)

## Future Considerations

### Planned Features

1. **Rollback Mechanism**: Undo capability for changes
2. **Retry Logic**: Automatic retry for transient failures
3. **Config File Support**: External configuration files
4. **Uninstall Script**: Reverse workstation installation

### Architectural Decisions

| Decision | Rationale |
|----------|-----------|
| Bash over Python | Target systems always have bash; no dependency installation |
| Library-based | Reduces duplication, ensures consistency |
| DEB822 format | Modern APT repository format, better tooling support |
| GNOME API | Direct extension installation without browser |
| Log files | Audit trail and debugging support |
