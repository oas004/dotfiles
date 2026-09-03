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

- **LSP**: `kotlin-lsp` (JetBrains official) at `~/.local/opt/kotlin-lsp/kotlin-lsp.sh`
- **Formatter**: `ktfmt` (Google's formatter, removes unused imports)

## Commands

```vim
" Check LSP status
:LspInfo

" View LSP logs
:LspLog

" Manual format current file
:KotlinFormat

" Check conform.nvim status
:ConformInfo
```

## Formatting

ktfmt is used for all Kotlin formatting:
- Removes unused imports automatically
- Consistent Android Studio style formatting
- Opinionated (minimal configuration options)

### Format on Save

Format on save is enabled by default via `conform.nvim`.

### Manual Formatting

```vim
:KotlinFormat
```

## Troubleshooting

### kotlin-lsp not found
Make sure it's installed at `~/.local/opt/kotlin-lsp/kotlin-lsp.sh`. Download from:
https://github.com/Kotlin/kotlin-lsp/releases

### LSP not attaching
```vim
:LspInfo                  " Check LSP status
:LspLog                   " View detailed logs
```

If LSP is stuck, kill all processes and restart Neovim:
```bash
pkill -9 -f kotlin-lsp
```

### Formatting not working
```vim
:ConformInfo             " Check conform.nvim status
:KotlinFormat            " Try manual format
```

### Go-to-definition not working

kotlin-lsp (JetBrains) is still in pre-alpha and may have issues with:
- Dependency resolution
- Android-specific libraries
- Multi-module Gradle projects

**Workaround**: Open the project in Android Studio first, let it complete Gradle sync, then use Neovim. The LSP can leverage Android Studio's caches.

## Known Limitations

- **kotlin-lsp is pre-alpha**: Expect bugs and missing features
- **Go-to-definition**: Works better for pure Kotlin/JVM projects than Android projects
- **Indexing**: Can take 5-15 minutes for large projects on first open
- **Android libraries**: May not resolve correctly (androidx.*, com.google.android.*)
