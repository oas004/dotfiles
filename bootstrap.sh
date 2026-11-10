#!/usr/bin/env bash
set -euo pipefail

# Bootstrap script for Neovim configuration
# Works on macOS and Linux (Debian/Ubuntu, Fedora, Arch)
#
# Usage:
#   ./bootstrap.sh              # Full installation
#   ./bootstrap.sh --dry-run    # Show what would be installed
#   ./bootstrap.sh --help       # Show help

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

# jdtls needs Java 21+ to run, and gradle_ls and ktfmt (Mason java-jar
# wrappers, ktfmt needs 17+) run on the same JDK
MIN_JAVA_VERSION=21
# macOS JDK lookup; a variable so the tests can point it elsewhere
MACOS_JAVA_HOME_CMD="/usr/libexec/java_home"

# Warnings repeated at the end by print_summary, one per line
SUMMARY_WARNINGS=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Bootstrap Neovim configuration with LSP and development tools.

Options:
    -n, --dry-run    Show what would be installed without making changes
    -v, --verbose    Show more detailed output
    -h, --help       Show this help message

Environment variables:
    NVIM_RELEASE=tag    Neovim release tag to install on Debian/Ubuntu
                        (default: stable, e.g. v0.12.0)

Examples:
    $(basename "$0")                    # Full installation
    $(basename "$0") --dry-run          # Preview changes
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

# Warn now and again in the summary
warn_later() {
    warn "$1"
    SUMMARY_WARNINGS+="$1"$'\n'
}

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

    # Used for the Neovim release build and rustup downloads, and by Mason
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

    # Mason downloads and extracts servers with curl, git, unzip, tar and
    # gzip (kotlin-lsp's macOS .sit archive is a zip). jq is the json
    # formatter in lua/plugins/formatting.lua.
    local tool
    for tool in git unzip tar gzip jq; do
        if ! command_exists "$tool"; then
            info "Installing $tool..."
            install_pkg "$tool"
        else
            info "$tool already installed"
        fi
    done
}

# Print the major version of a java binary, e.g. 21 (empty if unknown)
java_major() {
    local ver
    ver="$("$1" -version 2>&1 | sed -n 's/.*version "\([^"]*\)".*/\1/p' | head -1)" || true
    # Java 8 and older report 1.8.0_x
    [[ "$ver" == 1.* ]] && ver="${ver#1.}"
    echo "${ver%%[!0-9]*}"
}

# Shell profile lines that make the JDK at $1 the one jdtls (JAVA_HOME) and
# gradle_ls (java on PATH) run on
java_env_hint() {
    echo "export JAVA_HOME=\"$1\"; export PATH=\"\$JAVA_HOME/bin:\$PATH\""
}

# JDK for jdtls, gradle_ls and ktfmt. jdtls uses $JAVA_HOME if set, else
# java on PATH; the others use java on PATH.
install_jdk() {
    info "Checking JDK (jdtls and gradle_ls need Java $MIN_JAVA_VERSION+)..."

    local java_bin="java" major=""
    [[ -n "${JAVA_HOME:-}" ]] && java_bin="$JAVA_HOME/bin/java"
    command_exists "$java_bin" && major="$(java_major "$java_bin")"
    if [[ -n "$major" ]] && ((major >= MIN_JAVA_VERSION)); then
        info "Java $major already installed"
        return
    fi
    local found="Java ${major:-not found}"
    [[ -n "${JAVA_HOME:-}" ]] && found+=" (JAVA_HOME=$JAVA_HOME)"

    # On macOS a JDK 21+ may be installed without being the default.
    # java_home returns some other JDK if none matches, so check its version.
    if [[ -x "$MACOS_JAVA_HOME_CMD" ]]; then
        local home
        home="$("$MACOS_JAVA_HOME_CMD" -v "$MIN_JAVA_VERSION+" 2>/dev/null)" || true
        major=""
        [[ -n "$home" ]] && major="$(java_major "$home/bin/java")"
        if [[ -n "$major" ]] && ((major >= MIN_JAVA_VERSION)); then
            warn_later "$found is too old for jdtls, but Java $major is installed. Add to your shell profile: $(java_env_hint "$home")"
            return
        fi
    fi

    info "Installing JDK $MIN_JAVA_VERSION..."
    local ok=1
    case "$PKG_MGR" in
        brew)   run brew install "openjdk@$MIN_JAVA_VERSION" || ok=0 ;;
        apt)    apt_install "openjdk-$MIN_JAVA_VERSION-jdk" || ok=0 ;;
        dnf)    run_sudo dnf install -y "java-$MIN_JAVA_VERSION-openjdk-devel" || ok=0 ;;
        pacman) run_sudo pacman -S --noconfirm "jdk$MIN_JAVA_VERSION-openjdk" || ok=0 ;;
        *)      ok=0 ;;
    esac
    if [[ $ok -eq 0 ]]; then
        # Not fatal: some distros (e.g. Debian 12) have no JDK 21 package
        warn_later "Could not install JDK $MIN_JAVA_VERSION. Install JDK $MIN_JAVA_VERSION+ (e.g. from https://adoptium.net) and add to your shell profile: $(java_env_hint "<jdk dir>")"
        return
    fi

    if [[ "$PKG_MGR" == "brew" ]]; then
        # Homebrew's openjdk@21 is keg-only: not on PATH or seen by java_home
        local prefix
        prefix="$(brew --prefix 2>/dev/null)" || prefix="/opt/homebrew"
        warn_later "openjdk@$MIN_JAVA_VERSION is keg-only. Add to your shell profile: $(java_env_hint "$prefix/opt/openjdk@$MIN_JAVA_VERSION/libexec/openjdk.jdk/Contents/Home")"
    elif [[ $DRY_RUN -eq 0 ]]; then
        major=""
        command_exists "$java_bin" && major="$(java_major "$java_bin")"
        if [[ -z "$major" ]] || ((major < MIN_JAVA_VERSION)); then
            warn_later "$found is still the default. Add to your shell profile: $(java_env_hint "/usr/lib/jvm/<JDK $MIN_JAVA_VERSION dir>")"
        fi
    fi
}

