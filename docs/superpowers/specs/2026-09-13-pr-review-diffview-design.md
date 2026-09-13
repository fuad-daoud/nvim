# PR review in Neovim via diffview.nvim

## Goal

Make large GitHub PRs easier to review from Neovim: a panel listing only the
changed files, side-by-side diffs with hunk navigation, and the working-tree
side as a real buffer so LSP (`gd`, hover) works while reading.

Commenting on the PR is out of scope (octo.nvim can be added later if wanted).

## Components

### `lua/plugins/diffview.lua`

Lazy.nvim spec for `sindrets/diffview.nvim`:

- Lazy-loaded on `cmd = { 'DiffviewOpen', 'DiffviewClose', 'DiffviewFileHistory', 'PrReview' }`.
- Uses nvim-web-devicons already present (via snacks/lualine deps); no new deps.
- `opts`: `enhanced_diff_hl = true`, `view.merge_tool.layout = 'diff3_mixed'`
  (defaults otherwise).

### Base-branch detection

Helper `pr_base()` in the same file:

1. If inside a git repo and on a PR branch, run
   `gh pr view --json baseRefName -q .baseRefName` (synchronous, `vim.system`).
2. On success return `origin/<baseRefName>`; on failure (no PR, gh error) fall
   back to `origin/master`.

### `:PrReview [number]`

User command defined in the spec's `config`:

1. If a number is given, run `gh pr checkout <number>` (synchronous; abort with
   `vim.notify` error on non-zero exit).
2. Run `git fetch origin <base>` so the merge base is current — non-fatal on
   failure.
3. `:DiffviewOpen <base>...HEAD` using `pr_base()`.

Without a number it just opens diffview against the base of the current branch.

### Keymaps (global, defined in `keys`)

| Key | Action |
|-----|--------|
| `<leader>gv` | `:PrReview` (current branch vs detected base) |
| `<leader>gV` | `:DiffviewClose` |

Inside diffview, stock bindings apply: `<Tab>`/`<S-Tab>` next/prev file,
`]c`/`[c` hunks, `-` toggle viewed, `g?` help.

### Docs

Add a `diffview.lua` section to `lua/plugins/CLAUDE.md` with the command,
keymaps, and workflow (`:PrReview 464` → `<Tab>` through files).

## Error handling

- `gh` missing or not authed → `gh pr checkout` fails → notify with stderr, stop.
- Not a PR branch → `pr_base()` falls back to `origin/master` silently.

## Testing

Manual: `:PrReview <num>` on a real PR in a repo with a GitHub remote; `<leader>gv`
on a plain branch; `<leader>gV` closes. `stylua --check .` passes.
