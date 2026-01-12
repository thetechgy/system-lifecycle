# Ansible Playbooks for System Lifecycle

This directory contains Ansible playbooks that replicate the functionality of the shell scripts in `linux/ubuntu/`.

## Prerequisites

- Ansible 2.15+ installed (`pip install ansible` or `apt install ansible`)
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
ansible-playbook playbooks/update-system.yml -e "update_snap=false"
ansible-playbook playbooks/update-system.yml -e "update_snap=false update_npm=false update_flatpak=false"

# Enable firmware updates (opt-in, auto-skipped on WSL)
ansible-playbook playbooks/update-system.yml -e "update_firmware=true"

# Full cache clean instead of autoclean
ansible-playbook playbooks/update-system.yml -e "apt_full_clean=true"

# Upgrade Node.js via NodeSource APT
ansible-playbook playbooks/update-system.yml -e "update_nodejs=true"
ansible-playbook playbooks/update-system.yml -e "update_nodejs=true nodejs_version=22"

# Run only specific updates using tags
ansible-playbook playbooks/update-system.yml --tags apt
ansible-playbook playbooks/update-system.yml --tags "apt,npm"
```

**Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `update_apt` | `true` | Enable/disable APT package updates |
| `update_snap` | `true` | Enable/disable snap package updates |
| `update_flatpak` | `true` | Enable/disable flatpak package updates |
| `update_npm` | `true` | Enable/disable npm global package updates |
| `update_firmware` | `false` | Enable firmware updates (opt-in) |
| `update_nodejs` | `false` | Enable Node.js upgrade via NodeSource APT |
| `apt_full_clean` | `false` | Use `apt-get clean` instead of `autoclean` |
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
├── playbooks/
│   ├── update-system.yml    # System update playbook
│   └── configure-bashrc.yml # Bashrc configuration playbook
└── roles/
    ├── system_updates/      # System update orchestration role
    │   ├── defaults/main.yml    # Default variables
    │   ├── handlers/main.yml    # Reboot notification handler
    │   ├── vars/main.yml        # Internal variables
    │   └── tasks/
    │       ├── main.yml         # Task orchestrator
    │       ├── apt.yml          # APT package updates
    │       ├── snap.yml         # Snap package refresh
    │       ├── flatpak.yml      # Flatpak updates
    │       ├── npm.yml          # NPM global package updates
    │       ├── nodejs.yml       # Node.js upgrade via NodeSource
    │       ├── firmware.yml     # Firmware updates via fwupdmgr
    │       └── cleanup.yml      # APT cleanup tasks
    └── bashrc_config/       # Bashrc alias configuration
        ├── defaults/main.yml
        └── tasks/main.yml
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
| Selective skip | `--no-snap` flags | `-e "update_snap=false"` |
| Custom exit codes | Yes (0-6) | No (Ansible uses 0/1/2/4) |
| Timestamped logs | Yes | Requires callback plugin |

## Notes

- **WSL Detection**: Firmware updates are automatically skipped when running on WSL
- **User Scope**: Flatpak updates run in both system (sudo) and user scope; npm updates run with sudo to target system-wide installs
- **Node.js Source**: `update_nodejs=true` adds the NodeSource APT repo and installs `nodejs`
- **Check Mode**: Use `--check` for dry-run. Command-based updates (snap/flatpak/npm/fwupdmgr/apt-get clean) are skipped while listing pending updates where available; apt upgrade still uses Ansible's check mode and won't show detailed `apt upgrade --dry-run` output like the shell script
- **Idempotency**: All playbooks are idempotent and safe to run multiple times
- **Privilege Escalation**: The `update-system.yml` playbook uses `become: true` (sudo)
