#!/usr/bin/env bash
#
# colors.sh - Terminal color definitions
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/colors.sh"
#   echo -e "${GREEN}Success${NC}"
#
# shellcheck disable=SC2034  # Variables are used by sourcing scripts

# Detect if running in a terminal that supports colors
if [[ -t 1 ]]; then
  readonly RED='\033[0;31m'
  readonly GREEN='\033[0;32m'
  readonly YELLOW='\033[0;33m'
  readonly BLUE='\033[0;34m'
  readonly MAGENTA='\033[0;35m'
  readonly CYAN='\033[0;36m'
  readonly WHITE='\033[0;37m'
  readonly BOLD='\033[1m'
  readonly NC='\033[0m'  # No Color / Reset
else
  readonly RED=''
  readonly GREEN=''
  readonly YELLOW=''
  readonly BLUE=''
  readonly MAGENTA=''
  readonly CYAN=''
  readonly WHITE=''
  readonly BOLD=''
  readonly NC=''
fi
