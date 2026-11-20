# Neovim Configuration

A modern Neovim configuration written in Lua with LSP support for Kotlin/Android, Rust/WebAssembly, and more.

## Features

- **Plugin Management**: lazy.nvim for fast, lazy-loading plugins
- **LSP Support**: Rust (rust-analyzer from rustup), and Kotlin (JetBrains kotlin-lsp), Java, C/C++, Haskell, Python (basedpyright and ruff), Lua and Gradle via mason.nvim
- **WebAssembly**: treesitter highlighting for WIT files; bootstrap.sh installs the wasm-tools CLI and the wasm32 Rust targets
- **Autoformatting**: conform.nvim with ktfmt for Kotlin, google-java-format for Java, StyLua for Lua in projects with a `stylua.toml` (all three installed by Mason), ruff for Python, rustfmt for Rust
- **Linting**: nvim-lint with detekt for Kotlin, shellcheck for shell scripts and selene for Lua in projects with a `selene.toml` (all three installed by Mason)
- **Completion**: blink.cmp with LSP, file path, snippet (friendly-snippets) and buffer word sources, plus `:` and `/` command-line completion
- **Fuzzy Finding**: snacks.picker (files, grep, buffers, symbols, diagnostics, help, keymaps, git) with ripgrep backend
- **Theme**: Nordic colorscheme with optimized UI

## Installation

### Quick Start (Recommended)

```bash
# Clone the repository
git clone https://github.com/oas004/dotfiles.git ~/.config/nvim

# Run the bootstrap script (works on macOS and Linux)
~/.config/nvim/bootstrap.sh
```

The bootstrap script installs all dependencies including Neovim, the Rust toolchain (with the rust-analyzer and rustfmt components), wasm-tools, a JDK 21, python3 with venv, jq, lazygit and the tools Mason needs, and syncs plugins. Plugins are installed at the versions in `lazy-lock.json` (`:Lazy! restore`), and the script fails if a plugin or treesitter parser can't be installed. It also fails if an existing Neovim is older than 0.11.

On Debian/Ubuntu, apt's `neovim` package is older than 0.11, so the script installs the official release build instead: it extracts `nvim-linux-x86_64.tar.gz` (or `nvim-linux-arm64.tar.gz`) from https://github.com/neovim/neovim/releases into `~/.local/opt/nvim` and symlinks `~/.local/bin/nvim` to it. Make sure `~/.local/bin` is on your PATH. Set `NVIM_RELEASE` to pick a release tag (default `stable`, e.g. `NVIM_RELEASE=v0.12.0`).

jdtls needs Java 21+ and uses `JAVA_HOME` if it is set, otherwise `java` on PATH; gradle_ls and ktfmt use `java` on PATH. If that is an older Java, the script installs JDK 21 (or, on macOS, finds one that is already installed) and prints the `JAVA_HOME` and `PATH` lines to add to your shell profile. Homebrew's `openjdk@21` is keg-only, so on macOS you need to set them either way.

The script does not install ghcup, which Mason uses to install haskell-language-server. It warns if ghcup is missing; to use Haskell, install ghcup and GHC with `curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh`.

The language servers (kotlin-lsp included) and the ktfmt, google-java-format and StyLua formatters are installed by Mason, not by the script. Mason starts installing whatever is missing the first time you open Neovim; `:Mason` shows the progress. Mason's bin directory (`~/.local/share/nvim/mason/bin`) is put on PATH inside Neovim only, so these tools are not on your shell's PATH. ktfmt is a jar that Mason runs with `java -jar`, so it needs Java 17+ as `java` on PATH.

### Manual Setup

#### Prerequisites

