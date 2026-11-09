#!/usr/bin/env bash
set -euo pipefail

# Bootstrap script for Neovim configuration
# Works on macOS and Linux (Debian/Ubuntu, Fedora, Arch)
#
# Usage:
#   ./bootstrap.sh              # Full installation
#   ./bootstrap.sh --dry-run    # Show what would be installed
#   ./bootstrap.sh --help       # Show help
#   INSTALL_KOTLIN=1 ./bootstrap.sh  # Include Kotlin tooling

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

DRY_RUN=0
VERBOSE=0
APT_UPDATED=0

# The config needs Neovim 0.11+ (vim.lsp.config/vim.lsp.enable)
MIN_NVIM_VERSION="0.11.0"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Bootstrap Neovim configuration with LSP and development tools.

Options:
    -n, --dry-run    Show what would be installed without making changes
    -v, --verbose    Show more detailed output
    -h, --help       Show this help message

Environment variables:
    INSTALL_KOTLIN=1    Include Kotlin tooling (ktfmt, kotlin-lsp)
    NVIM_RELEASE=tag    Neovim release tag to install on Debian/Ubuntu
                        (default: stable, e.g. v0.12.0)

Examples:
    $(basename "$0")                    # Full installation
    $(basename "$0") --dry-run          # Preview changes
    INSTALL_KOTLIN=1 $(basename "$0")   # Include Kotlin
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--dry-run)
                DRY_RUN=1
                shift
                ;;
            -v|--verbose)
                VERBOSE=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
dry() { echo -e "${BLUE}[DRY-RUN]${NC} Would: $1"; }

command_exists() { command -v "$1" &>/dev/null; }

# version_ge A B: true if dotted version A >= B (missing parts count as 0)
version_ge() {
    local -a a b
    IFS=. read -r -a a <<<"$1"
    IFS=. read -r -a b <<<"$2"
    local i x y
    for ((i = 0; i < 3; i++)); do
        x="${a[i]:-0}"
        y="${b[i]:-0}"
        [[ "$x" =~ ^[0-9]+$ ]] || x=0
        [[ "$y" =~ ^[0-9]+$ ]] || y=0
        if ((10#$x > 10#$y)); then return 0; fi
        if ((10#$x < 10#$y)); then return 1; fi
    done
    return 0
}

# Run a command, or just print it in dry-run mode
run() {
    if [[ $DRY_RUN -eq 1 ]]; then
        dry "$*"
        return 0
    fi
    if [[ $VERBOSE -eq 1 ]]; then
        echo "+ $*"
    fi
    "$@"
}

# Run a command that requires sudo
run_sudo() {
    if [[ $DRY_RUN -eq 1 ]]; then
        dry "sudo $*"
        return 0
    fi
    sudo "$@"
}

# Detect OS and package manager
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
        if command_exists brew; then
            PKG_MGR="brew"
        else
            if [[ $DRY_RUN -eq 1 ]]; then
                warn "Homebrew not found (would fail in real run)"
                PKG_MGR="brew"
            else
                error "Homebrew not found. Install from https://brew.sh"
                exit 1
            fi
        fi
    elif [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        case "$ID" in
            ubuntu|debian|pop)
                OS="debian"
                PKG_MGR="apt"
                ;;
            fedora|rhel|centos)
                OS="fedora"
                PKG_MGR="dnf"
                ;;
            arch|manjaro)
                OS="arch"
                PKG_MGR="pacman"
                ;;
            *)
                OS="linux"
                PKG_MGR="unknown"
                ;;
        esac
    else
        OS="unknown"
        PKG_MGR="unknown"
    fi
    info "Detected OS: $OS (package manager: $PKG_MGR)"
}

install_pkg() {
    local pkg="$1"
    local brew_pkg="${2:-$1}"
    local apt_pkg="${3:-$1}"
    local dnf_pkg="${4:-$1}"
    local pacman_pkg="${5:-$1}"

    case "$PKG_MGR" in
        brew)   run brew install "$brew_pkg" ;;
        apt)    apt_install "$apt_pkg" ;;
        dnf)    run_sudo dnf install -y "$dnf_pkg" ;;
        pacman) run_sudo pacman -S --noconfirm "$pacman_pkg" ;;
        *)      warn "Unknown package manager, install $pkg manually" ;;
    esac
}

