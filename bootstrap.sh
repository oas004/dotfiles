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
        apt)    run_sudo apt-get install -y "$apt_pkg" ;;
        dnf)    run_sudo dnf install -y "$dnf_pkg" ;;
        pacman) run_sudo pacman -S --noconfirm "$pacman_pkg" ;;
        *)      warn "Unknown package manager, install $pkg manually" ;;
    esac
}

# System dependencies
install_system_deps() {
    info "Checking system dependencies..."

    if ! command_exists nvim; then
        info "Installing Neovim..."
        case "$PKG_MGR" in
            brew)   run brew install neovim ;;
            apt)    run_sudo apt-get install -y neovim ;;
            dnf)    run_sudo dnf install -y neovim ;;
            pacman) run_sudo pacman -S --noconfirm neovim ;;
        esac
    else
        info "Neovim already installed: $(nvim --version | head -1)"
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
            apt)    run_sudo apt-get install -y nodejs npm ;;
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
        local major minor
        major=$(echo "$rust_version" | cut -d. -f1)
        minor=$(echo "$rust_version" | cut -d. -f2)
        if [[ "$major" -eq 1 && "$minor" -lt 82 ]]; then
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

    # kotlin-lsp
    local kotlin_lsp_dir="$HOME/.local/opt/kotlin-lsp"
    if [[ ! -x "$kotlin_lsp_dir/kotlin-lsp.sh" ]]; then
        info "Installing kotlin-lsp..."
        if [[ $DRY_RUN -eq 1 ]]; then
            dry "Download and extract kotlin-lsp to $kotlin_lsp_dir"
        else
            mkdir -p "$HOME/.local/opt"
            curl -L https://github.com/Kotlin/kotlin-lsp/releases/latest/download/kotlin-lsp.zip -o /tmp/kotlin-lsp.zip
            unzip -o /tmp/kotlin-lsp.zip -d "$HOME/.local/opt/"
            chmod +x "$kotlin_lsp_dir/kotlin-lsp.sh"
            rm /tmp/kotlin-lsp.zip
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

# Sync Neovim plugins
sync_nvim() {
    info "Syncing Neovim plugins..."
    if [[ $DRY_RUN -eq 1 ]]; then
        dry "nvim --headless '+Lazy! sync' +qa"
        dry "nvim --headless '+TSInstall rust toml wit' +qa"
    else
        nvim --headless "+Lazy! sync" +qa 2>/dev/null || true
        info "Installing treesitter parsers..."
        nvim --headless "+TSInstall rust toml wit" +qa 2>/dev/null || true
    fi
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
    install_wasm_tools
    install_kotlin_tools
    sync_nvim
    print_summary
}

# Allow sourcing for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
