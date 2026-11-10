# Neovim Configuration

A modern Neovim configuration written in Lua with LSP support for Kotlin/Android, Rust/WebAssembly, and more.

## Features

- **Plugin Management**: lazy.nvim for fast, lazy-loading plugins
- **LSP Support**: Rust (rust-analyzer from rustup), and Kotlin (JetBrains kotlin-lsp), Java, C/C++, Haskell, Python, Lua and Gradle via mason.nvim
- **WebAssembly**: treesitter highlighting for WIT files; bootstrap.sh installs the wasm-tools CLI and the wasm32 Rust targets
- **Autoformatting**: conform.nvim with ktfmt for Kotlin, google-java-format for Java (both installed by Mason), rustfmt for Rust
- **Fuzzy Finding**: Telescope.nvim with ripgrep backend
- **Theme**: Nordic colorscheme with optimized UI

## Installation

### Quick Start (Recommended)

```bash
# Clone the repository
git clone https://github.com/oas004/dotfiles.git ~/.config/nvim

# Run the bootstrap script (works on macOS and Linux)
~/.config/nvim/bootstrap.sh
```

The bootstrap script installs all dependencies including Neovim, the Rust toolchain (with the rust-analyzer and rustfmt components), wasm-tools, a JDK 21, python3 with venv, jq and the tools Mason needs, and syncs plugins. Plugins are installed at the versions in `lazy-lock.json` (`:Lazy! restore`), and the script fails if a plugin or treesitter parser can't be installed. It also fails if an existing Neovim is older than 0.11.

On Debian/Ubuntu, apt's `neovim` package is older than 0.11, so the script installs the official release build instead: it extracts `nvim-linux-x86_64.tar.gz` (or `nvim-linux-arm64.tar.gz`) from https://github.com/neovim/neovim/releases into `~/.local/opt/nvim` and symlinks `~/.local/bin/nvim` to it. Make sure `~/.local/bin` is on your PATH. Set `NVIM_RELEASE` to pick a release tag (default `stable`, e.g. `NVIM_RELEASE=v0.12.0`).

jdtls needs Java 21+ and uses `JAVA_HOME` if it is set, otherwise `java` on PATH; gradle_ls and ktfmt use `java` on PATH. If that is an older Java, the script installs JDK 21 (or, on macOS, finds one that is already installed) and prints the `JAVA_HOME` and `PATH` lines to add to your shell profile. Homebrew's `openjdk@21` is keg-only, so on macOS you need to set them either way.

The script does not install ghcup, which Mason uses to install haskell-language-server. It warns if ghcup is missing; to use Haskell, install ghcup and GHC with `curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh`.

The language servers (kotlin-lsp included) and the ktfmt and google-java-format formatters are installed by Mason, not by the script. Mason starts installing whatever is missing the first time you open Neovim; `:Mason` shows the progress. Mason's bin directory (`~/.local/share/nvim/mason/bin`) is put on PATH inside Neovim only, so these tools are not on your shell's PATH. ktfmt is a jar that Mason runs with `java -jar`, so it needs Java 17+ as `java` on PATH.

### Manual Setup

#### Prerequisites

