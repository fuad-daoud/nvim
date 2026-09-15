#!/usr/bin/env bash
# Install every external tool the Neovim config depends on, on Arch or Ubuntu.
#   ./install.sh          install what is missing, then check
#   ./install.sh --check  only report what is missing (exit 1 if anything is)
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=install/common.sh
. "$HERE/install/common.sh"
# shellcheck source=install/manifest.sh
. "$HERE/install/manifest.sh"

check() {
  local ok=1 bin want got
  printf '%-28s %s\n' 'tool' 'status'
  for bin in "${REQUIRED_BINS[@]}"; do
    if ! have "$bin"; then
      printf '%-28s \033[31m✗ missing\033[0m\n' "$bin"
      ok=0
    elif [ -n "${MIN_VERSION[$bin]:-}" ]; then
      want=${MIN_VERSION[$bin]}
      got=$(bin_version "$bin")
      if version_ge "$got" "$want"; then
        printf '%-28s \033[32m✓\033[0m %s\n' "$bin" "$got"
      else
        printf '%-28s \033[31m✗ %s < %s\033[0m\n' "$bin" "$got" "$want"
        ok=0
      fi
    else
      printf '%-28s \033[32m✓\033[0m\n' "$bin"
    fi
  done
  if [ -d "$MAGICK_ROCK" ]; then
    printf '%-28s \033[32m✓\033[0m\n' 'magick (luarock)'
  else
    printf '%-28s \033[31m✗ missing (%s)\033[0m\n' 'magick (luarock)' "$MAGICK_ROCK"
    ok=0
  fi
  [ "$ok" = 1 ]
}

main() {
  if [ "${1:-}" = --check ]; then
    check
    return
  fi
  [ $# -eq 0 ] || die "usage: $0 [--check]"

  DISTRO=$(detect_distro)
  ARCH=$(detect_arch)
  export DISTRO ARCH
  log "distro=$DISTRO arch=$ARCH"
  sudo -v

  # shellcheck disable=SC1090
  . "$HERE/install/$DISTRO.sh"
  # shellcheck source=install/shared.sh
  . "$HERE/install/shared.sh"

  log 'checking'
  check
}

main "$@"
