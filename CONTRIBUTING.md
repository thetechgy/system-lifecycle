# Contributing to System Lifecycle

Thank you for your interest in contributing! This document provides guidelines for contributing to this project.

## Prerequisites

- Ubuntu 24.04 LTS (or compatible Debian-based distribution)
- Git
- ShellCheck (`sudo apt-get install shellcheck`)
- Bats (`sudo apt-get install bats`)
- Pre-commit (`pip install pre-commit`)

## Development Setup

1. Fork and clone the repository:
   ```bash
   git clone https://github.com/YOUR_USERNAME/system-lifecycle.git
   cd system-lifecycle
   ```

2. Install pre-commit hooks:
   ```bash
   pre-commit install
   ```

3. Create a feature branch from `develop`:
   ```bash
   git checkout develop
   git pull origin develop
   git checkout -b feature/your-feature-name
   ```

## Coding Standards

See [AGENTS.md](AGENTS.md) for detailed bash scripting standards. Key requirements:

- Use strict mode (`set -euo pipefail`)
- Source shared libraries from `linux/lib/`
- Support `--help` and `--dry-run` flags
- Pass ShellCheck with no warnings
- Include tests for new functionality

## Commit Message Conventions

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>: <description>

[optional body]
```

**Types:**
- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation changes
- `style:` Formatting (no code change)
- `refactor:` Code restructuring
- `test:` Adding/updating tests
- `chore:` Maintenance tasks
- `ci:` CI/CD changes

**Examples:**
```
feat: Add snap package update support
fix: Handle missing npm gracefully
docs: Update README with new flags
ci: Add Bats testing workflow
```

## Branch Naming

- `feature/` - New features
- `fix/` - Bug fixes
- `docs/` - Documentation updates
- `refactor/` - Code refactoring

## Pull Request Process

1. Ensure all tests pass:
   ```bash
   shellcheck linux/**/*.sh
   bats tests/
   ```

2. Update documentation if needed (README.md, AGENTS.md)

3. Create a PR from your branch to `develop`

4. Fill out the PR template completely

5. Wait for CI checks to pass

6. Address any review feedback

7. PRs are merged using **regular merge commits** (not squash or rebase)

## Testing

Run tests before submitting:

```bash
# Lint all scripts
shellcheck linux/**/*.sh

# Run all tests
bats tests/

# Run specific test file
bats tests/lib/utils.bats
```

## Questions?

Open an issue for questions or discussions about proposed changes.
