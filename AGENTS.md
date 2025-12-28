# AGENTS.md

Context for AI coding assistants (Claude Code, Codex).

## Project Overview

Personal scripts for building, configuring, and maintaining Linux and Windows systems. Scripts are organized by platform, distribution, and task type.

## Directory Structure

```
linux/
├── lib/                    # Shared bash libraries (source these)
│   ├── colors.sh           # Terminal colors (RED, GREEN, etc.)
│   ├── logging.sh          # log_info, log_error, section, init_logging
│   ├── utils.sh            # command_exists, check_root, exit codes
│   └── version-check.sh    # check_for_updates (warns if behind origin/main)
├── ubuntu/                 # Ubuntu-specific
│   ├── update/             # System update scripts
│   ├── configure/          # Configuration scripts
│   └── install/            # Installation scripts
├── debian/                 # Debian-specific
└── common/                 # Cross-distro scripts

windows/
├── lib/                    # Shared PowerShell modules
├── update/
├── configure/
└── install/
```

## Bash Script Standards

All bash scripts must:

1. **Use strict mode:**
   ```bash
   set -o errexit
   set -o nounset
   set -o pipefail
   ```

2. **Source shared libraries:**
   ```bash
   SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
   readonly SCRIPT_DIR
   readonly LIB_DIR="${SCRIPT_DIR}/../../lib"

   source "${LIB_DIR}/colors.sh"
   source "${LIB_DIR}/logging.sh"
   source "${LIB_DIR}/utils.sh"
   ```

3. **Pass shellcheck locally before committing:**
   ```bash
   shellcheck linux/**/*.sh
   ```

4. **Support standard flags:** `--help`, `--dry-run` where applicable

5. **Use named exit codes** from `utils.sh` (EXIT_SUCCESS, EXIT_ERROR, etc.)

## Adding a New Script

1. Place in correct directory: `linux/{distro}/{task-type}/script-name.sh`
2. Source the shared libraries
3. Follow the header template (see existing scripts)
4. Make executable: `chmod +x`
5. If adding an alias, update `configure-bashrc.sh`
6. Update `README.md` if adding/changing/removing functionality
7. Add Bats tests in `tests/` directory

## Available Library Functions

**From logging.sh:**
- `init_logging "script-name"` - Initialize log file
- `log_info`, `log_success`, `log_warning`, `log_error`
- `section "Title"` - Display section header

**From utils.sh:**
- `command_exists "cmd"` - Check if command available
- `check_root` - Exit if not running as root
- `show_system_info` - Log hostname, OS, kernel
- `reboot_required` - Check if reboot needed

**From colors.sh:**
- `RED`, `GREEN`, `YELLOW`, `BLUE`, `NC` (no color)

**From version-check.sh:**
- `check_for_updates` - Warns if local repo is behind origin/main (call at start of main())

## Git Workflow

**Always work on `develop` branch. Never commit directly to `main`.**

Before making changes:
```bash
git checkout develop
git pull origin develop
```

After changes:
```bash
shellcheck linux/**/*.sh   # Must pass before committing
git add .
git commit -m "Description"
git push origin develop
```

Releases go to `main` via PR only. Use regular merge commits (not squash or rebase).

After PR is merged to `main`, sync develop:
```bash
git fetch origin && git merge origin/main && git push origin develop
```

## Testing

Tests use [Bats](https://github.com/bats-core/bats-core) (Bash Automated Testing System).

**Test file structure:**
- `tests/test_helper.bash` - Common setup and helpers
- `tests/lib/*.bats` - Tests for shared libraries
- `tests/ubuntu/*.bats` - Tests for Ubuntu scripts

**Running tests:**
```bash
bats tests/           # Run all tests
bats tests/lib/       # Run library tests only
```

**Test guidelines:**
- Test `--help` and `--version` flags
- Test invalid argument handling
- Test exit codes match `utils.sh` constants
- Use `load '../test_helper'` in each test file

## Avoid

- Committing to `main` branch directly
- Hardcoded paths (use variables)
- Missing error handling
- Scripts without `--help`
- Modifying files without backup
- Interactive prompts in automated scripts (use `DEBIAN_FRONTEND=noninteractive`)
- Changing functionality without updating README.md
- Adding scripts without corresponding tests
