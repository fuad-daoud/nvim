# shellcheck shell=bash
# Distro-agnostic layer: tools installed through go, npm and luarocks so that
# Arch and Ubuntu get byte-identical versions. Runs after the base layer.

# zls must match zig's minor and distro packages (the AUR in particular) lag
# behind zig, so both distros take the matching GitHub release.
if ! have_version zls "$ZLS_VERSION"; then
  install_release zls \
    "https://github.com/zigtools/zls/releases/download/${ZLS_VERSION}/zls-${ARCH}-linux.tar.xz" \
    0 zls
fi

log 'shared: go tools'
GOBIN=$(go env GOBIN)
[ -n "$GOBIN" ] || GOBIN=$(go env GOPATH)/bin
# Remember whether the user's own PATH has GOBIN before we prepend it for this run.
case ":$PATH:" in
  *":$GOBIN:"*) GOBIN_ON_PATH=1 ;;
  *) GOBIN_ON_PATH=0 ;;
esac
export PATH="$GOBIN:$PATH"
go_tool() { # go_tool <binary> <module path>
  have "$1" || go install "$2@latest"
}
go_tool gopls golang.org/x/tools/gopls
go_tool goimports golang.org/x/tools/cmd/goimports
go_tool golines github.com/segmentio/golines
go_tool gomodifytags github.com/fatih/gomodifytags
go_tool dlv github.com/go-delve/delve/cmd/dlv
go_tool templ github.com/a-h/templ/cmd/templ
go_tool shfmt mvdan.cc/sh/v3/cmd/shfmt
go_tool actionlint github.com/rhysd/actionlint/cmd/actionlint

log 'shared: npm packages'
npm_tool() { # npm_tool <binary> <package>
  have "$1" || sudo npm install -g "$2"
}
npm_tool prettier prettier
npm_tool prettierd @fsouza/prettierd
npm_tool yaml-language-server yaml-language-server
npm_tool bash-language-server bash-language-server
npm_tool tailwindcss-language-server @tailwindcss/language-server
npm_tool mmdc @mermaid-js/mermaid-cli

# mmdc renders through puppeteer, which keeps its browser in $HOME/.cache/puppeteer,
# so the download must run as the user, not under sudo (a root-owned copy under
# /root is invisible to the user, and `have mmdc` cannot tell). Probe with a real
# render; install the browser only if it fails.
ensure_mmdc_browser() {
  local probe="$INSTALL_TMP/probe" pkg
  printf 'graph TD; a-->b\n' >"$probe.mmd"
  mmdc -i "$probe.mmd" -o "$probe.png" >/dev/null 2>&1 && return
  log 'shared: puppeteer browser for mmdc'
  pkg=$(dirname "$(dirname "$(readlink -f "$(command -v mmdc)")")") # …/@mermaid-js/mermaid-cli
  node "$pkg/node_modules/puppeteer/install.mjs"
  # keep the second probe's stderr: it names the real cause (missing libs, sandbox/AppArmor, …)
  if ! mmdc -i "$probe.mmd" -o "$probe.png" >/dev/null 2>"$probe.err"; then
    cat "$probe.err" >&2
    die 'mmdc still cannot render after installing the puppeteer browser'
  fi
}
ensure_mmdc_browser

log 'shared: magick luarock'
[ -d "$MAGICK_ROCK" ] || luarocks --lua-version 5.1 install magick --local

[ "$GOBIN_ON_PATH" = 1 ] || warn "add $GOBIN to your PATH (go-installed tools live there)"
