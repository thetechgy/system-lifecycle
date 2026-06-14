# Linux Ansible Automation

Native Ansible playbooks for Linux system lifecycle work.

## Prerequisites

- Ubuntu 24.04 LTS or compatible Debian-based distribution
- Ansible Core 2.15+ (`ansible-playbook`)
- Sudo privileges for system-level changes

Run commands from this directory:

```bash
cd linux/ansible
```

Install missing Ansible runtime packages:

```bash
./scripts/ensure-ansible.sh
./scripts/ensure-ansible.sh --dry-run
```

The managed aliases also run `ensure-ansible.sh` before invoking `ansible-playbook`.

## Configure Shell Aliases

```bash
ansible-playbook playbooks/configure-shell.yml
ansible-playbook playbooks/configure-shell.yml -e shell_aliases_state=absent
```

Managed aliases:

- `linux-update`
- `linux-update-check`
- `linux-update-firmware`
- `linux-workstation`
- `linux-workstation-check`
- `linux-workstation-apps`
- `linux-workstation-devtools`
- `linux-security`

## Update System

```bash
ansible-playbook -K playbooks/update-system.yml
ansible-playbook -K playbooks/update-system.yml --check
ansible-playbook -K playbooks/update-system.yml --tags apt
ansible-playbook -K playbooks/update-system.yml -e update_firmware=true
ansible-playbook -K playbooks/update-system.yml -e update_nodejs=true
```

| Variable | Default | Purpose |
|----------|---------|---------|
| `update_apt` | `true` | Run apt update/upgrade/cleanup |
| `update_snap` | `true` | Refresh snaps when snap is installed |
| `update_flatpak` | `true` | Update system and user flatpaks |
| `update_npm` | `true` | Update target-user npm globals |
| `update_firmware` | `false` | Run fwupd firmware updates |
| `update_nodejs` | `false` | Install/refresh Snap Node.js |
| `apt_full_clean` | `false` | Use `apt-get clean` instead of autoclean |
| `nodejs_version` | `"20"` | Snap Node.js channel |

## Install Workstation

```bash
ansible-playbook -K playbooks/install-workstation.yml
ansible-playbook -K playbooks/install-workstation.yml --check
ansible-playbook -K playbooks/install-workstation.yml --tags apps
ansible-playbook -K playbooks/install-workstation.yml --tags devtools
ansible-playbook -K playbooks/install-workstation.yml --tags security
```

| Variable | Default | Purpose |
|----------|---------|---------|
| `workstation_security` | `true` | Ubuntu Pro and USG/CIS phase |
| `workstation_apps` | `true` | Edge, VS Code, Discord |
| `workstation_devtools` | `true` | Node.js, AI CLIs, PowerShell, gh, rg, fd, jq |
| `workstation_extensions` | `true` | GNOME extensions and dconf settings |
| `workstation_fastfetch` | `true` | Fastfetch install and config |
| `ubuntu_pro_token` | `""` | Optional token for noninteractive Pro attach |
| `cis_profile` | `cis_level1_workstation` | USG profile |
| `target_user` | auto | User for npm, CLI tools, GNOME, and user config |
| `target_home` | auto | Home directory for `target_user` |

## Tags

- `apt`, `snap`, `flatpak`, `npm`, `nodejs`, `firmware`
- `security`, `ubuntu_pro`, `usg`
- `apps`, `devtools`, `extensions`, `gnome`, `fastfetch`
- `shell`, `aliases`

## Notes

- Node.js is managed through Snap to match the workstation install model.
- User-scoped commands run as `target_user`, with user `HOME`, `PATH`, `XDG_RUNTIME_DIR`, and DBus environment set.
- Firmware and USG/CIS hardening are skipped on WSL where they do not apply.