- [Neovim 0.11+](https://neovim.io/) (recommended: 0.12+, which nvim-treesitter's main branch requires; on 0.11 the config pins an older main commit)
- [Git](https://git-scm.com/)
- [Rust](https://rustup.rs/) with the `rust-analyzer` and `rustfmt` components (`rustup component add rust-analyzer rustfmt`), plus the wasm tools
- `ripgrep` (for telescope fuzzy finder)
- [`tree-sitter` CLI](https://github.com/tree-sitter/tree-sitter/blob/master/crates/cli/README.md) 0.26.1+ (not the npm package), plus `curl`, `tar` and a C compiler, for installing treesitter parsers
- `unzip` and `gzip`, which Mason uses along with `curl`, `git` and `tar` to download and extract servers
- JDK 21+ for jdtls, gradle_ls and ktfmt, as `java` on PATH (and `JAVA_HOME`, if you set it)
- `python3` with the `venv` module (`python3-venv` on Debian/Ubuntu), for jedi-language-server and the jdtls launcher
- [ghcup](https://www.haskell.org/ghcup/) and GHC, for haskell-language-server (optional)
- `jq` (json formatter)

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

4. **Let Mason install the LSP servers and formatters** (kotlin-lsp, ktfmt and google-java-format included). This starts on its own; follow it with:
   ```
   :Mason
   ```

### Neovim 0.12 and nvim-treesitter

On Neovim 0.11, `lua/plugins/parser.lua` pins nvim-treesitter to the last main commit that supports 0.11, and on 0.12+ it follows main. `lazy-lock.json` can only record one commit, so it records the 0.11 one, and a first install or `:Lazy restore` (which bootstrap.sh runs) checks out that commit on 0.12 too. On Neovim 0.12+, run this after a restore:

```vim
:Lazy update nvim-treesitter
```

That moves nvim-treesitter to current main, so you get the parser and query fixes made since the pin. It also changes nvim-treesitter's entry in `lazy-lock.json`. Don't commit that change: a restore on 0.11 would then check out a commit that no longer supports 0.11.

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

The leader key is `<Space>`.

### which-key

[which-key.nvim](https://github.com/folke/which-key.nvim) shows a popup with the keys that can follow a prefix (`<leader>`, `g`, `z`, `]`, ...) when you pause after typing it. It loads right after startup. The `<leader>` groups are `a` (Claude), `c` (code), `h` (git hunks), `n` (new) and `y` (yank); a group only shows up when something is mapped under it. `<leader>?` lists the keymaps local to the current buffer, such as the LSP maps. `:checkhealth which-key` reports overlapping and duplicate mappings.

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

### Code Actions & Refactoring

| Keys | Action |
|------|--------|
| `<leader>ca` / `<F4>` | Code actions (quick fixes) |
| `<F2>` / `<S-F6>` | Rename symbol |
| `<leader>cf` | Format buffer |

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

### File Navigation (Telescope)

| Keys | Action |
|------|--------|
| `<leader>p` | Find files |
| `<leader>f` | Find in files (grep) |
| `<leader>o` | Open buffers |
| `<leader>s` | Document symbols (outline of current file) |
| `<leader>S` | Workspace symbols (search across project) |
| `<leader>r` | Recent files |

In the open buffers picker, `<leader>q` in normal mode (or `<M-d>` in insert mode) closes the selected buffer.

### File Explorer

| Keys | Action |
|------|--------|
| `<leader>l` | Toggle file explorer |
| `<leader>L` | Reveal current file in explorer |

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

### Treesitter Text Objects

| Keys | Action |
|------|--------|
| `af` | Select around function |
| `if` | Select inside function |
| `ac` | Select around class |
| `ic` | Select inside class |
| `]m` / `[m` | Next/previous function start |
| `]M` / `[M` | Next/previous function end |

### Git (gitsigns)

[gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim) shows added, changed and deleted lines in the sign column. These maps are only set in buffers for files in a git repository.

| Keys | Action |
|------|--------|
| `]c` / `[c` | Next/previous hunk (in diff mode: next/previous change) |
| `<leader>hs` | Stage hunk (visual: stage selected lines) |
| `<leader>hr` | Reset hunk (visual: reset selected lines) |
| `<leader>hp` | Preview hunk |
| `<leader>hb` | Blame current line |
| `ih` | Select hunk (text object, e.g. `dih`, `vih`) |

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
- `bootstrap.sh` installs dependencies on a new machine.

## Development

Run the whole test suite with:

```bash
tests/run.sh
```

It runs `tests/bootstrap_test.sh`, every `tests/*_test.lua` in a fresh headless Neovim, and a startup smoke test that opens sample files and fails on errors in `:messages`. It exits non-zero if anything fails. `TEST_SKIP` skips tests by name, and the header of `tests/run.sh` lists the other options. CI runs the same script on every push and pull request, on Neovim 0.11 and 0.12.

`make lint` runs [selene](https://github.com/Kampfkarren/selene) over the Lua files, with the `vim` global declared in `vim.yml`, [ShellCheck](https://github.com/koalaman/shellcheck) over the tracked `*.sh` files (`bootstrap.sh` and the shell scripts in `tests/`), and lua-language-server's type check. ShellCheck runs at its default severity, so info-level notes fail too; silence a false positive with a `# shellcheck disable=SCxxxx` comment on the narrowest scope, with a reason. CI runs `make lint` too.

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
