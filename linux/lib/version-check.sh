#!/usr/bin/env bash
#
# version-check.sh - Check if local scripts are up to date
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/version-check.sh"
#   check_for_updates
#
# Description:
#   Compares local HEAD against origin/main and warns if behind.
#   Gracefully skips if git unavailable, not a repo, or no network.
#

# Get the repository root from this library's location
_get_repo_root() {
  local lib_dir
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  echo "${lib_dir}/../.."
}

# Check for updates and warn if behind origin/main
# Returns: 0 always (never fails the calling script)
check_for_updates() {
  local repo_root
  local local_rev
  local remote_rev
  local behind_count

  repo_root="$(_get_repo_root)"

  # Skip if git is not installed
  if ! command -v git &>/dev/null; then
    return 0
  fi

  # Skip if not a git repository
  if ! git -C "${repo_root}" rev-parse --git-dir &>/dev/null; then
    return 0
  fi

  # Fetch latest from origin (quietly, with timeout)
  # Skip if fetch fails (no network, no credentials, etc.)
  # GIT_TERMINAL_PROMPT=0 prevents credential prompts
  if ! GIT_TERMINAL_PROMPT=0 timeout 5 git -C "${repo_root}" fetch origin main --quiet 2>/dev/null; then
    return 0
  fi

  # Get local and remote revisions
  local_rev=$(git -C "${repo_root}" rev-parse HEAD 2>/dev/null) || return 0
  remote_rev=$(git -C "${repo_root}" rev-parse origin/main 2>/dev/null) || return 0

  # If already up to date, nothing to do
  if [[ "${local_rev}" == "${remote_rev}" ]]; then
    return 0
  fi

  # Count how many commits behind
  behind_count=$(git -C "${repo_root}" rev-list --count HEAD..origin/main 2>/dev/null) || return 0

  # Only warn if actually behind (not ahead or diverged)
  if [[ "${behind_count}" -gt 0 ]]; then
    # Use colors if available, otherwise plain text
    if [[ -n "${YELLOW:-}" ]] && [[ -n "${NC:-}" ]]; then
      printf "%b⚠️  Your scripts are %d commit(s) behind origin/main.%b\n" "${YELLOW}" "${behind_count}" "${NC}" >&2
    else
      printf "⚠️  Your scripts are %d commit(s) behind origin/main.\n" "${behind_count}" >&2
    fi
    printf "    Run: git -C %s pull\n\n" "${repo_root}" >&2
  fi

  return 0
}