- [Neovim 0.11+](https://neovim.io/) (recommended: 0.12+, which nvim-treesitter's main branch requires; on 0.11 the config pins an older main commit)
- [Git](https://git-scm.com/)
- [Rust](https://rustup.rs/) with the `rust-analyzer` and `rustfmt` components (`rustup component add rust-analyzer rustfmt`), plus the wasm tools
- `ripgrep` (for the file and grep pickers)
- [`tree-sitter` CLI](https://github.com/tree-sitter/tree-sitter/blob/master/crates/cli/README.md) 0.26.1+ (not the npm package), plus `curl`, `tar` and a C compiler, for installing treesitter parsers
- `unzip` and `gzip`, which Mason uses along with `curl`, `git` and `tar` to download and extract servers
- JDK 21+ for jdtls, gradle_ls and ktfmt, as `java` on PATH (and `JAVA_HOME`, if you set it)
- `python3` with the `venv` module (`python3-venv` on Debian/Ubuntu), for basedpyright (Mason installs it from PyPI into a venv) and the jdtls launcher
- [ghcup](https://www.haskell.org/ghcup/) and GHC, for haskell-language-server (optional)
- `jq` (json formatter)
- [lazygit](https://github.com/jesseduffield/lazygit), for `<leader>gg` (optional)

#### macOS
```bash
brew install neovim ripgrep tree-sitter-cli jq openjdk@21
# openjdk@21 is keg-only, so point JAVA_HOME and PATH at it in your shell profile
export JAVA_HOME="$(brew --prefix)/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"
export PATH="$JAVA_HOME/bin:$PATH"
```

#### Ubuntu/Debian
```bash
sudo apt-get update
sudo apt-get install ripgrep build-essential curl git unzip jq openjdk-21-jdk python3 python3-venv
cargo install --locked tree-sitter-cli  # apt's tree-sitter-cli is usually too old
# apt's neovim is older than 0.11, so use the release build
# (on arm64, replace nvim-linux-x86_64 with nvim-linux-arm64)
mkdir -p ~/.local/opt ~/.local/bin
curl -fL https://github.com/neovim/neovim/releases/download/stable/nvim-linux-x86_64.tar.gz | tar xz -C ~/.local/opt
mv ~/.local/opt/nvim-linux-x86_64 ~/.local/opt/nvim
ln -sf ~/.local/opt/nvim/bin/nvim ~/.local/bin/nvim
```

#### Fedora
```bash
sudo dnf install neovim ripgrep tree-sitter-cli gcc unzip jq java-21-openjdk-devel python3
```


#### Setup Steps

1. **Backup your current config** (if you have one):
   ```bash
   mv ~/.config/nvim ~/.config/nvim.bak
   ```

2. **Clone this repository**:
   ```bash
   git clone https://github.com/oas004/dotfiles.git ~/.config/nvim
   ```

3. **Start Neovim** - lazy.nvim will automatically bootstrap and install plugins:
   ```bash
   nvim
   ```

4. **Let Mason install the LSP servers and formatters** (kotlin-lsp, ktfmt, google-java-format and StyLua included). This starts on its own; follow it with:
   ```
   :Mason
   ```

### Neovim 0.12 and nvim-treesitter

On Neovim 0.11, `lua/plugins/parser.lua` pins nvim-treesitter to the last main commit that supports 0.11, and on 0.12+ it follows main. `lazy-lock.json` can only record one commit, so it records the 0.11 one, and a first install or `:Lazy restore` (which bootstrap.sh runs) checks out that commit on 0.12 too. On Neovim 0.12+, run this after a restore:

```vim
:Lazy update nvim-treesitter
```

That moves nvim-treesitter to current main, so you get the parser and query fixes made since the pin. It also changes nvim-treesitter's entry in `lazy-lock.json`. Don't commit that change: a restore on 0.11 would then check out a commit that no longer supports 0.11. `bootstrap.sh` reminds you of this step at the end when it finds Neovim 0.12 or newer.

This is temporary. Once 0.12 is the minimum supported version, the pin, this step and CI's workaround for it go away ([#28](https://github.com/oas004/dotfiles/issues/28)).

### Rust / WebAssembly Development

The bootstrap script installs everything, but if you need to set up manually:

```bash
# Install Rust toolchain
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Add components
rustup component add rust-analyzer rustfmt

# WebAssembly targets
rustup target add wasm32-unknown-unknown
rustup target add wasm32-wasip1

# WebAssembly tooling
cargo install wasm-tools wit-bindgen-cli
```

### Kotlin Development

Mason installs the JetBrains kotlin-lsp and the ktfmt formatter, so there is nothing to install by hand. kotlin-lsp (~370 MB) ships its own Java runtime; ktfmt runs on `java` from PATH (Java 17+).

See [KOTLIN_SETUP.md](KOTLIN_SETUP.md) for more details.

## Keybindings

### Leader Key

The leader key is `<Space>`, and the local leader (used by some filetype plugins) is `\`.

Leader maps are grouped by a mnemonic letter: `a` Claude, `c` code, `f` find, `g` git (pickers and lazygit), `h` git hunks, `n` new, `u` toggles, `w` sessions, `x` lists, `y` yank. Planned features get their own groups: `d` debug and `t` test. The pickers used to be single letters (`<leader>p`, `o`, `r`, `s`, `S`); those still work as aliases of the `<leader>f` maps and will be removed later. The old `<leader>f` (grep) is now `<leader>fg`, since `<leader>f` is the group. `<leader>e`/`<leader>E` (diagnostics) and `<leader>l`/`<leader>L` (file explorer) stay as they are.

### which-key

[which-key.nvim](https://github.com/folke/which-key.nvim) shows a popup with the keys that can follow a prefix (`<leader>`, `g`, `z`, `]`, ...) when you pause after typing it. It loads right after startup. The `<leader>` groups are `a` (Claude), `c` (code), `f` (find), `g` (git), `h` (git hunks), `n` (new), `u` (toggles), `w` (sessions), `x` (lists) and `y` (yank); a group only shows up when something is mapped under it. `<leader>?` lists the keymaps local to the current buffer, such as the LSP maps. `:checkhealth which-key` reports overlapping and duplicate mappings.

### LSP Navigation

`gd`, `gD`, `gI`, `gy`, `gs` and insert-mode `<C-k>` are set only in buffers with an attached language server. `grr`, `grn`, `gra`, `gri`, `gO` and `K` are Neovim's built-in LSP defaults.

Neovim's own insert-mode `<C-s>` for signature help is replaced by save, so it is on `<C-k>` instead. In those buffers `<C-k>` no longer starts a digraph. It still does elsewhere, and in LSP buffers `:digraphs` lists each digraph with its code point, which `<C-v>u` followed by the hex value inserts.

| Keys | Action |
|------|--------|
| `gd` | Go to definition |
| `gD` | Go to declaration |
| `gI` | Go to implementation |
| `grr` | Find references/usages |
| `grn` | Rename symbol |
| `gra` | Code actions |
| `gri` | Go to implementation |
| `gy` | Go to type definition |
| `gs` | Show function signature |
| `<C-k>` | Show function signature (insert mode) |
| `gO` | Document symbols |
| `K` | Show hover documentation |

### Diagnostics

| Keys | Action |
|------|--------|
| `gl` | Show line diagnostics (error popup) |
| `<leader>e` | Next diagnostic (shows it in a float) |
| `<leader>E` | Previous diagnostic (shows it in a float) |

### Linting (nvim-lint)

[nvim-lint](https://github.com/mfussenegger/nvim-lint) adds diagnostics from linters the language servers don't run. They show up like LSP diagnostics, with the linter as the source.

| Filetype | Linter | Runs on |
|------|--------|--------|
| Kotlin | [detekt](https://detekt.dev) | open and save |
| sh, bash | [shellcheck](https://www.shellcheck.net) | open and save |
| Lua | [selene](https://github.com/Kampfkarren/selene), only below a `selene.toml` | open, save and leaving insert mode |

detekt and shellcheck read the saved file, so they run on open and save only; selene reads the buffer. detekt analyses just the current file, from the Gradle project root (the directory with `settings.gradle(.kts)`, else the git root). If the project has `config/detekt/detekt.yml`, `detekt.yml` or `.detekt.yml`, it is used on top of detekt's defaults, like the Gradle plugin's `buildUponDefaultConfig`, and `config/detekt/baseline.xml` or `detekt-baseline.xml` is used as the baseline. detekt is a JVM program and needs `java` on PATH; a run takes about a second.

Mason installs all three. A linter that isn't installed is skipped without a message. Python has no linter here, since the ruff language server covers it.

### Lists (trouble.nvim)

[trouble.nvim](https://github.com/folke/trouble.nvim) shows diagnostics, symbols and LSP locations as a list in a split. It loads the first time one of these keys (or `:Trouble`) is used. Each key opens the list, or closes it if it is already open.

| Keys | Action |
|------|--------|
| `<leader>xx` | Diagnostics in the workspace |
| `<leader>xX` | Diagnostics in the current buffer |
| `<leader>xs` | Symbols in the current buffer |
| `<leader>xr` | LSP definitions, references and implementations of the symbol under the cursor |
| `<leader>xq` | Quickfix list |
| `<leader>xl` | Location list |
| `]q` / `[q` | Next/previous item in an open trouble list, jumping to it. Without one, Neovim's built-in `:cnext`/`:cprevious` |

In the list, `<CR>` jumps to an item, `p` previews it, `q` closes the list and `?` shows the other keys.

### Code Actions & Refactoring

| Keys | Action |
|------|--------|
| `<leader>ca` / `<F4>` | Code actions (quick fixes) |
| `<leader>cr` / `<F2>` / `<S-F6>` | Rename symbol |
| `<leader>cf` | Format buffer |
| `<leader>cl` / `grx` | Run the code lens on the current line |

### Inlay Hints and Code Lenses

Inlay hints (inferred types and parameter names, shown inline) are on in every buffer whose language server provides them: for example rust-analyzer, clangd, jdtls and lua_ls. `<leader>uh` turns them off and on in all buffers.

Code lenses are shown too, such as jdtls' reference and implementation counts and rust-analyzer's references. On Neovim 0.12 they appear as virtual lines above the code, and on 0.11 at the end of the line, refreshed when you enter the buffer, leave insert mode or save. `grx` (built in on 0.12, added on 0.11) or `<leader>cl` runs the lens on the current line. Lenses that need client-side support, like rust-analyzer's Run and Debug, report that the command isn't supported.

### Python

basedpyright checks types and answers hover, go to definition and the like. ruff's language server lints, offers fixes and import sorting as code actions (`gra`), and `ruff format` formats Python on save. Both come from Mason, and both read a project's `pyproject.toml` (`[tool.basedpyright]`, `[tool.ruff]`). To avoid duplicate diagnostics, basedpyright runs in pyright's `standard` mode and leaves undefined names, unused expressions and redefinitions to ruff. A `[tool.basedpyright]` section in a project replaces those editor settings.

### LSP Progress

[fidget.nvim](https://github.com/j-hui/fidget.nvim) shows what language servers report while they work, such as jdtls and kotlin-lsp importing a Gradle project or rust-analyzer indexing, in the bottom-right corner. It loads when the first server attaches. Only progress goes there; `vim.notify` messages are shown the usual way.

### Completion

[blink.cmp](https://github.com/saghen/blink.cmp) completes from the language server, file paths, snippets ([friendly-snippets](https://github.com/rafamadriz/friendly-snippets) plus the ones language servers send, expanded with Neovim's built-in `vim.snippet`) and words in open buffers. The menu shows where each item comes from, e.g. `[LSP]` or `[Buffer]`, and documentation for the selected item. Nothing is selected until you move into the menu.

| Keys (insert mode) | Action |
|------|--------|
| `<C-Space>` | Open the menu |
| `<Tab>` / `<S-Tab>` | Menu open: next/previous item. Otherwise jump to the next/previous snippet placeholder, otherwise insert a tab. In a selected snippet placeholder they always jump. |
| `<Up>` / `<Down>` | Previous/next item |
| `<C-n>` / `<C-p>` | Next/previous item, inserting it as you go; open the menu if it is closed |
| `<CR>` | Accept the selected item, or the first one if none is selected |
| `<C-y>` | Accept the selected item (with nothing selected, Neovim's `i_CTRL-Y`) |
| `<C-e>` | Close the menu and undo the inserted item |
| `<C-u>` / `<C-d>` | Scroll the documentation |

On the `:` and `/` command lines, `<Tab>` opens the menu (or completes the only match) and moves through it, `<S-Tab>` moves back, `<C-y>` accepts and `<C-e>` closes it.

Fuzzy matching uses a prebuilt binary that blink downloads from its GitHub release when it is installed or updated (`:Lazy! restore` in `bootstrap.sh` does this too). If the download fails, it uses its Lua matcher instead, which is a bit slower and doesn't correct typos.

### Android Studio-style keys (macOS)

These need a terminal or GUI that passes Cmd (and Option as Alt) through to Neovim. The LSP ones are set only in buffers with an attached language server.

| Keys | Action |
|------|--------|
| `<D-b>` | Go to definition |
| `<D-A-b>` | Go to implementation |
| `<A-F7>` | Find usages |
| `<A-CR>` | Code actions |
| `<D-S-o>` | Find files |
| `<D-o>` | Document symbols |
| `<D-A-o>` | Workspace symbols |
| `<D-S-f>` | Find in files (grep) |
| `<D-e>` | Recent files |

### File Navigation (snacks.picker)

The pickers come from [snacks.picker](https://github.com/folke/snacks.nvim/blob/main/docs/picker.md). Where a picker has a buffer and a workspace version, lowercase is the current buffer and uppercase the whole workspace.

| Keys | Old alias | Action |
|------|-----------|--------|
| `<leader>ff` | `<leader>p` | Find files |
| `<leader>fg` | | Find in files (grep) |
| `<leader>fw` | | Grep the word under the cursor (visual mode: the selection) |
| `<leader>fb` | `<leader>o` | Open buffers |
| `<leader>fr` | `<leader>r` | Recent files |
| `<leader>fs` | `<leader>s` | Document symbols (outline of current file) |
| `<leader>fS` | `<leader>S` | Workspace symbols (search across project) |
| `<leader>fd` | | Diagnostics in the current buffer |
| `<leader>fD` | | Diagnostics in the workspace |
| `<leader>fh` | | Help tags |
| `<leader>fk` | | Keymaps |
| `<leader>f.` | | Resume the last picker |
| `<leader>gs` | | Git status |
| `<leader>gl` | | Git log |
| `<leader>gL` | | Git log of the current file |

Hidden files and files ignored by git are left out; `<M-h>` and `<M-i>` in a picker toggle them. `.git/` is always left out, and so is `node_modules/`, even where no `.gitignore` lists it. In the open buffers picker, `<M-d>` (insert or normal mode), `<leader>q` (normal mode), `<C-x>` or `dd` in the list closes the selected buffer.

### File Explorer

| Keys | Action |
|------|--------|
| `<leader>l` | Toggle file explorer |
| `<leader>L` | Reveal current file in explorer |

### Window navigation and tmux

| Keys | Action |
|------|--------|
| `<C-h>` `<C-j>` `<C-k>` `<C-l>` | Move to the window left/below/above/right, or past the last window into the tmux pane there |
| `<A-h>` `<A-j>` `<A-k>` `<A-l>` | Resize the window (takes a count) |

These come from [smart-splits.nvim](https://github.com/smart-splits-nvim/smart-splits.nvim) with its tmux backend, and are normal mode only, so in terminal mode (the Claude Code terminal) the keys still go to the program. `<C-l>` replaces Neovim's default redraw/clear-highlight map; `<Esc>` clears search highlighting. In nvim-tree, `<C-k>` is nvim-tree's own file info map. On macOS the `<A-…>` maps need the terminal to send Option as Meta (Alt).

Outside tmux the keys just move between Neovim windows. Inside tmux, tmux needs bindings that pass the keys to Neovim when the pane runs it (smart-splits sets the pane option `@pane-is-vim` while Neovim runs) and move between panes otherwise. Add this to `~/.tmux.conf` and reload it with `tmux source-file ~/.tmux.conf`:

```tmux
bind -n C-h if -F '#{@pane-is-vim}' { send-keys C-h } { select-pane -L }
bind -n C-j if -F '#{@pane-is-vim}' { send-keys C-j } { select-pane -D }
bind -n C-k if -F '#{@pane-is-vim}' { send-keys C-k } { select-pane -U }
bind -n C-l if -F '#{@pane-is-vim}' { send-keys C-l } { select-pane -R }

bind -n M-h if -F '#{@pane-is-vim}' { send-keys M-h } { resize-pane -L 3 }
bind -n M-j if -F '#{@pane-is-vim}' { send-keys M-j } { resize-pane -D 3 }
bind -n M-k if -F '#{@pane-is-vim}' { send-keys M-k } { resize-pane -U 3 }
bind -n M-l if -F '#{@pane-is-vim}' { send-keys M-l } { resize-pane -R 3 }

bind -T copy-mode-vi C-h select-pane -L
bind -T copy-mode-vi C-j select-pane -D
bind -T copy-mode-vi C-k select-pane -U
bind -T copy-mode-vi C-l select-pane -R
```

These bind the keys without the tmux prefix, so in panes that don't run Neovim (a shell, or Claude Code started directly in tmux) the keys move between panes instead of reaching the program: the shell's `<C-l>` (clear screen) and `<C-k>` (kill to end of line) are gone there. At the edge of the tmux window, focus wraps to the pane on the far side, which matches smart-splits' default `move.at_edge = "wrap"`. The backend's [README](https://github.com/smart-splits-nvim/backend-tmux#tmux) has variants that stop at the edge or create a pane instead. `:checkhealth smart-splits` shows whether the tmux backend is in use and which tmux keys defer to Neovim.

### General

| Keys | Action |
|------|--------|
| `<Esc>` | Clear search highlighting |
| `<C-s>` | Save file (normal, insert and visual mode) |
| `jj` or `jk` | Exit insert mode |
| `;;` | Exit visual mode |
| `<leader>ne` | New file in the current file's directory |
| `<C-o>` | Jump back (after go to definition) |
| `<C-i>` | Jump forward |

### Terminal

`<C-/>` opens a shell in a split at the bottom, or hides it again; the shell keeps running while it is hidden. A count picks another shell, so `2<C-/>` toggles a second one. It comes from [snacks.terminal](https://github.com/folke/snacks.nvim/blob/main/docs/terminal.md). Most terminals send Ctrl+/ as `<C-_>`, which is mapped too.

| Keys | Action |
|------|--------|
| `<C-/>` | Toggle the shell (normal mode, and terminal mode inside that shell) |
| `<Esc><Esc>` | Leave terminal mode (a single `<Esc>` goes to the program) |
| `q` | Hide the terminal (in normal mode inside it) |

In the Claude Code terminal, Ctrl+/ goes to Claude, since the terminal-mode map only exists in the shell's own buffer. To move to another window from a terminal, leave terminal mode with `<Esc><Esc>` first; `<C-h/j/k/l>` aren't mapped in terminal mode because shells use them (backspace, newline, kill line, clear).

### Indent Guides

[snacks.indent](https://github.com/folke/snacks.nvim/blob/main/docs/indent.md) draws a thin guide for each indent level, and the guide of the scope around the cursor a little brighter. They are only drawn in file buffers, not in help, terminals (including the Claude Code terminal), nvim-tree, lazy or Mason. `<leader>ui` turns them off and on.

### Sessions

[persistence.nvim](https://github.com/folke/persistence.nvim) saves a session (windows, open files, folds, the working directory) when Neovim exits, one per directory and git branch, as long as a file was open. Nothing is restored automatically.

| Keys | Action |
|------|--------|
| `<leader>ws` | Restore the session for the current directory (and branch, falling back to the directory's session) |
| `<leader>wl` | Restore the last saved session |
| `<leader>wS` | Pick a session from a list |
| `<leader>wd` | Don't save a session when this Neovim exits |

Terminals (the Claude Code terminal and `<C-/>` shells), nvim-tree and trouble windows aren't saved, so a restored session only has file windows. Sessions are stored in `~/.local/state/nvim/sessions/`.

### Treesitter Text Objects

| Keys | Action |
|------|--------|
| `af` | Select around function |
| `if` | Select inside function |
| `ac` | Select around class |
| `ic` | Select inside class |
| `]m` / `[m` | Next/previous function start |
| `]M` / `[M` | Next/previous function end |

### Folding and Indentation

Buffers with a treesitter parser fold on the syntax tree (functions, classes, blocks), and files open with every fold open. Use Neovim's fold keys: `za` toggles the fold under the cursor, `zc`/`zo` close/open it, `zM`/`zR` close/open all. Big files get neither (see Big Files below).

Rust and C++ are indented with nvim-treesitter's indentation (which the plugin calls experimental). Every other language keeps Neovim's runtime indent script, which did as well or better in a comparison (Java, C, Lua, Python), or is the only option (Kotlin). The list is `treesitter_indent` in `lua/plugins/parser.lua`.

### Git (gitsigns)

[gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim) shows added, changed and deleted lines in the sign column. These maps are only set in buffers for files in a git repository.

| Keys | Action |
|------|--------|
| `]c` / `[c` | Next/previous hunk (in diff mode: next/previous change) |
| `<leader>hs` | Stage hunk, or unstage it if it is already staged (visual: stage selected lines) |
| `<leader>hr` | Reset hunk (visual: reset selected lines) |
| `<leader>hS` | Stage buffer |
| `<leader>hR` | Reset buffer |
| `<leader>hp` | Preview hunk in a float |
| `<leader>hi` | Preview hunk inline (shows the deleted lines) |
| `<leader>hb` | Blame current line |
| `<leader>hd` | Diff the file against the index |
| `<leader>hD` | Diff the file against the last commit |
| `<leader>hq` | All hunks in the repository to the quickfix list |
| `<leader>ub` | Toggle blame on the current line |
| `<leader>uw` | Toggle word diff |
| `ih` | Select hunk (text object, e.g. `dih`, `vih`) |

### lazygit

[lazygit](https://github.com/jesseduffield/lazygit) opens in a floating terminal through [snacks.nvim](https://github.com/folke/snacks.nvim/blob/main/docs/lazygit.md), with colours from the current colorscheme. Editing a file from lazygit (`e`) opens it in this Neovim, not a nested one. bootstrap.sh installs lazygit: with Homebrew or pacman where they are used, and elsewhere (Debian/Ubuntu, Fedora) as the release build pinned in `LAZYGIT_VERSION`, in `~/.local/bin`.

| Keys | Action |
|------|--------|
| `<leader>gg` | Open lazygit |
| `<leader>gf` | lazygit with the history of the current file |

## Big Files

[snacks.bigfile](https://github.com/folke/snacks.nvim/blob/main/docs/bigfile.md) gives files over 1.5 MB, or with an average line longer than 1000 characters (minified JavaScript or JSON), the `bigfile` filetype instead of their own. That keeps language servers, treesitter highlighting and folding, syntax highlighting, filetype plugins and completion off for them, and matchparen gives up after 1 ms in that buffer. A warning names the file and the filetype it would have had. To work on such a file with everything on anyway, run `:set filetype=<its filetype>`.

Files opened through a symlinked directory (on macOS that includes `/tmp` and `/var`) aren't checked, because snacks only checks a file when the path it is given matches the buffer name, and buffer names resolve symlinks.

## AI Integration

Setup for working alongside AI coding agents such as Claude Code (no inline completion).

Files changed on disk by an agent are reloaded automatically (`autoread` plus `:checktime` on focus, buffer enter, cursor hold and leaving/closing a terminal), with a notification when a buffer is reloaded. Buffers with unsaved changes are not overwritten; Neovim asks first.

`<leader>yr` copies a code reference to the system clipboard for pasting into a prompt: `path:LINE` in normal mode, `path:START-END` for a visual selection. The path is relative to the cwd (or the git root if the file is outside the cwd).

[claudecode.nvim](https://github.com/coder/claudecode.nvim) connects Neovim to Claude Code: Claude sees your current selection and diagnostics and shows proposed edits as diffs in Neovim. It needs the `claude` CLI on your `PATH` and starts right after Neovim does, so a Claude Code session in another terminal can attach with `/ide`.

| Keys | Action |
|------|--------|
| `<leader>yr` | Copy `path:line` reference (visual: `path:start-end`) |
| `<leader>ac` | Toggle Claude terminal |
| `<leader>af` | Focus Claude terminal |
| `<leader>ar` | Resume a previous Claude session |
| `<leader>aC` | Continue the last Claude session |
| `<leader>am` | Select Claude model |
| `<leader>ab` | Add current buffer to Claude's context |
| `<leader>as` | Send visual selection to Claude (in nvim-tree: add file) |
| `<leader>aa` | Accept proposed diff (or `:w` in the diff) |
| `<leader>ad` | Deny proposed diff (or `:q` in the diff) |

## Updating Plugins

Plugins are installed at the commits in `lazy-lock.json`, and lazy.nvim doesn't check for updates in the background. Updating is a deliberate step:

```bash
make update    # update plugins, run the tests, show the lazy-lock.json diff
make restore   # put plugins back at the commits in lazy-lock.json
```

`make update` refuses to start if `lazy-lock.json` has uncommitted changes, so the diff it prints shows only the update. It runs `:Lazy! update`, updates the treesitter parsers to match, runs `tests/run.sh` against the result and prints `git diff lazy-lock.json`. It doesn't commit anything: if the tests pass, review the diff and commit `lazy-lock.json`. If they fail, fix the config, or go back with `git checkout -- lazy-lock.json && make restore`.

nvim-treesitter's entry in `lazy-lock.json` stays at the 0.11 pin (see "Neovim 0.12 and nvim-treesitter" above), so updating on 0.12 doesn't break restores on 0.11. On 0.12 both commands move the installed nvim-treesitter to main and leave its lockfile entry alone, so after `make restore` there's no need to run `:Lazy update nvim-treesitter` by hand.

Both commands use the config `NVIM_APPNAME` points at, which must be this checkout, and `NVIM` picks the Neovim binary (default `nvim`). `make update` also passes `TEST_SKIP` and the other `tests/run.sh` options through. Mason packages aren't in `lazy-lock.json` and aren't updated; update them from `:Mason` (`U`).

In lazy.nvim's window (`:Lazy`), `R` (restore) also returns plugins to `lazy-lock.json`, while `U` (update) and `S` (sync) move them to newer commits and rewrite `lazy-lock.json` without running the tests. Prefer `make update` for that.

## Useful Commands

| Command | Description |
|---------|-------------|
| `:Lazy` | Open plugin manager |
| `:Mason` | Open LSP/formatter installer |
| `:checkhealth vim.lsp` | Check LSP status (on 0.11, `:LspInfo` also works) |
| `:lsp restart` | Restart the language servers attached to the current buffer (`:LspRestart` on 0.11) |
| `:lua vim.cmd.tabnew(vim.lsp.log.get_filename())` | View the LSP log (on 0.11, `:LspLog` also works) |
| `:LspClients` | List active LSP clients and their root directories |
| `:KotlinFormat` | Format Kotlin file with ktfmt (no LSP fallback) |
| `:JavaFormat` | Format Java file with google-java-format (no LSP fallback) |
| `:CleanupLSPCache` | Clean LSP caches (requires restart) |
| `:CleanupLSPLogs` | Clean log files |
| `:checkhealth` | Diagnose nvim setup issues |

## Folder Structure

- `init.lua` is the entry point. It loads the core modules and trims the LSP log on startup.
- `lua/core/` holds editor setup that is not a plugin: options, keymaps, user commands (`:CleanupLSPCache`, `:CleanupLSPLogs`, `:LspClients`), the lazy.nvim bootstrap, shared helpers, and central path definitions.
- `lua/plugins/` holds lazy.nvim plugin specs, grouped by area. lazy.nvim imports every file in this directory.
- `tests/` holds the test suite (see Development below).
- `scripts/plugins.sh` runs `make update` and `make restore` (see Updating Plugins above).
- `bootstrap.sh` installs dependencies on a new machine.

## Development

Run the whole test suite with:

```bash
tests/run.sh
```

It runs `tests/bootstrap_test.sh`, every `tests/*_test.lua` in a fresh headless Neovim, and a startup smoke test that opens sample files and fails on errors in `:messages`. It exits non-zero if anything fails. `TEST_SKIP` skips tests by name, and the header of `tests/run.sh` lists the other options. CI runs the same script on every push and pull request, on Neovim 0.11 and 0.12.

`make lint` runs [selene](https://github.com/Kampfkarren/selene) over the Lua files, with the `vim` global declared in `vim.yml`, [ShellCheck](https://github.com/koalaman/shellcheck) over the tracked `*.sh` files (`bootstrap.sh`, `scripts/plugins.sh` and the shell scripts in `tests/`), and lua-language-server's type check, configured in `.luarc.lint.json`. ShellCheck runs at its default severity, so info-level notes fail too; silence a false positive with a `# shellcheck disable=SCxxxx` comment on the narrowest scope, with a reason. CI runs `make lint` too.

In the editor, lua_ls knows the Neovim API and every installed plugin's modules in this config, in other Neovim configs (a `lua/` directory next to an `init.lua`), and in plugin checkouts (`lua/` next to `plugin/`, or anything under lazy.nvim's plugin directory): hover, go to definition and type checks work for `vim.*` and for `require("conform")` and the like. It gets that library when it starts, which makes its first indexing take a few seconds longer (about 6 s instead of 1.5 s here). Other Lua projects get plain lua_ls settings. The lint config is not named `.luarc.json`, because lua_ls would read that file in the editor too, and its `workspace.library` would replace this library. lazydev.nvim isn't used: lua_ls ignores the library changes it sends after the server has started.

Lua is formatted with [StyLua](https://github.com/JohnnyMorganz/StyLua), configured in `stylua.toml` (2-space indentation, double quotes, 120 columns). `make lint` starts with `stylua --check` over `init.lua`, `lua/`, `tests/` and `.github/scripts/` and fails on any file that isn't formatted; `make format` rewrites them in place. CI pins StyLua (`STYLUA_VERSION` in `.github/workflows/test.yml`), and other releases can format some code differently, so use the same version locally.

Inside Neovim, saving a Lua file formats it with StyLua when a `stylua.toml` or `.stylua.toml` is found in its directory or a parent, as in this repo. Lua files in projects without one are not formatted on save (`<leader>cf` still formats them with lua_ls). Mason installs StyLua at the version in `vim.g.mason_tool_versions` (`lua/plugins/language-server.lua`), which must match `STYLUA_VERSION`; tests/format_test.lua fails if they differ. Mason's copy is only on PATH inside Neovim, so `make lint` and `make format` still need `stylua` on your shell's PATH (or run them with `PATH=~/.local/share/nvim/mason/bin:$PATH`).

The commit that first formatted the repo with StyLua is listed in `.git-blame-ignore-revs`, so blame shows who last really changed a line. GitHub's blame view uses the file automatically; for local `git blame`, run `git config blame.ignoreRevsFile .git-blame-ignore-revs` once.

To test changes without touching your live config, check them out in a separate directory under `~/.config` and point Neovim at it with `NVIM_APPNAME`, which also gives it its own plugin and data directories:

```bash
git worktree add ~/.config/nvim-dev -b my-change
cd ~/.config/nvim-dev
NVIM_APPNAME=nvim-dev nvim             # try it interactively
NVIM_APPNAME=nvim-dev tests/run.sh     # run the tests against it
```

`tests/run.sh` refuses to run if Neovim would load a config other than the checkout it lives in.

## Troubleshooting

### LSP not attaching

```vim
:checkhealth vim.lsp      " Check status
:lua vim.cmd.tabnew(vim.lsp.log.get_filename())   " View errors
:lsp restart              " Restart the server
```

`:lsp restart` is new in Neovim 0.12; on 0.11 use `:LspRestart`. nvim-lspconfig defines `:LspInfo`, `:LspLog` and `:LspRestart` only on 0.11, and leaves them out on 0.12 in favour of the builtin `:lsp` command. The first two commands above work on both.

### Kotlin LSP issues

If kotlin-lsp quits right after it starts, check `:LspLog` for "This build of kotlin-server has expired". JetBrains' kotlin-lsp builds stop working after a date, so update it with `:MasonInstall kotlin-lsp` (or `U` on it in `:Mason`).

Quitting Neovim waits up to 5 s for kotlin-lsp and jdtls to exit (2 s for lua_ls) and then stops them, so a server busy importing a project doesn't keep running after Neovim is gone.

```bash
# Kill stuck processes
pkill -9 -f kotlin-lsp

# Clear cache
:CleanupLSPCache
# Then restart Neovim
```

### High memory usage

1. Run `:CleanupLSPCache` and restart
2. Check which LSP is consuming memory with Activity Monitor / htop
3. Memory limits are configured in `lua/plugins/language-server.lua`