# apt-get install, refreshing the package lists before the first install.
# A fresh Debian/Ubuntu machine (or container) has empty or stale lists.
apt_install() {
    if [[ $APT_UPDATED -eq 0 ]]; then
        info "Updating apt package lists..."
        run_sudo apt-get update
        APT_UPDATED=1
    fi
    run_sudo apt-get install -y "$@"
}

# Print the installed Neovim version, e.g. 0.11.4 (empty if unknown)
nvim_version() {
    nvim --version 2>/dev/null | sed -n '1s/^NVIM v\{0,1\}\([0-9][0-9.]*\).*/\1/p'
}

# Fail if nvim is older than MIN_NVIM_VERSION; warn if it is older than 0.12
check_nvim_version() {
    local ver
    ver="$(nvim_version)"
    if [[ -z "$ver" ]]; then
        warn "Could not determine the Neovim version ($MIN_NVIM_VERSION+ required)"
        return 0
    fi

    if ! version_ge "$ver" "$MIN_NVIM_VERSION"; then
        local msg="Neovim $ver is too old: this config needs $MIN_NVIM_VERSION+ (0.12+ recommended)"
        local hint="Upgrade Neovim (https://github.com/neovim/neovim/releases) and rerun this script"
        if [[ "$PKG_MGR" == "apt" ]]; then
            hint="apt's neovim package is too old. Remove it (sudo apt-get remove neovim) and rerun this script to install a release build into ~/.local/bin"
        fi
        if [[ $DRY_RUN -eq 1 ]]; then
            warn "$msg (would fail in real run)"
            return 0
        fi
        error "$msg"
        error "$hint"
        exit 1
    fi

    # nvim-treesitter main needs Neovim 0.12+; on 0.11 the config pins an older commit
    if ! version_ge "$ver" "0.12"; then
        warn "Neovim 0.12+ recommended (nvim-treesitter main is pinned to an older commit on 0.11)"
    fi
}

# Install the official Neovim release build into ~/.local/opt/nvim and
# symlink it as ~/.local/bin/nvim. Used on Debian/Ubuntu, whose neovim
# package is older than the 0.11 this config needs.
install_nvim_release() {
    local arch
    case "$(uname -m)" in
        x86_64|amd64)  arch="x86_64" ;;
        aarch64|arm64) arch="arm64" ;;
        *)
            error "No Neovim release build for $(uname -m); install Neovim $MIN_NVIM_VERSION+ manually"
            exit 1
            ;;
    esac

    local release="${NVIM_RELEASE:-stable}"
    local name="nvim-linux-$arch"
    local url="https://github.com/neovim/neovim/releases/download/$release/$name.tar.gz"
    local dest="$HOME/.local/opt/nvim"
    local bin_dir="$HOME/.local/bin"

    info "Installing Neovim ($release) from the official release build..."
    if [[ $DRY_RUN -eq 1 ]]; then
        dry "Download $url, extract it to $dest and symlink $bin_dir/nvim to $dest/bin/nvim"
        return 0
    fi

    # Global so the EXIT trap can still see it if curl or tar fails and
    # set -e exits the script
    NVIM_RELEASE_TMP="$(mktemp -d)"
    trap 'rm -rf "$NVIM_RELEASE_TMP"' EXIT
    local tmp="$NVIM_RELEASE_TMP"
    run curl -fL "$url" -o "$tmp/nvim.tar.gz"
    run tar xzf "$tmp/nvim.tar.gz" -C "$tmp"
    run mkdir -p "$(dirname "$dest")" "$bin_dir"
    run rm -rf "$dest"
    run mv "$tmp/$name" "$dest"
    run ln -sf "$dest/bin/nvim" "$bin_dir/nvim"
    rm -rf "$tmp"
    trap - EXIT

    case ":$PATH:" in
        *":$bin_dir:"*) ;;
        *)
            warn "$bin_dir is not on your PATH; add it in your shell profile"
            export PATH="$bin_dir:$PATH"
            ;;
    esac
}

