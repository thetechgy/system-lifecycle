#!/usr/bin/env bash
#
# progress.sh - Progress tracking and display utilities
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/progress.sh"
#   progress_start 5 "Installing packages"
#   progress_update 1 "Installing package 1"
#   progress_complete
#
# Dependencies:
#   - colors.sh (for terminal colors)

# Global state for progress tracking
_PROGRESS_TOTAL=0
_PROGRESS_CURRENT=0
_PROGRESS_TITLE=""
_PROGRESS_START_TIME=0

# Start progress tracking
# Arguments:
#   $1 - Total number of items/steps
#   $2 - (optional) Title/description
progress_start() {
  _PROGRESS_TOTAL="${1}"
  _PROGRESS_CURRENT=0
  _PROGRESS_TITLE="${2:-Progress}"
  _PROGRESS_START_TIME=$(date +%s)

  printf '%b[%s]%b Starting: %s (0/%d)\n' \
    "${BLUE:-}" "${_PROGRESS_TITLE}" "${NC:-}" \
    "${_PROGRESS_TITLE}" "${_PROGRESS_TOTAL}"
}

# Update progress
# Arguments:
#   $1 - Current item number (1-based)
#   $2 - (optional) Current item description
progress_update() {
  _PROGRESS_CURRENT="${1}"
  local description="${2:-}"

  local percent=0
  if [[ ${_PROGRESS_TOTAL} -gt 0 ]]; then
    percent=$(( (_PROGRESS_CURRENT * 100) / _PROGRESS_TOTAL ))
  fi

  # Calculate progress bar
  local bar_width=20
  local filled=$(( (percent * bar_width) / 100 ))
  local empty=$(( bar_width - filled ))

  local bar=""
  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++)); do bar+="░"; done

  if [[ -n "${description}" ]]; then
    printf '\r%b[%s]%b [%s] %3d%% (%d/%d) %s\033[K\n' \
      "${BLUE:-}" "${_PROGRESS_TITLE}" "${NC:-}" \
      "${bar}" "${percent}" "${_PROGRESS_CURRENT}" "${_PROGRESS_TOTAL}" "${description}"
  else
    printf '\r%b[%s]%b [%s] %3d%% (%d/%d)\033[K' \
      "${BLUE:-}" "${_PROGRESS_TITLE}" "${NC:-}" \
      "${bar}" "${percent}" "${_PROGRESS_CURRENT}" "${_PROGRESS_TOTAL}"
  fi
}

# Mark progress as complete
# Arguments:
#   $1 - (optional) Completion message
progress_complete() {
  local message="${1:-Complete}"

  local end_time
  end_time=$(date +%s)
  local elapsed=$(( end_time - _PROGRESS_START_TIME ))
  local elapsed_str
  elapsed_str=$(format_duration "${elapsed}")

  printf '\r%b[%s]%b %s (%d/%d) - %s\033[K\n' \
    "${GREEN:-}" "${_PROGRESS_TITLE}" "${NC:-}" "${message}" \
    "${_PROGRESS_TOTAL}" "${_PROGRESS_TOTAL}" "${elapsed_str}"

  # Reset state
  _PROGRESS_TOTAL=0
  _PROGRESS_CURRENT=0
  _PROGRESS_TITLE=""
  _PROGRESS_START_TIME=0
}

# Format a duration in seconds to human-readable string
# Arguments:
#   $1 - Duration in seconds
# Returns:
#   Prints formatted string (e.g., "2m 30s")
format_duration() {
  local seconds="${1}"

  if [[ ${seconds} -lt 60 ]]; then
    echo "${seconds}s"
  elif [[ ${seconds} -lt 3600 ]]; then
    local mins=$(( seconds / 60 ))
    local secs=$(( seconds % 60 ))
    echo "${mins}m ${secs}s"
  else
    local hours=$(( seconds / 3600 ))
    local mins=$(( (seconds % 3600) / 60 ))
    echo "${hours}h ${mins}m"
  fi
}

# Display a phase header with phase number
# Arguments:
#   $1 - Current phase number
#   $2 - Total phases
#   $3 - Phase description
phase_header() {
  local current="${1}"
  local total="${2}"
  local description="${3}"

  printf "\n"
  printf '%b\n' "${BOLD:-}${BLUE:-}╔════════════════════════════════════════════════════════════╗${NC:-}"
  printf '%b║%b  %bPhase %d/%d: %-46s%b║%b\n' \
    "${BOLD:-}${BLUE:-}" "${NC:-}" "${BOLD:-}" \
    "${current}" "${total}" "${description}" "${BLUE:-}" "${NC:-}"
  printf '%b\n' "${BOLD:-}${BLUE:-}╚════════════════════════════════════════════════════════════╝${NC:-}"
  printf "\n"
}

# Display an installation summary
# Arguments:
#   Variable number of "category:count" pairs
# Example:
#   summary_display "Applications:3" "Dev Tools:8" "Extensions:2"
summary_display() {
  printf "\n"
  printf '%b\n' "${BOLD:-}${GREEN:-}═══════════════════════════════════════════════════════════════${NC:-}"
  printf '%b\n' "${BOLD:-}${GREEN:-}                    INSTALLATION SUMMARY${NC:-}"
  printf '%b\n' "${BOLD:-}${GREEN:-}═══════════════════════════════════════════════════════════════${NC:-}"
  printf "\n"

  for item in "$@"; do
    local category="${item%%:*}"
    local count="${item##*:}"
    printf "  %-40s %s\n" "${category}:" "${count}"
  done

  printf "\n"
  printf '%b\n' "${BOLD:-}${GREEN:-}═══════════════════════════════════════════════════════════════${NC:-}"
}

# Display next steps after installation
# Arguments:
#   $@ - List of next steps (each as a separate argument)
summary_next_steps() {
  printf "\n"
  printf '%bNext Steps:%b\n' "${BOLD:-}" "${NC:-}"

  local step_num=1
  for step in "$@"; do
    printf "  %d. %s\n" "${step_num}" "${step}"
    ((step_num++))
  done

  printf "\n"
}
