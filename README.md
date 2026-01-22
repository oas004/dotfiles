# Neovim Configuration

A modern Neovim configuration written in Lua with a focus on development, LSP support, and mobile development tooling.

## Features

- **Plugin Management**: lazy.nvim for fast, lazy-loading plugins
- **LSP Support**: Kotlin, Clang, Haskell, and more via mason.nvim
- **Autoformatting**: conform.nvim with support for multiple formatters
- **Android Development**: Custom ADB integration for device management and app installation
- **Fuzzy Finding**: Telescope.nvim with ripgrep backend
- **Git Integration**: Git blame with gutter display and custom git status commands
- **Theme**: Nordic colorscheme with optimized UI

## Installation

### Prerequisites

- [Neovim 0.9+](https://neovim.io/) (recommended: latest stable)
- [Git](https://git-scm.com/) (for cloning and LSP servers)
- `ripgrep` (for telescope fuzzy finder)
  ```bash
  # macOS
  brew install ripgrep

  # Ubuntu/Debian
  sudo apt-get install ripgrep

  # Arch
  sudo pacman -S ripgrep
  ```

### Setup

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

4. **Install LSP servers and tools** (optional, but recommended):
   ```
   :Mason
   ```
   Mason provides a UI to install language servers, formatters, linters, and DAP servers.

### Optional Dependencies

For full functionality, consider installing:

- **Android Development**: `adb` (Android SDK Platform Tools)
  ```bash
  # macOS
  brew install android-platform-tools

  # Ubuntu/Debian
  sudo apt-get install android-tools-adb
  ```

- **Kotlin Development**: Install Kotlin LSP via Mason (`:Mason`)
- **Language Servers**: Use Mason to install servers for your languages

## Useful Commands

1. **`:Lazy`**: Open the plugin manager interface
   - View installed plugins
   - Check for updates
   - Profile plugin load times

2. **`:Mason`**: Open the LSP/DAP/formatter/linter installer
   - Install language servers
   - Manage formatter and linter versions

3. **`:KotlinLspList`**: List available Kotlin language servers
4. **`:KotlinLspSwitch`**: Switch between Kotlin language servers
5. **`:KotlinFormatterList`**: List available Kotlin formatters
6. **`:KotlinFormatterSwitch`**: Switch between Kotlin formatters
7. **`:CustomGitStatus`**: Show git status in a split
8. **`:CustomAdbDevices`**: List connected Android devices
9. **`:AdbPickInstall`**: Pick an APK to install on a connected device
10. **`:AdbLogcat`**: Stream logcat output in a split

## Keybindings

### Leader Key

The leader key is set to `<Space>`.

### General Navigation
- `Y` - Yank to end of line (y$)
- `j` / `k` - Navigate by visual lines (wrap-aware)
- `<Esc>` - Clear search highlighting
- `<C-s>` - Save file (works in normal, insert, and visual modes)

### Diagnostics & LSP
- `gl` - Show line diagnostics in floating window
- `]d` - Jump to next diagnostic
- `[d` - Jump to previous diagnostic
- `gd` - Go to definition
- `gD` - Go to declaration
- `gI` - Go to implementation
- `gy` - Go to type definition
- `gr` - Show references/usages
- `<Leader>ca` - Code actions (e.g., implement interface members)

### Search & Navigation (Leader + key)
- `<Leader>f` - Fuzzy search in file content (live grep)
- `<Leader>p` - Find files
- `<Leader>o` - Search open buffers
- `<Leader>l` - Toggle file explorer
- `<Leader>q` - Delete buffer (in telescope)

### Git (Leader + key)
- `<Leader>gb` - Toggle git blame on current line (virtual text)
- `<Leader>gB` - Show git blame for current line in popup
- `<Leader>g?` - Show full buffer git blame
- `<Leader>gs` - Git status (short format)
- `<Leader>gS` - Git status (full format)

### Android/ADB (Leader + a + key)

#### Device & Installation
- `<Leader>ad` - Pick and set device
- `<Leader>ai` - Pick APK and install on device
- `<Leader>aI` - Pick APK and install on device (allow downgrade)

#### Logcat & Debugging
- `<Leader>al` - Stream all logcat (Info level and above)
- `<Leader>aL` - Stream app-specific logcat (verbose, with PID filter, clears first)
- `<Leader>aG` - Grab foreground app package (auto-detects running app)
- `<Leader>aw` - Open log bookmarks menu (select: Crashes, Network, Database, UI, or App logs)
- `<Leader>as` - Search logcat by regex pattern (normal mode)
- `<Leader>aS` - Search logcat by regex pattern (clear first)
- `<Leader>as` (visual) - Use selected text as regex seed (auto-escaped)

#### Log Bookmarks (`<Leader>aw`)
Press `<Leader>aw` to open a menu with pre-configured log filters:
- **Crashes** - `AndroidRuntime.*FATAL|Exception`
- **Network** - `HttpConnection|OkHttp|Retrofit|Socket`
- **Database** - `SQLite|Room|Database|cursor`
- **UI/Layout** - `ViewGroup|LayoutInflater|View|draw`
- **App logs** - Filter by your app package (set via `<Leader>aG`)

#### Recommended Workflow
1. Launch your Android app on a connected device
2. Press `<Leader>aG` to auto-detect and store your app's package name
3. Press `<Leader>aw` and select a bookmark (e.g., "Crashes" or "App logs")
4. Logs appear in a terminal split with verbose output and threadtime format
5. Press `q` to close the logcat window

## Folder structure

### [lua/config/keymaps.lua](lua/config/keymaps.lua)
- Define your custom keymaps here using the [vim.keymap](https://neovim.io/doc/user/lua.html#vim.keymap) module.
- Since the keymaps are binded after the plugins are loaded, then it can use functions exported by plugins.

### [lua/config/options.lua](lua/config/options.lua)
- Define your custom neovim options here using [vim.opt](https://neovim.io/doc/user/lua.html#vim.opt).

### [lua/config/package-manager.lua](lua/config/package-manager.lua)
- Out of the box configuration for the package manager.

### [lua/plugins/*.lua](lua/plugins/)
- Plugin directory which contains the plugins to download, with the plugin's configurations.
- Each module in the directory should return a Lua table that contains the plugin/s to download using `lazy.nvim`.
  See [lazy.nvim startup sequence](https://github.com/folke/lazy.nvim?tab=readme-ov-file#%EF%B8%8F-startup-sequence)
