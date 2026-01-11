# Ansible Playbooks for System Lifecycle

This directory contains Ansible playbooks that replicate the functionality of the shell scripts in `linux/ubuntu/`.

## Prerequisites

- Ansible 2.9+ installed (`pip install ansible` or `apt install ansible`)
- Python 3.8+

## Quick Start

```bash
cd linux/ansible

# Full system update
ansible-playbook playbooks/update-system.yml

# Dry-run (check mode)
ansible-playbook playbooks/update-system.yml --check

# Configure bashrc aliases
ansible-playbook playbooks/configure-bashrc.yml
```

## Playbooks

### update-system.yml

Comprehensive system update playbook equivalent to `update-system.sh`.

**Usage:**
```bash
# Full update (apt, snap, flatpak, npm)
ansible-playbook playbooks/update-system.yml

# Skip specific package managers
ansible-playbook playbooks/update-system.yml -e "skip_snap=true"
ansible-playbook playbooks/update-system.yml -e "skip_snap=true skip_npm=true skip_flatpak=true"

# Enable firmware updates (opt-in, auto-skipped on WSL)
ansible-playbook playbooks/update-system.yml -e "run_firmware=true"

# Full cache clean instead of autoclean
ansible-playbook playbooks/update-system.yml -e "run_clean=true"

# Upgrade Node.js via NodeSource APT
ansible-playbook playbooks/update-system.yml -e "upgrade_nodejs=true"
ansible-playbook playbooks/update-system.yml -e "upgrade_nodejs=true nodejs_version=20"

# Run only specific updates using tags
ansible-playbook playbooks/update-system.yml --tags apt
ansible-playbook playbooks/update-system.yml --tags "apt,npm"
```

**Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `skip_snap` | `false` | Skip snap package updates |
| `skip_flatpak` | `false` | Skip flatpak package updates |
| `skip_npm` | `false` | Skip npm global package updates |
| `run_firmware` | `false` | Enable firmware updates (opt-in) |
| `run_clean` | `false` | Use `apt-get clean` instead of `autoclean` |
| `upgrade_nodejs` | `false` | Upgrade Node.js via NodeSource APT |
| `nodejs_version` | `"20"` | Node.js major version for NodeSource APT |

**Tags:**
- `apt` - APT package operations only
- `snap` - Snap package refresh only
- `flatpak` - Flatpak updates only
- `npm` - NPM global package updates only
- `nodejs` - Node.js upgrade only
- `firmware` - Firmware updates only
- `update` - All update operations

### configure-bashrc.yml

Configure shell aliases in `~/.bashrc`, equivalent to `configure-bashrc.sh`.
The managed `update-system` alias runs the local Ansible update playbook.

**Usage:**
```bash
# Add/update aliases
ansible-playbook playbooks/configure-bashrc.yml

# Remove aliases
ansible-playbook playbooks/configure-bashrc.yml -e "bashrc_state=absent"

# Configure for a different user
ansible-playbook playbooks/configure-bashrc.yml -e "bashrc_home=/home/otheruser"
```

**Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `bashrc_state` | `present` | `present` to add, `absent` to remove |
| `bashrc_home` | `~` | Home directory containing `.bashrc` |

## Directory Structure

```
ansible/
├── ansible.cfg              # Ansible configuration
├── inventory/
│   └── localhost.yml        # Localhost inventory
├── group_vars/
│   └── all.yml              # Default variables
├── playbooks/
│   ├── update-system.yml    # System update playbook
│   └── configure-bashrc.yml # Bashrc configuration playbook
└── roles/
    ├── apt_updates/         # APT package management
    ├── snap_updates/        # Snap package refresh
    ├── flatpak_updates/     # Flatpak updates
    ├── npm_updates/         # NPM global package updates
    ├── nodejs_upgrade/      # Node.js upgrade via NodeSource APT
    ├── firmware_updates/    # Firmware updates via fwupdmgr
    └── bashrc_config/       # Bashrc alias configuration
```

## Comparison with Shell Scripts

| Feature | Shell Script | Ansible |
|---------|-------------|---------|
| APT updates | Native | `ansible.builtin.apt` module |
| Snap refresh | Native | Shell command (no native "refresh all") |
| Flatpak update | Native | Shell command (no native "update all") |
| NPM update -g | Native | Shell command (no native "update all") |
| Firmware updates | Native | Shell command |
| WSL detection | `/proc/version` | `ansible_kernel` fact |
| Dry-run mode | `--dry-run` flag | `--check` mode |
| Selective skip | `--no-snap` flags | `-e "skip_snap=true"` |
| Custom exit codes | Yes (0-6) | No (Ansible uses 0/1/2/4) |
| Timestamped logs | Yes | Requires callback plugin |

## Notes

- **WSL Detection**: Firmware updates are automatically skipped when running on WSL
- **User Scope**: Flatpak and npm updates run as the invoking user to target per-user installs
- **Node.js Source**: `upgrade_nodejs=true` adds the NodeSource APT repo and installs `nodejs`
- **Check Mode**: Use `--check` for dry-run. Note that Ansible's check mode is all-or-nothing and won't show detailed `apt upgrade --dry-run` output like the shell script
- **Idempotency**: All playbooks are idempotent and safe to run multiple times
- **Privilege Escalation**: The `update-system.yml` playbook uses `become: true` (sudo)
