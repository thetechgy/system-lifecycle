# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- CI status badges in README
- CHANGELOG.md for tracking changes
- Markdown linting via pre-commit

### Changed

- Document develop sync step after PR merge to main

## [0.4.0] - 2024-12-27

### Added

- Regular merge commit policy documentation in AGENTS.md and CONTRIBUTING.md

### Changed

- Switch from squash merges to regular merge commits

## [0.3.0] - 2024-12-27

### Added

- CONTRIBUTING.md with development guidelines
- SECURITY.md with vulnerability reporting process
- LICENSE file (MIT)
- GitHub issue templates (bug report, feature request)
- GitHub pull request template
- Dependabot configuration for automated dependency updates
- `version-check.sh` library to warn when scripts are behind origin/main
- Bats testing framework with tests for library functions
- CI workflow for running Bats tests

### Changed

- Update actions/checkout from v4 to v6 in CI workflows
- Remove path filters from CI workflows (run on all pushes)
- Expand AGENTS.md with testing section and additional guidelines

## [0.2.0] - 2024-12-26

### Added

- `--no-snap` flag to skip snap package updates
- `--no-flatpak` flag to skip flatpak package updates
- `--firmware` flag to enable firmware updates (opt-in)
- `--clean` flag for aggressive package cache cleanup
- Snap package update support in update-system.sh
- Flatpak package update support in update-system.sh
- Firmware update support via fwupd (auto-installs if needed)
- WSL detection to skip firmware updates in virtualized environments
- Personal use disclaimer in README

### Changed

- Reorder update operations: package managers before cleanup
- Improve help text and examples in update-system.sh

## [0.1.0] - 2024-12-25

### Added

- Initial repository structure (linux/, windows/, docs/, tests/)
- Ubuntu system update script (`update-system.sh`)
- Bashrc configuration script (`configure-bashrc.sh`)
- Shared bash libraries:
  - `colors.sh` - Terminal color definitions
  - `logging.sh` - Logging utilities
  - `utils.sh` - Common utility functions
- AGENTS.md for AI coding assistant context
- ShellCheck CI workflow
- Pre-commit hooks (gitleaks, shellcheck, basic hygiene)
- Develop/main branching workflow
