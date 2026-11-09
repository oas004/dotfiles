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

- [Neovim 0.11+](https://neovim.io/) (recommended: latest stable)
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

# Install kotlin-lsp into ~/.local/opt/kotlin-lsp
INSTALL_KOTLIN=1 ~/.config/nvim/bootstrap.sh
```

To install kotlin-lsp by hand, download the standalone archive for your platform from the [kotlin-lsp releases page](https://github.com/Kotlin/kotlin-lsp/releases) and extract it so that `~/.local/opt/kotlin-lsp/kotlin-lsp.sh` exists. The macOS `.sit` file is a zip archive.

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

### Treesitter Text Objects

| Keys | Action |
|------|--------|
| `af` | Select around function |
| `if` | Select inside function |
| `]m` / `[m` | Next/previous function start |
| `]M` / `[M` | Next/previous function end |

## Useful Commands

| Command | Description |
|---------|-------------|
| `:Lazy` | Open plugin manager |
| `:Mason` | Open LSP/formatter installer |
| `:LspInfo` | Check LSP status |
| `:LspLog` | View LSP logs |
| `:KotlinFormat` | Format Kotlin file with ktfmt (no LSP fallback) |
| `:JavaFormat` | Format Java file with google-java-format (no LSP fallback) |
| `:CleanupLSPCache` | Clean LSP caches (requires restart) |
| `:CleanupLSPLogs` | Clean log files |
| `:checkhealth` | Diagnose nvim setup issues |

## Folder Structure

- `init.lua` is the entry point. It loads the core modules and defines a few LSP maintenance commands.
- `lua/core/` holds editor setup that is not a plugin: options, keymaps, the lazy.nvim bootstrap, shared helpers, and central path definitions.
- `lua/plugins/` holds lazy.nvim plugin specs, grouped by area. lazy.nvim imports every file in this directory.
- `tests/` holds the test suite (see Development below).
- `bootstrap.sh` installs dependencies on a new machine.

## Development

Run the whole test suite with:

```bash
tests/run.sh
```

It runs `tests/bootstrap_test.sh`, every `tests/*_test.lua` in a fresh headless Neovim, and a startup smoke test that opens sample files and fails on errors in `:messages`. It exits non-zero if anything fails. `TEST_SKIP` skips tests by name, and the header of `tests/run.sh` lists the other options. CI runs the same script on every push and pull request.

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
