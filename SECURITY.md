# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| main    | :white_check_mark: |
| develop | :warning: Development only |

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly:

1. **Do not** open a public GitHub issue for security vulnerabilities

2. **Use GitHub's private vulnerability reporting:**
   - Go to the repository's Security tab
   - Click "Report a vulnerability"
   - Provide details about the vulnerability

3. **Include in your report:**
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

## Response Timeline

- **Acknowledgment:** Within 48 hours
- **Initial assessment:** Within 7 days
- **Resolution target:** Within 30 days (depending on severity)

## Security Measures

This project implements the following security practices:

- **Pre-commit hooks:** Gitleaks for secret scanning
- **Code review:** All changes require PR review
- **CI/CD:** Automated ShellCheck linting
- **Dependency updates:** Dependabot for automated security updates

## Scope

This policy applies to:
- Shell scripts in this repository
- GitHub Actions workflows
- Configuration files

Out of scope:
- Third-party dependencies (report to upstream maintainers)
- Issues in the underlying operating system
