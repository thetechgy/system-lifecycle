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
| `update-system.yml` | APT, Snap, Flatpak, nvm/Node LTS, npm/globals, Codex, optional Snap Node.js, optional firmware, cleanup |
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

GitHub Actions runs ShellCheck, Ansible syntax checks, and Bats tests on pushes to `main` and pull requests to `main`.

## Developer-tool update contract

Linux `system_updates/tasks/npm.yml` owns the Ansible entry point, user identity, controls, tags, and check-mode boundary. Its internal Python worker loads nvm explicitly, verifies upstream provenance, selects the existing default, installs an exact resolved LTS, migrates globals, then changes the default. `shared/npm-tools.cjs` supplies identical inventory validation, engine checks, link preservation, and package verification to Linux and Windows. It invokes npm's JS entry point with the selected Node executable and argument arrays, without shell parsing. npm's bundled semver evaluates package engine requirements; no extra package is installed for validation.

Windows `Update-System.ps1` owns the UAC boundary. Full updates start unelevated; the elevated child receives only allowlisted system switches and `-SystemOnly` through a literal, encoded command. It uses the current executable, waits, and propagates failures without execution-policy overrides. Developer tools run in the caller through `DeveloperTools.ps1`. No preview enters the elevation or developer mutation paths. System-only invocations do not update or clean npm caches. Full invocations verify the npm cache in the user phase; `-Clean` requests aggressive npm cache cleanup when npm updates are enabled.

Before Windows migration, the worker captures settings, installed runtime hashes, and per-runtime global inventories in a restricted recovery directory. The official 2.x updater or signed community installer performs the upgrade. Environment variables are refreshed from user/machine settings before rediscovery. Runtime and package preservation checks precede LTS selection. A failed check stops dependent work; successful independent phases cannot erase earlier failure status. Recovery snapshots are retained as private local artifacts and never included in repository files or normal logs.

There is no transaction spanning an upstream installer, nvm, and npm. Partial upgrades remain possible; old runtimes and Windows recovery inventories support manual recovery. Process scans are preflight checks, not a lock: upstream silent setup can close a process started after the last scan. Keep tools closed during migration. Custom or ambiguous Codex sources are skipped; recognized standalone layouts use the supported self-updater or official unattended installer.

### Disposable Windows acceptance (not established by Linux tests)

1. Use a disposable Windows 10/11 user with nvm-windows 1.x, multiple installed runtimes, a selected default, registry globals, a linked global package, and Codex. Repeat with supported 2.x and a custom legacy root.
2. Run previews under Windows PowerShell 5.1 and PowerShell 7; verify no UAC, downloads, runtime/default changes, or package changes.
3. Start a process beneath each affected root; verify migration defers without terminating it. Close it before proceeding.
4. Run unelevated, approve UAC, verify the child uses the same PowerShell edition, exits before developer work, and preserves supported arguments. Cancel UAC in another run and verify a final failure with independent tool results retained.
5. Verify the private recovery directory ACL, signed stable installer, migration of all old runtimes/configuration, registry and linked package preservation, latest LTS default, npm compatibility, and both Codex installation sources. Repeat with LTS already installed and on a second update.
6. Inject an installer failure or missing retained runtime/package; verify dependent npm updates stop, final status stays nonzero, and recovery information remains available. Restore the old runtime using the private inventory and verify tools before removing any old data.

Bats runs production Ansible tasks against isolated runtimes and a local npm registry fixture, plus an offline real-npm linked-package test with a temporary prefix/cache (verified with Node 24.15.0 and npm 12.2.0); Pester exercises orchestration and migration boundaries with mocks. These checks do not prove real UAC, Windows process enumeration, Authenticode, installer migration, or PowerShell 5.1 runtime behavior. No disposable Windows environment was available during this implementation.
