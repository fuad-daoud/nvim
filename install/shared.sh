# shellcheck shell=bash
# Distro-agnostic layer: tools installed through go, npm and luarocks so that
# Arch and Ubuntu get byte-identical versions. Runs after the base layer.

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
npm_tool() { # npm_tool <binary> <package> [extra npm flags...]
  local bin=$1 pkg=$2
  shift 2
  have "$bin" || sudo npm install -g "$@" "$pkg"
}
npm_tool prettier prettier
npm_tool prettierd @fsouza/prettierd
npm_tool yaml-language-server yaml-language-server
npm_tool bash-language-server bash-language-server
npm_tool tailwindcss-language-server @tailwindcss/language-server
# --allow-scripts is required or puppeteer skips its Chromium download and mmdc fails at runtime
npm_tool mmdc @mermaid-js/mermaid-cli --allow-scripts=puppeteer

log 'shared: magick luarock'
[ -d "$MAGICK_ROCK" ] || luarocks --lua-version 5.1 install magick --local

[ "$GOBIN_ON_PATH" = 1 ] || warn "add $GOBIN to your PATH (go-installed tools live there)"