# System dependencies
install_system_deps() {
    info "Checking system dependencies..."

    # Used for the Neovim release build, rustup and kotlin-lsp downloads
    if ! command_exists curl; then
        info "Installing curl..."
        install_pkg curl
    fi

    if ! command_exists nvim; then
        info "Installing Neovim..."
        case "$PKG_MGR" in
            brew)   run brew install neovim ;;
            apt)    install_nvim_release ;;
            dnf)    run_sudo dnf install -y neovim ;;
            pacman) run_sudo pacman -S --noconfirm neovim ;;
            *)      warn "Unknown package manager, install Neovim $MIN_NVIM_VERSION+ manually" ;;
        esac
        if [[ $DRY_RUN -eq 0 ]] && command_exists nvim; then
            check_nvim_version
        fi
    else
        info "Neovim already installed: $(nvim --version | head -1)"
        check_nvim_version
    fi

    if ! command_exists rg; then
        info "Installing ripgrep..."
        install_pkg ripgrep ripgrep ripgrep ripgrep ripgrep
    else
        info "ripgrep already installed"
    fi

    if ! command_exists git; then
        info "Installing git..."
        install_pkg git
    else
        info "git already installed"
    fi

    # Node.js (needed for some LSPs)
    if ! command_exists node; then
        info "Installing Node.js..."
        case "$PKG_MGR" in
            brew)   run brew install node ;;
            apt)    apt_install nodejs npm ;;
            dnf)    run_sudo dnf install -y nodejs npm ;;
            pacman) run_sudo pacman -S --noconfirm nodejs npm ;;
        esac
    else
        info "Node.js already installed"
    fi
}

# Rust toolchain
install_rust() {
    info "Checking Rust toolchain..."

    if ! command_exists rustup; then
        info "Installing Rust via rustup..."
        if [[ $DRY_RUN -eq 1 ]]; then
            dry "curl https://sh.rustup.rs | sh -s -- -y"
        else
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
            # shellcheck source=/dev/null
            source "$HOME/.cargo/env"
        fi
    else
        info "Rust already installed: $(rustc --version)"
        # wasm-tools requires Rust 1.82+ for edition2024 support
        local rust_version
        rust_version=$(rustc --version | grep -oE '[0-9]+\.[0-9]+' | head -1)
        if ! version_ge "$rust_version" "1.82"; then
            warn "Rust $rust_version is too old for wasm-tools (needs 1.82+)"
            info "Updating Rust toolchain..."
            run rustup update stable
        fi
    fi

    # Ensure rust-analyzer component is installed
    if ! command_exists rust-analyzer; then
        info "Installing rust-analyzer..."
        run rustup component add rust-analyzer
    else
        info "rust-analyzer already installed"
    fi

    # Ensure rustfmt is installed
    if ! command_exists rustfmt; then
        info "Installing rustfmt..."
        run rustup component add rustfmt
    else
        info "rustfmt already installed"
    fi
}

# Treesitter tooling: nvim-treesitter main compiles parsers with the
# tree-sitter CLI (0.26.1+, not the npm package) and a C compiler
install_treesitter_cli() {
    info "Checking tree-sitter CLI..."

    if ! command_exists cc && ! command_exists gcc && ! command_exists clang; then
        warn "No C compiler found; treesitter parsers cannot be compiled"
    fi

    if command_exists tree-sitter; then
        info "tree-sitter CLI already installed: $(tree-sitter --version)"
        return
    fi

    info "Installing tree-sitter CLI..."
    case "$PKG_MGR" in
        brew|dnf|pacman)
            install_pkg tree-sitter-cli
            ;;
        *)
            # Distro packages (e.g. Debian/Ubuntu) are often older than 0.26.1
            if command_exists cargo || [[ $DRY_RUN -eq 1 ]]; then
                run cargo install --locked tree-sitter-cli
            else
                warn "tree-sitter CLI: install manually (cargo install --locked tree-sitter-cli)"
            fi
            ;;
    esac
}

# WebAssembly tooling
install_wasm_tools() {
    info "Checking WebAssembly tooling..."

    if ! command_exists wasm-tools; then
        info "Installing wasm-tools..."
        run cargo install wasm-tools
    else
        info "wasm-tools already installed"
    fi

    if ! command_exists wit-bindgen; then
        info "Installing wit-bindgen..."
        run cargo install wit-bindgen-cli
    else
        info "wit-bindgen already installed"
    fi

    # WebAssembly targets for Rust
    info "Adding WebAssembly targets..."
    run rustup target add wasm32-unknown-unknown
    # Try newer target name first, fall back to older
    if [[ $DRY_RUN -eq 1 ]]; then
        dry "rustup target add wasm32-wasip1 (or wasm32-wasi)"
    else
        rustup target add wasm32-wasip1 2>/dev/null || rustup target add wasm32-wasi 2>/dev/null || true
    fi
}

