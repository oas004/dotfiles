# Neovim Configuration

A modern Neovim configuration written in Lua with LSP support for Kotlin/Android, Rust/WebAssembly, and more.

## Features

- **Plugin Management**: lazy.nvim for fast, lazy-loading plugins
- **LSP Support**: Kotlin, Rust, Java, Clang, Haskell, and more via mason.nvim
- **WebAssembly**: WIT syntax highlighting, wasm-tools integration
- **Autoformatting**: conform.nvim with ktfmt for Kotlin, rustfmt for Rust
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

The bootstrap script installs all dependencies including Neovim, Rust toolchain, wasm-tools, and syncs plugins.

### Manual Setup

#### Prerequisites

- [Neovim 0.9+](https://neovim.io/) (recommended: latest stable)
- [Git](https://git-scm.com/)
- [Rust](https://rustup.rs/) (for rust-analyzer and wasm tools)
- `ripgrep` (for telescope fuzzy finder)

#### macOS
```bash
brew install neovim ripgrep
```

#### Ubuntu/Debian
```bash
sudo apt install neovim ripgrep
```

#### Fedora
```bash
sudo dnf install neovim ripgrep
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

4. **Install LSP servers and tools**:
   ```
   :Mason
   ```

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

For Kotlin support, install the JetBrains official kotlin-lsp:

```bash
# Install ktfmt (formatter)
brew install ktfmt

# Install kotlin-lsp
curl -L https://github.com/Kotlin/kotlin-lsp/releases/latest/download/kotlin-lsp.zip -o /tmp/kotlin-lsp.zip
unzip /tmp/kotlin-lsp.zip -d ~/.local/opt/
chmod +x ~/.local/opt/kotlin-lsp/kotlin-lsp.sh
```

See [KOTLIN_SETUP.md](KOTLIN_SETUP.md) for more details.

## Keybindings

### Leader Key

The leader key is `<Space>`.

### LSP Navigation

| Keys | Action |
|------|--------|
| `gd` | Go to definition |
| `gD` | Go to declaration |
| `gI` | Go to implementation |
| `gr` | Find references/usages |
| `gy` | Go to type definition |
| `K` | Show hover documentation |

### Diagnostics

| Keys | Action |
|------|--------|
| `gl` | Show line diagnostics (error popup) |
| `<leader>e` | Next diagnostic |
| `<leader>E` | Previous diagnostic |

### Code Actions & Refactoring

| Keys | Action |
|------|--------|
| `<leader>ca` | Code actions (quick fixes) |
| `<S-F6>` | Rename symbol |
| `<leader>fm` | Format buffer |

### File Navigation (Telescope)

| Keys | Action |
|------|--------|
| `<leader>p` | Find files |
| `<leader>f` | Find in files (grep) |
| `<leader>o` | Open buffers |
| `<leader>s` | Document symbols (outline of current file) |
| `<leader>S` | Workspace symbols (search across project) |
| `<leader>r` | Recent files |

### File Explorer

| Keys | Action |
|------|--------|
| `<leader>l` | Toggle file explorer |
| `<leader>lf` | Reveal current file in explorer |

### General

| Keys | Action |
|------|--------|
| `Y` | Yank to end of line |
| `j` / `k` | Navigate by visual lines (wrap-aware) |
| `<Esc>` | Clear search highlighting |
| `<C-s>` | Save file |
| `jj` or `jk` | Exit insert mode |
| `<C-o>` | Jump back (after go to definition) |
| `<C-i>` | Jump forward |
| `]m` / `[m` | Jump to next/previous function |

### Treesitter Text Objects

| Keys | Action |
|------|--------|
| `af` | Select around function |
| `if` | Select inside function |
| `]m` / `[m` | Next/previous function start |
| `]M` / `[M` | Next/previous function end |

## AI Integration

Setup for working alongside AI coding agents such as Claude Code (no inline completion).

Files changed on disk by an agent are reloaded automatically (`autoread` plus `:checktime` on focus, buffer enter, cursor hold and leaving/closing a terminal), with a notification when a buffer is reloaded. Buffers with unsaved changes are not overwritten; Neovim asks first.

`<leader>yr` copies a code reference to the system clipboard for pasting into a prompt: `path:LINE` in normal mode, `path:START-END` for a visual selection. The path is relative to the cwd (or the git root if the file is outside the cwd).

[claudecode.nvim](https://github.com/coder/claudecode.nvim) connects Neovim to Claude Code: Claude sees your current selection and diagnostics and shows proposed edits as diffs in Neovim. It needs the `claude` CLI on your `PATH` and loads on first use of a key or `:ClaudeCode*` command below. To attach a Claude Code session started in another terminal, run `:ClaudeCodeStart` first, then `/ide` in Claude.

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
| `:LspInfo` | Check LSP status |
| `:LspLog` | View LSP logs |
| `:KotlinFormat` | Manually format Kotlin file |
| `:CleanupLSPCache` | Clean LSP caches (requires restart) |
| `:CleanupLSPLogs` | Clean log files |
| `:checkhealth` | Diagnose nvim setup issues |

## Folder Structure

```
~/.config/nvim/
├── init.lua                 # Entry point
├── lua/
│   ├── core/
│   │   ├── keymaps.lua      # Key bindings
│   │   ├── options.lua      # Neovim options
│   │   ├── paths.lua        # Path configuration
│   │   └── utils.lua        # Helper functions
│   └── plugins/
│       ├── language-server.lua  # LSP configuration
│       ├── kotlin-formatter.lua # ktfmt setup
│       ├── fuzzy-finder.lua     # Telescope
│       ├── file-explorer.lua    # nvim-tree
│       ├── parser.lua           # Treesitter
│       └── theming.lua          # Colorscheme
```

## Troubleshooting

### LSP not attaching

```vim
:LspInfo                  " Check status
:LspLog                   " View errors
```

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