# python3 with venv: Mason installs jedi-language-server into a venv, and
# Mason's jdtls launcher is a Python script
install_python() {
    info "Checking python3 with venv..."

    # Debian/Ubuntu split ensurepip, which venv needs, into python3-venv
    if python3 -c 'import ensurepip, venv' &>/dev/null; then
        info "python3 with venv already installed"
        return
    fi

    info "Installing python3 with venv..."
    case "$PKG_MGR" in
        brew)   run brew install python ;;
        apt)    apt_install python3 python3-venv ;;
        dnf)    run_sudo dnf install -y python3 ;;
        pacman) run_sudo pacman -S --noconfirm python ;;
        *)      warn "Unknown package manager, install python3 with venv manually" ;;
    esac
}

# Mason installs haskell-language-server with ghcup. ghcup's installer is
# interactive and installs GHC as well, so it is left to the user.
check_ghcup() {
    if command_exists ghcup; then
        info "ghcup already installed"
    else
        warn_later "ghcup not found, so Mason can't install haskell-language-server (hls). To use Haskell, install ghcup and GHC: curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh"
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

    # rust-analyzer (the LSP server) and rustfmt (conform's Rust formatter).
    # rustup puts proxies for both in ~/.cargo/bin even when the component
    # isn't installed, so check that the tool actually runs.
    local component
    for component in rust-analyzer rustfmt; do
        if rustup_has_component "$component" || "$component" --version &>/dev/null; then
            info "$component already installed"
        else
            info "Installing $component..."
            run rustup component add "$component"
        fi
    done
}

# True if the rustup component is installed for the default toolchain
rustup_has_component() {
    local installed
    installed="$(rustup component list --installed 2>/dev/null)" || return 1
    grep -Eq "^$1(-|\$)" <<<"$installed"
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
        dry "check every plugin is at its lazy-lock.json commit, restore once more if not, and fail if still not"
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

    # lazy.nvim installs missing plugins on startup at their lockfile commits
    # (lua/core/package-manager.lua clones lazy.nvim itself at its locked
    # commit), then rewrites the lockfile with the commit every installed
    # plugin is on. On a fresh machine that leaves it unchanged, but plugins
    # that were already installed on other commits end up in it, and a
    # restore in the same nvim would keep them there. So install in a run of
    # its own and put the original lockfile back before restoring.
    if ! nvim --headless "+$lazy_loaded" "+$ts_settle" +qa; then
        cp "$snapshot" "$lockfile"
        rm -f "$snapshot"
        error "Neovim plugin install failed (see output above)"
        exit 1
    fi
    cp "$snapshot" "$lockfile"

    # In headless mode Lazy! restore does not report plugins it left on
    # other commits, so compare the lockfile it writes with the snapshot. A
    # second restore has fixed such plugins before, so retry once.
    local restored=0 attempt
    for attempt in 1 2; do
        local rc=0
        nvim --headless "+$lazy_loaded" "+Lazy! restore" "+$ts_settle" +qa || rc=$?
        echo ""
        [[ $rc -eq 0 ]] || break
        if cmp -s "$snapshot" "$lockfile"; then
            restored=1
            break
        fi
        if [[ $attempt -eq 1 ]]; then
            info "These plugins are not at their lazy-lock.json commit, restoring again (- locked, + checked out):"
        else
            error "These plugins are not at their lazy-lock.json commit (- locked, + checked out):"
        fi
        diff "$snapshot" "$lockfile" | grep '^[<>]' | sed 's/^</-/; s/^>/+/' || true
        cp "$snapshot" "$lockfile"
    done
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
        local ra_version
        if ra_version="$(rust-analyzer --version 2>/dev/null)"; then
            echo "  - rust-analyzer: $ra_version"
        else
            SUMMARY_WARNINGS+="rust-analyzer does not run; install it with: rustup component add rust-analyzer"$'\n'
        fi
        command_exists wasm-tools && echo "  - wasm-tools: $(wasm-tools --version)"
        command_exists wit-bindgen && echo "  - wit-bindgen: $(wit-bindgen --version)"
        echo ""
    fi

    if [[ -n "$SUMMARY_WARNINGS" ]]; then
        local line
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then warn "$line"; fi
        done <<<"$SUMMARY_WARNINGS"
        echo ""
    fi

    echo "Next steps:"
    echo "  1. Open Neovim: nvim"
    echo "  2. Wait for Mason to install the language servers and formatters (:Mason shows progress)"
    echo "  3. Run :checkhealth to verify setup"
    echo ""
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
    install_jdk
    install_python
    check_ghcup
    install_rust
    install_treesitter_cli
    install_wasm_tools
    sync_nvim
    print_summary
}

# Allow sourcing for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
