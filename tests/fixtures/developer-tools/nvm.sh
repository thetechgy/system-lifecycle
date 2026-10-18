# shellcheck shell=bash
nvm() {
  printf '%s\n' "$*" >> "$TOOL_FIXTURE/nvm-calls"
  case "$1" in
    --version) printf '0.40.8\n' ;;
    which)
      local version="$2"
      if [ "$version" = default ]; then version="$(cat "$NVM_DIR/default")"; fi
      printf '%s/versions/node/%s/bin/node\n' "$NVM_DIR" "$version"
      ;;
    version-remote) printf '%s\n' "$FIXTURE_NODE_VERSION" ;;
    install)
      shift
      if [ "$1" = --skip-default-packages ]; then shift; fi
      if [ ! -d "$NVM_DIR/versions/node/$1" ]; then
        cp -a "$TOOL_FIXTURE/destination" "$NVM_DIR/versions/node/$1"
      fi
      ;;
    alias) printf '%s' "$3" > "$NVM_DIR/default" ;;
    use) : ;;
    install-latest-npm) : ;;
    *) return 9 ;;
  esac
}
