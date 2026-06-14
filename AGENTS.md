# AGENTS.md

Context for AI coding assistants (Claude Code, Codex).

## Project Overview

Personal automation for building, configuring, and maintaining Linux and Windows systems. Linux automation is Ansible-first; Windows automation remains PowerShell-based.

## Directory Structure

```
linux/
├── ansible/                # Linux playbooks, roles, inventory, bootstrap
│   ├── playbooks/          # update-system, install-workstation, configure-shell
│   ├── roles/              # reusable Linux automation roles
│   └── scripts/
│       └── ensure-ansible.sh
├── lib/                    # Minimal Bash helpers for ensure-ansible.sh
│   ├── colors.sh           # Terminal colors
│   ├── logging.sh          # log_info, log_error, section, init_logging
│   └── utils.sh            # command_exists, check_root, exit codes
├── ubuntu/                 # Config assets consumed by Ansible roles
│   └── install/configs/
├── debian/                 # Debian-specific placeholder
└── common/                 # Cross-distro placeholder

windows/
├── lib/                    # Shared PowerShell modules
├── update/
├── configure/
└── install/
```

## Linux Automation Standards

Linux functionality should be added to Ansible playbooks and roles under `linux/ansible`. Do not add new legacy Bash entrypoint scripts under `linux/ubuntu`, `linux/debian`, or `linux/common`.

The retained bootstrap script, `linux/ansible/scripts/ensure-ansible.sh`, must:

1. **Use strict mode:**
   ```bash
   set -o errexit
   set -o nounset
   set -o pipefail
   ```

2. **Source only the retained bootstrap libraries:**
   ```bash
   source "${LIB_DIR}/colors.sh"
   source "${LIB_DIR}/logging.sh"
   source "${LIB_DIR}/utils.sh"
   ```

3. **Pass shellcheck locally before committing:**
   ```bash
   find linux -name '*.sh' -exec shellcheck -x {} +
   ```

4. **Support standard flags:** `--help`, `--dry-run`

5. **Use named exit codes** from `utils.sh` (`EXIT_SUCCESS`, `EXIT_ERROR`, etc.)

## Adding Linux Functionality

1. Add or update an Ansible role under `linux/ansible/roles`
2. Wire it into the appropriate playbook under `linux/ansible/playbooks`
3. If adding an alias, update `linux/ansible/roles/shell_aliases/tasks/main.yml`
4. Update `README.md` and `linux/ansible/README.md` if behavior or commands change
5. Add or update Bats tests in `tests/ansible/`

## Git Workflow

**Always work on `develop` branch. Never commit directly to `main`.**

Before making changes:
```bash
git checkout develop
git pull origin develop
```

After changes:
```bash
find linux -name '*.sh' -exec shellcheck -x {} +
(cd linux/ansible && ansible-playbook --syntax-check playbooks/update-system.yml playbooks/install-workstation.yml playbooks/configure-shell.yml)
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

Tests use [Bats](https://github.com/bats-core/bats-core).

**Test file structure:**
- `tests/test_helper.bash` - Common setup and helpers
- `tests/lib/*.bats` - Tests for bootstrap helper libraries
- `tests/ansible/*.bats` - Tests for Ansible playbooks and roles

**Running tests:**
```bash
bats tests/           # Run all tests
bats tests/ansible/   # Run Ansible tests only
```

**Test guidelines:**
- Test `--help` flags for retained shell helpers
- Test invalid argument handling
- Test exit codes match `utils.sh` constants
- Use `load '../test_helper'` in each test file

## Avoid

- Committing to `main` branch directly
- Adding new Linux shell entrypoint scripts
- Hardcoded paths (use variables/facts)
- Missing error handling
- Interactive prompts in automated scripts
- Changing functionality without updating README.md
- Adding Linux behavior without corresponding Ansible tests
