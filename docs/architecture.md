# System Lifecycle Architecture

This document describes the architecture and design decisions of the system-lifecycle project.

## Overview

Linux automation is implemented with local Ansible playbooks and roles. Bash is retained only for the `ensure-ansible.sh` bootstrap helper that installs the packages needed to run those playbooks.

## Directory Structure

```
system-lifecycle/
├── linux/
│   ├── ansible/
│   │   ├── playbooks/              # update-system, install-workstation, configure-shell
│   │   ├── roles/                  # reusable Linux automation roles
│   │   ├── inventory/              # local inventory
│   │   └── scripts/                # bootstrap helpers
│   ├── lib/                        # colors/logging/utils for ensure-ansible.sh
│   ├── ubuntu/install/configs/     # dconf and fastfetch assets consumed by Ansible
│   ├── debian/                     # placeholder
│   └── common/                     # placeholder
├── windows/                        # Windows PowerShell scripts
├── tests/                          # Bats test suite
└── docs/                           # Documentation
```

## Linux Ansible Architecture

The Linux Ansible model uses local playbooks in `linux/ansible/playbooks` and roles in `linux/ansible/roles`.

| Playbook | Purpose |
|----------|---------|
| `update-system.yml` | APT, Snap, Flatpak, npm, optional Node.js, optional firmware, cleanup |
| `install-workstation.yml` | Ubuntu Pro/USG, applications, developer tools, GNOME extensions, fastfetch |
| `configure-shell.yml` | Managed convenience aliases for common playbook scenarios |

The `linux_context` role resolves `repo_root`, `target_user`, `target_home`, WSL status, and the environment used for user-scoped commands. Roles that touch npm, GNOME extensions, dconf, CLI tools, or user config must use those facts instead of running as root by default.

## Bootstrap Script

`linux/ansible/scripts/ensure-ansible.sh` is the only supported Linux shell entrypoint. It ensures `ansible-core`, `python3-apt`, and `python3-yaml` are installed before playbooks run. The managed shell aliases call it before invoking `ansible-playbook`.

The retained Bash libraries are intentionally small:

| Library | Purpose |
|---------|---------|
| `colors.sh` | Terminal color definitions |
| `logging.sh` | Structured logging helpers |
| `utils.sh` | Common command and exit-code helpers |

## Design Patterns

1. **Ansible-first Linux automation**: New Linux behavior belongs in roles and playbooks, not standalone shell scripts.
2. **Check mode for previews**: Use `ansible-playbook --check` instead of custom `--dry-run` behavior.
3. **Target-user execution**: User-scoped package, GNOME, dconf, and config tasks use `linux_context` facts.
4. **Idempotent tasks**: Prefer Ansible modules and explicit `changed_when`/`failed_when` where command tasks are unavoidable.
5. **Bootstrap isolation**: Shell helpers exist only to support `ensure-ansible.sh`.

## Security Considerations

- System-level package and configuration tasks run with `become: true`.
- User-scoped commands run as the resolved target user with explicit `HOME`, `PATH`, `XDG_RUNTIME_DIR`, and DBus environment.
- Ubuntu Pro tokens should be treated as secrets and passed using safe Ansible mechanisms where possible.
- Firmware and USG/CIS hardening are skipped on WSL where they do not apply.

## Extension Points

### Adding Linux Automation

1. Add or update a role under `linux/ansible/roles`.
2. Wire the role or task into the appropriate playbook.
3. Add tags and defaults for user-facing toggles.
4. Update `README.md` and `linux/ansible/README.md` when commands, variables, or behavior change.
5. Add Bats coverage under `tests/ansible/`.

### Distribution Support

The current playbooks target Ubuntu 24.04 LTS and compatible Debian-based systems. Placeholder directories remain for future Debian or cross-distribution assets.

## Testing

Tests use [Bats](https://github.com/bats-core/bats-core).

```
tests/
├── ansible/                 # Ansible migration surface tests
├── lib/                     # Bootstrap helper library tests
└── test_helper.bash         # Common test helpers
```

Run checks before submitting:

```bash
find linux -name '*.sh' -exec shellcheck -x {} +

cd linux/ansible
ansible-playbook --syntax-check playbooks/update-system.yml playbooks/install-workstation.yml playbooks/configure-shell.yml
cd ../..

bats tests/
```

## CI/CD

GitHub Actions runs ShellCheck, Ansible syntax checks, and Bats tests on pushes to `develop` and pull requests to `main`.
