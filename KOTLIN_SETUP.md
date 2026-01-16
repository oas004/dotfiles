# Kotlin Development Setup

This configuration provides easy switching between different Kotlin LSP implementations and formatters, plus Android Studio-style formatting.

## Quick Start

### 1. Install Required Tools

```bash
# Install ktfmt (primary formatter - removes unused imports, Android Studio style)
brew install ktfmt

# (Optional) Install ktlint for linting
brew install ktlint

# Ensure your Kotlin LSP is installed via Mason
# In neovim: :Mason
```

### 2. Current Configuration

The configuration uses:
- **LSP**: `kotlin_language_server` (community edition) - default
- **Formatter**: `ktfmt` (Google's formatter, removes unused imports)

## Switching Between LSP Implementations

### Available Kotlin LSP Servers

1. **kotlin_language_server** (recommended - default)
   - Community-maintained, feature-rich
   - Installed via Mason
   - Per-project H2 database to avoid locks
   - Good IntelliJ integration

2. **kotlin-lsp** (official JetBrains - pre-alpha)
   - Official implementation
   - Early stage, may have fewer features
   - Requires Java 17+
   - Manual installation from releases

### Commands

```vim
" List available Kotlin LSP servers
:KotlinLspList

" Switch to official Kotlin LSP
:KotlinLspSwitch kotlin-lsp

" Switch back to community version
:KotlinLspSwitch kotlin_language_server
```

**Note**: After switching LSP servers, restart Neovim for changes to take effect.

## Switching Between Formatters

### Available Formatters

1. **ktfmt** (recommended - default)
   - Google's Kotlin formatter
   - Removes unused imports automatically
   - Consistent Android Studio style formatting
   - Opinionated (minimal configuration options)

2. **ktlint** (alternative)
   - Kotlin linter with auto-fixer
   - More configuration options
   - Does not remove unused imports by default

### Commands

```vim
" List available formatters
:KotlinFormatterList

" Switch to ktlint
:KotlinFormatterSwitch ktlint

" Switch back to ktfmt
:KotlinFormatterSwitch ktfmt

" Manual format current file
:KotlinFormat
```

## Formatting Behavior

### Format on Save

Format on save is enabled by default when using `conform.nvim`. This happens automatically for Kotlin files.

### Manual Formatting

```vim
" Format current file
:KotlinFormat

" Or use conform's built-in
:ConformFormat
```

### Import Organization

- **ktfmt**: Automatically removes unused imports and organizes them
- **ktlint**: Does not remove unused imports by default

If you were using the Kotlin LSP's auto-import feature previously:
- ktfmt replaces this by cleaning up imports during formatting
- More aggressive than just organizing - it removes truly unused imports

## Configuration Details

### LSP Configuration (lua/config/kotlin-config.lua)

The Kotlin config module handles:
- Available LSP servers and their capabilities
- Available formatters and their commands
- User preference storage (`vim.g.kotlin_lsp`, `vim.g.kotlin_formatter`)
- Helper functions for other plugins

### Formatter Plugin (lua/plugins/kotlin-formatter.lua)

Uses `conform.nvim` (modern null-ls replacement) to provide:
- Format on save
- Manual formatting command
- LSP fallback formatting

### LSP Plugin (lua/plugins/language-server.lua)

Integrates with:
- lsp-zero for LSP setup
- Mason for package management
- Kotlin config module for LSP selection

## Troubleshooting

### ktfmt not found
```bash
brew install ktfmt
# Or install via Mason: :MasonInstall ktfmt
```

### LSP not starting
```vim
:LspInfo                  " Check LSP status
:Mason                    " Install language servers
:KotlinLspList           " See current Kotlin LSP config
```

### Formatting not working
```vim
:ConformInfo             " Check conform.nvim status
:KotlinFormat            " Try manual format
:KotlinFormatterList     " Check current formatter
```

### Switch to Kotlin LSP (official)

1. Download from: https://github.com/Kotlin/kotlin-lsp/releases
2. Make executable and add to PATH:
   ```bash
   chmod +x kotlin-lsp.sh
   sudo mv kotlin-lsp.sh /usr/local/bin/kotlin-lsp
   ```
3. In Neovim:
   ```vim
   :KotlinLspSwitch kotlin-lsp
   " Then restart Neovim
   ```

## Next Steps

- Customize formatter options in `lua/plugins/kotlin-formatter.lua`
- Add LSP keybindings if desired (already enabled via lsp-zero)
- Add project-specific Gradle options in `.gradle` directory
- Use `:KotlinLspList` and `:KotlinFormatterList` to explore options