# Kotlin tooling (optional)
install_kotlin_tools() {
    if [[ "${INSTALL_KOTLIN:-}" != "1" ]]; then
        return
    fi

    info "Installing Kotlin tooling..."

    # ktfmt
    if ! command_exists ktfmt; then
        case "$PKG_MGR" in
            brew)
                run brew install ktfmt
                ;;
            *)
                warn "ktfmt: install manually from https://github.com/facebook/ktfmt"
                ;;
        esac
    else
        info "ktfmt already installed"
    fi

    # kotlin-lsp: standalone build from download.jetbrains.com (the GitHub
    # releases page links there). macOS gets a .sit file, which is a zip.
    local kotlin_lsp_dir="$HOME/.local/opt/kotlin-lsp"
    if [[ ! -x "$kotlin_lsp_dir/kotlin-lsp.sh" ]]; then
        local ver="${KOTLIN_LSP_VERSION:-263.7084.0}"
        local suffix=""
        case "$(uname -m)" in arm64|aarch64) suffix="-aarch64" ;; esac
        local ext="tar.gz"
        [[ "$OS" == "macos" ]] && ext="sit"
        local url="https://download.jetbrains.com/language-server/kotlin-server/$ver/kotlin-server-$ver$suffix.$ext"

        info "Installing kotlin-lsp $ver..."
        if [[ $DRY_RUN -eq 1 ]]; then
            dry "Download $url and extract it to $kotlin_lsp_dir"
        else
            local tmp
            tmp="$(mktemp -d)"
            curl -fL "$url" -o "$tmp/archive"
            mkdir -p "$tmp/x"
            if [[ "$ext" == "sit" ]]; then
                unzip -q "$tmp/archive" -d "$tmp/x"
            else
                tar xzf "$tmp/archive" -C "$tmp/x"
            fi
            # Use the archive's top-level directory if it has exactly one
            local src="$tmp/x"
            local entries=("$tmp/x"/*)
            if [[ ${#entries[@]} -eq 1 && -d "${entries[0]}" ]]; then
                src="${entries[0]}"
            fi
            mkdir -p "$(dirname "$kotlin_lsp_dir")"
            rm -rf "$kotlin_lsp_dir"
            mv "$src" "$kotlin_lsp_dir"
            chmod +x "$kotlin_lsp_dir/kotlin-lsp.sh"
            rm -rf "$tmp"
        fi
    else
        info "kotlin-lsp already installed"
    fi
}

# Create necessary directories
setup_directories() {
    info "Setting up directories..."
    run mkdir -p "$HOME/.local/opt"
    run mkdir -p "$HOME/.local/share/nvim"
}

# Install plugins at the versions in lazy-lock.json, then treesitter parsers.
# Errors in +commands don't change nvim's exit code, and lazy.nvim doesn't
# report failed git commands as errors in headless mode, so each step checks
# its own result.
sync_nvim() {
    info "Restoring Neovim plugins to the versions in lazy-lock.json..."
    # Parser installs are async, so wait for them before quitting.
    # vim.g.treesitter_parsers is the list from lua/plugins/parser.lua.
    local ts_install="lua local ok, res = pcall(function()"
    ts_install+=" assert(vim.g.treesitter_parsers, 'vim.g.treesitter_parsers is not set')"
    ts_install+=" return require('nvim-treesitter').install(vim.g.treesitter_parsers):wait(300000)"
    ts_install+=" end)"
    ts_install+=" if not (ok and res) then io.stderr:write('Treesitter parser install failed: ' .. (ok and 'see messages above' or tostring(res)) .. '\n') vim.cmd.cquit() end"
    local lazy_loaded="lua if vim.fn.exists(':Lazy') ~= 2 then io.stderr:write('lazy.nvim did not load\n') vim.cmd.cquit() end"
    # Loading the config starts nvim-treesitter's background install of
    # missing parsers (lua/plugins/parser.lua), and a restore that moves
    # nvim-treesitter runs its :TSUpdate build. Quitting while those run
    # leaves half-finished installs in the cache that break the next
    # install, so wait for them first. update() and install() wait for an
    # in-flight install of the same parser. Skipped if nvim-treesitter
    # isn't loaded or isn't on main yet; failures are left to the strict
    # parser step at the end.
    local ts_settle="lua local ok, ts = pcall(require, 'nvim-treesitter')"
    ts_settle+=" if ok and ts.install and ts.update and vim.g.treesitter_parsers then pcall(function()"
    ts_settle+=" ts.update(vim.g.treesitter_parsers):wait(300000)"
    ts_settle+=" ts.install(vim.g.treesitter_parsers):wait(300000)"
    ts_settle+=" end) end"

    if [[ $DRY_RUN -eq 1 ]]; then
        dry "nvim --headless +qa (lazy.nvim installs missing plugins on startup)"
        dry "nvim --headless '+Lazy! restore' +qa"
        dry "wait for nvim-treesitter's background parser installs before each +qa above"
        dry "check every plugin is at its lazy-lock.json commit, and fail otherwise"
        dry "nvim --headless \"+lua require('nvim-treesitter').install(vim.g.treesitter_parsers):wait(300000)\" +qa"
        return 0
    fi

    local config_dir lockfile snapshot
    config_dir="$(nvim --clean --headless "+lua io.write(vim.fn.stdpath('config'))" +qa)" || {
        error "Could not run nvim"
        exit 1
    }
    lockfile="$config_dir/lazy-lock.json"
    if [[ ! -f "$lockfile" ]]; then
        error "No lazy-lock.json found at $lockfile"
        exit 1
    fi
    # lazy.nvim rewrites lazy-lock.json with the commits actually checked
    # out, so a snapshot taken first tells us whether the restore worked.
    snapshot="$(mktemp)"
    cp "$lockfile" "$snapshot"

    # On a fresh machine lazy.nvim installs missing plugins on startup and
    # records its own freshly cloned commit in the lockfile. Put the
    # original lockfile back before restoring so lazy.nvim is restored too.
    if ! nvim --headless "+$lazy_loaded" "+$ts_settle" +qa; then
        cp "$snapshot" "$lockfile"
        rm -f "$snapshot"
        error "Neovim plugin install failed (see output above)"
        exit 1
    fi
    cp "$snapshot" "$lockfile"

    local restored=1
    nvim --headless "+$lazy_loaded" "+Lazy! restore" "+$ts_settle" +qa || restored=0
    echo ""
    if [[ $restored -eq 1 ]] && ! cmp -s "$snapshot" "$lockfile"; then
        restored=0
        error "These plugins are not at their lazy-lock.json commit (- locked, + checked out):"
        diff "$snapshot" "$lockfile" | grep '^[<>]' | sed 's/^</-/; s/^>/+/' || true
    fi
    # Leave lazy-lock.json as it was in the repo
    cp "$snapshot" "$lockfile"
    rm -f "$snapshot"
    if [[ $restored -eq 0 ]]; then
        error "Neovim plugin restore failed (see output above)"
        exit 1
    fi

    info "Installing treesitter parsers..."
    if ! nvim --headless "+$ts_install" +qa; then
        error "Treesitter parser install failed (see output above)"
        exit 1
    fi
    echo ""
}

# Summary of what's installed
print_summary() {
    echo ""
    echo "========================================"
    if [[ $DRY_RUN -eq 1 ]]; then
        info "Dry run complete (no changes made)"
    else
        info "Bootstrap complete!"
    fi
    echo "========================================"
    echo ""

    if [[ $DRY_RUN -eq 0 ]]; then
        echo "Installed tools:"
        echo "  - Neovim: $(nvim --version | head -1)"
        command_exists rustc && echo "  - Rust: $(rustc --version)"
        echo "  - rust-analyzer: $(rust-analyzer --version 2>/dev/null || echo 'via rustup')"
        command_exists wasm-tools && echo "  - wasm-tools: $(wasm-tools --version)"
        command_exists wit-bindgen && echo "  - wit-bindgen: $(wit-bindgen --version)"
        echo ""
    fi

    echo "Next steps:"
    echo "  1. Open Neovim: nvim"
    echo "  2. Run :Mason to install/manage LSP servers"
    echo "  3. Run :checkhealth to verify setup"
    echo ""
    if [[ "${INSTALL_KOTLIN:-}" != "1" ]]; then
        echo "For Kotlin support, run: INSTALL_KOTLIN=1 $0"
    fi
}

# Main
main() {
    parse_args "$@"

    echo "========================================"
    echo "  Neovim Configuration Bootstrap"
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "  (DRY RUN - no changes will be made)"
    fi
    echo "========================================"
    echo ""

    detect_os
    setup_directories
    install_system_deps
    install_rust
    install_treesitter_cli
    install_wasm_tools
    install_kotlin_tools
    sync_nvim
    print_summary
}

# Allow sourcing for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
