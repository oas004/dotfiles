# Kotlin Development Setup

This configuration uses the **official JetBrains kotlin-lsp** for language server features and **ktfmt** for formatting.

## Quick Start

### 1. Install Required Tools

```bash
# Install ktfmt (formatter - removes unused imports, Android Studio style)
brew install ktfmt

# Install kotlin-lsp (JetBrains official LSP)
# Download from: https://github.com/Kotlin/kotlin-lsp/releases
curl -L https://github.com/Kotlin/kotlin-lsp/releases/latest/download/kotlin-lsp.zip -o /tmp/kotlin-lsp.zip
unzip /tmp/kotlin-lsp.zip -d ~/.local/opt/
chmod +x ~/.local/opt/kotlin-lsp/kotlin-lsp.sh
```

### 2. Current Configuration

The configuration uses:
- **LSP**: `kotlin-lsp` (JetBrains official)
- **Formatter**: `ktfmt` (Google's formatter, removes unused imports)

## LSP Commands

### Diagnostics

```vim
" Check if LSP is attached and show project info
:KotlinLspDiagnostics

" Kill all kotlin-lsp processes (useful if stuck)
:KotlinLspKill

" Check LSP status
:LspInfo

" View LSP logs
:LspLog
```

## Formatting

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

### LSP Configuration (lua/core/kotlin-config.lua)

The Kotlin config module handles:
- Formatter selection and commands
- User preference storage for formatter
- Helper functions for other plugins
- LSP diagnostic commands

### Formatter Plugin (lua/plugins/kotlin-formatter.lua)

Uses `conform.nvim` to provide:
- Format on save
- Manual formatting command
- ktfmt integration

### LSP Plugin (lua/plugins/language-server.lua)

Configures:
- kotlin-lsp (JetBrains official) with stdio mode
- Mason for other language servers (Java, Gradle, etc.)
- Per-filetype LSP setup

## Troubleshooting

### kotlin-lsp not found
Make sure it's installed at `~/.local/opt/kotlin-lsp/kotlin-lsp.sh`. Download from:
https://github.com/Kotlin/kotlin-lsp/releases

### LSP not attaching
```vim
:LspInfo                  " Check LSP status
:KotlinLspDiagnostics    " Check kotlin-lsp specifically
:LspLog                  " View detailed logs
```

If LSP is stuck:
```vim
:KotlinLspKill           " Kill all kotlin-lsp processes
" Then restart Neovim
```

### Formatting not working
```vim
:ConformInfo             " Check conform.nvim status
:KotlinFormat            " Try manual format
:KotlinFormatterList     " Check current formatter (should be ktfmt)
```

### Go-to-definition not working

kotlin-lsp (JetBrains) is still in pre-alpha and may have issues with:
- Dependency resolution
- Android-specific libraries
- Multi-module Gradle projects

**Workaround**: Open the project in Android Studio first, let it complete Gradle sync, then use Neovim. The LSP can leverage Android Studio's caches.

### LSP shows "Address already in use" error

This means another kotlin-lsp instance is running. Kill all instances:
```vim
:KotlinLspKill
```
Then restart Neovim.

## Known Limitations

- **kotlin-lsp is pre-alpha**: Expect bugs and missing features
- **Go-to-definition**: Works better for pure Kotlin/JVM projects than Android projects
- **Indexing**: Can take 5-15 minutes for large projects on first open
- **Android libraries**: May not resolve correctly (androidx.*, com.google.android.*)

## Next Steps

- Customize formatter options in `lua/plugins/kotlin-formatter.lua`
- Add LSP keybindings if desired (already enabled via lsp-zero)
- Use `:KotlinFormatterList` to see formatter options
- Check `:LspLog` if you encounter issues
