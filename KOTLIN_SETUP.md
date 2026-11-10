# Kotlin Development Setup

This configuration uses the **official JetBrains kotlin-lsp** for language server features and **ktfmt** for formatting.

## Quick Start

### 1. Install Required Tools

Mason installs both tools the first time you start Neovim, so there is nothing to install by hand. kotlin-lsp is in `ensure_installed` in `lua/plugins/language-server.lua`, and ktfmt is in `vim.g.mason_tools` next to it. Watch the progress, or install them yourself, with:

```vim
:Mason
:MasonInstall kotlin-lsp ktfmt
```

kotlin-lsp (~370 MB download) ships its own Java runtime. ktfmt is a jar that Mason runs with `java` from PATH, so it needs Java 17+ there (bootstrap.sh installs JDK 21 for jdtls).

If you used an older version of this config, kotlin-lsp was installed in `~/.local/opt/kotlin-lsp` and ktfmt with Homebrew. Neither is used any more: delete `~/.local/opt/kotlin-lsp`, and `brew uninstall ktfmt` if you don't need it outside Neovim.

### 2. Current Configuration

- **LSP**: `kotlin-lsp` (JetBrains official), Mason package `kotlin-lsp`. Mason links its launcher into `~/.local/share/nvim/mason/bin` as `intellij-server`, which the config runs with `--stdio` and a per-project `--system-path` under `~/.cache/nvim/kotlin-lsp`
- **Formatter**: `ktfmt` (removes unused imports), Mason package `ktfmt`, run with `--kotlinlang-style`

Mason puts its bin directory first on PATH inside Neovim only, so `intellij-server` and `ktfmt` are not on your shell's PATH.

## Commands

```vim
" Check LSP status (on Neovim 0.11, :LspInfo also works)
:checkhealth vim.lsp

" View LSP logs (on Neovim 0.11, :LspLog also works)
:lua vim.cmd.tabnew(vim.lsp.log.get_filename())

" Restart kotlin-lsp (on Neovim 0.11, use :LspRestart)
:lsp restart

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

Format on save is not enabled for Kotlin. Format manually with `:KotlinFormat`
or `<leader>cf`. Java, Rust, Haskell (through hls) and C/C++/Objective-C
(through clangd) do format on save via `conform.nvim`; see
`lua/plugins/formatting.lua`.

### Manual Formatting

```vim
:KotlinFormat
```

## Troubleshooting

### kotlin-lsp not found
If opening a Kotlin file warns that spawning `intellij-server` failed, Mason has not finished installing kotlin-lsp yet. Check `:Mason` (or `:MasonLog` if the install failed), then reopen the file once it is installed.

On Linux arm64 the Mason registry's kotlin-lsp entry (263.7084.0) has a typo in its `bin` path (`{{{ version ...`), so the install fails there. Until it is fixed, download `kotlin-server-<version>-aarch64.tar.gz` from https://github.com/Kotlin/kotlin-lsp/releases and put its `bin/intellij-server` on your PATH; the config runs whichever `intellij-server` it finds.

### LSP not attaching
```vim
:checkhealth vim.lsp      " Check LSP status
:lua vim.cmd.tabnew(vim.lsp.log.get_filename())   " View detailed logs
```

On Neovim 0.11 you can use nvim-lspconfig's `:LspInfo` and `:LspLog` instead. On 0.12 nvim-lspconfig no longer defines them.

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
