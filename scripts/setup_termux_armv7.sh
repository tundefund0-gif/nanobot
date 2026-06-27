#!/data/data/com.termux/files/usr/bin/bash
# ============================================================================
# NanoBot — Termux armv7 One-Click Setup
#
# Installs ALL dependencies on 32-bit ARM Termux with source compilation.
# PyPI's manylinux wheels use glibc, which is incompatible with Android's
# Bionic libc, so we compile everything from source.
# ============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

NANOBOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$NANOBOT_DIR"

info "=============================================="
info " NanoBot — Termux armv7 Setup"
info "=============================================="
echo ""

# ---- 1. System packages ----
info "[1/5] Installing Termux build tools..."
yes 2>/dev/null | pkg update   || warn "pkg update failed (repos may be stale)"
yes 2>/dev/null | pkg upgrade  || warn "pkg upgrade failed"

# Core: Python + Git + build essentials
yes 2>/dev/null | pkg install \
    python \
    git \
    clang \
    make \
    cmake \
    pkg-config \
    binutils \
    libxml2 \
    libxslt \
    libffi \
    openssl \
|| warn "Some system packages failed to install"

# ---- 2. Rust (required for pydantic-core) ----
info "[2/5] Installing Rust toolchain..."
if command -v rustc &>/dev/null; then
    info "Rust already installed (rustc $(rustc --version | cut -d' ' -f2))"
else
    # Try pkg first, fall back to rustup
    yes 2>/dev/null | pkg install rust || {
        info "Installing Rust via rustup (this may take a while)..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
    }
fi

# Optional: add Android target (needed for some Rust crates)
rustup target add armv7-linux-androideabi 2>/dev/null || true

# ---- 3. pip configuration ----
info "[3/5] Configuring pip for Termux..."

# On Termux, manylinux/musllinux wheels are incompatible with Android's
# Bionic libc. We force source compilation which either:
#   • Extracts .py files (pure-Python packages)  ✓
#   • Compiles C extensions from source (clang)   ✓
#   • Compiles Rust crates from source (cargo)    ✓
mkdir -p "$HOME/.config/pip"
cat > "$HOME/.config/pip/pip.conf" << 'PIPEOF'
[global]
# Never use pre-built manylinux/musllinux wheels — they link glibc/musl
# which is incompatible with Termux's Bionic libc.
no-binary = :all:
# Respect standard Termux paths
target = /data/data/com.termux/files/usr/lib/python3.13/site-packages
PIPEOF

# ---- 4. Environment variables for pure-Python fallbacks ----
# Force msgpack to use its pure-Python implementation (avoids C compilation)
export MSGPACK_PUREPYTHON=1
# PyYAML will fall back to pure Python if libyaml headers are missing
# websockets/dulwich auto-fallback to pure Python when C ext unavailable

# ---- 5. Install NanoBot ----
info "[4/5] Installing NanoBot and all dependencies..."

# Clean install with --no-binary already set via pip.conf
# pydantic-core (Rust) will compile via cargo — this takes ~10-30 min on armv7
# dulwich was replaced with subprocess git calls — no compilation needed
info "Compiling pydantic-core (Rust) — this may take 10-30 minutes..."
pip install -e ".[dev]" 2>&1 | tail -20 || {
    error "Main install failed. Trying without dev extras..."
    pip install -e "." 2>&1 | tail -20
}

# ---- 6. Verify ----
info "[5/5] Verifying installation..."
python3 -c "
from nanobot.cli.commands import app
print('✓ NanoBot CLI loaded successfully')
try:
    import tiktoken; print('✓ tiktoken available (precise token counting)')
except ImportError:
    print('✓ tiktoken optional (char-based fallback active)')
" && {
    info "=============================================="
    info "  Setup complete!"
    info ""
    info "  Run:  nanobot gateway"
    info "  Or:   nanobot --help"
    info "=============================================="
} || {
    error "Verification failed. Check the errors above."
    exit 1
}
