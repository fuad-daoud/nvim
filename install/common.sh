# shellcheck shell=bash
# Helpers shared by install.sh and the install/*.sh layers.

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die() {
  printf '\033[1;31merror:\033[0m %s\n' "$*" >&2
  exit 1
}
have() { command -v "$1" >/dev/null 2>&1; }

# version_ge 1.2.3 1.2.0 -> true when $1 >= $2 (semver-ish, via sort -V)
version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }

# bin_version <bin> -> prints the installed version normalized to X.Y.Z
bin_version() {
  case "$1" in
    nvim) nvim --version | head -n1 | sed -E 's/^NVIM v([0-9.]+).*/\1/' ;;
    go) go version | sed -E 's/^go version go([0-9.]+).*/\1/' ;;
    node) node --version | sed 's/^v//' ;;
    zig) zig version ;;
    zls) zls --version ;;
    ruff) ruff --version | awk '{print $2}' ;;
    stylua) stylua --version | awk '{print $2}' ;;
    # anchor on ", version=": the line also ends with "git version=X.Y.Z"
    lazygit) lazygit --version | sed -E 's/.*, version=([0-9.]+).*/\1/' ;;
    lua-language-server) lua-language-server --version | sed -E 's/^[^0-9]*([0-9.]+).*/\1/' ;;
    *) die "bin_version: no version parser for '$1'" ;;
  esac
}

# have_version <bin> <min> -> true when <bin> is on PATH at version >= <min>
have_version() { have "$1" && version_ge "$(bin_version "$1")" "$2"; }

# All scratch files live under one dir removed when the script exits for any
# reason (normal end, die, set -e abort), so no failure path leaks temp files.
# The same trap stops the sudo keepalive loop install.sh starts (if any).
INSTALL_TMP=$(mktemp -d)
SUDO_KEEPALIVE_PID=
cleanup() {
  # set -e is active in the trap: a dead keepalive must not abort the tmp cleanup
  [ -z "$SUDO_KEEPALIVE_PID" ] || kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
  rm -rf "$INSTALL_TMP"
}
trap cleanup EXIT

# detect_distro -> prints arch|ubuntu, dies otherwise. OS_RELEASE overrides the file (tests).
detect_distro() {
  local f="${OS_RELEASE:-/etc/os-release}" id like
  [ -r "$f" ] || die "cannot read $f"
  # shellcheck disable=SC1090
  read -r id like < <(. "$f" && printf '%s %s\n' "${ID:-}" "${ID_LIKE:-}")
  case " $id $like " in
    *" arch "*) echo arch ;;
    *" ubuntu "* | *" debian "*) echo ubuntu ;;
    *) die "unsupported distro '$id' (supported: arch, ubuntu/debian-like)" ;;
  esac
}

# detect_arch -> prints x86_64|aarch64, dies otherwise
detect_arch() {
  case "$(uname -m)" in
    x86_64) echo x86_64 ;;
    aarch64 | arm64) echo aarch64 ;;
    *) die "unsupported architecture '$(uname -m)' (supported: x86_64, aarch64)" ;;
  esac
}

# install_release <name> <url> <strip-components> <bin-relpath>...
# Download an archive, verify it, unpack into /opt/<name> (replacing any previous
# install) and symlink each listed binary into /usr/local/bin. Allocates a per-call
# temp dir under INSTALL_TMP (cleaned on script exit); removes it on success.
# A failed download or corrupt archive dies before /opt is touched. Zip archives
# require strip-components=0.
install_release() {
  local name=$1 url=$2 strip=$3
  shift 3
  case "$url" in
    *.zip) [ "$strip" = 0 ] || die "install_release: strip-components is only supported for tar archives ($url)" ;;
  esac
  local tmp
  tmp=$(mktemp -d -p "$INSTALL_TMP")
  log "installing $name from $url"
  curl -fsSL -o "$tmp/archive" "$url"
  mkdir "$tmp/root"
  case "$url" in
    *.zip)
      unzip -tq "$tmp/archive" >/dev/null
      unzip -q "$tmp/archive" -d "$tmp/root"
      ;;
    *.tar.xz)
      tar -tJf "$tmp/archive" >/dev/null
      tar -xJf "$tmp/archive" -C "$tmp/root" --strip-components="$strip"
      ;;
    *.tar.gz)
      tar -tzf "$tmp/archive" >/dev/null
      tar -xzf "$tmp/archive" -C "$tmp/root" --strip-components="$strip"
      ;;
    *) die "install_release: unknown archive type in $url" ;;
  esac
  sudo rm -rf "/opt/$name"
  sudo mv "$tmp/root" "/opt/$name"
  sudo chown -R root:root "/opt/$name"
  local rel
  for rel in "$@"; do
    sudo chmod +x "/opt/$name/$rel"
    sudo ln -sfn "/opt/$name/$rel" "/usr/local/bin/$(basename "$rel")"
  done
  rm -rf "$tmp"
}
