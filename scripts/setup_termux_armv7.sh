#!/data/data/com.termux/files/usr/bin/bash
# ============================================================================
# setup_termux_armv7.sh — Install NanoBot on 32-bit ARM Termux
#
# This script installs build tools and compiles native dependencies from
# source so NanoBot runs on armv7 (32-bit ARM) Android devices.
#
# Usage:  bash scripts/setup_termux_armv7.sh
# ============================================================================
set -euo pipefail

echo "=============================================="
echo " NanoBot — Termux armv7 Setup"
echo "=============================================="
echo ""

# ---- 1. Update packages ----
echo "[1/5] Updating Termux packages..."
yes | pkg update && yes | pkg upgrade

# ---- 2. Install build tools ----
echo "[2/5] Installing build tools (clang, Rust, make, cmake)..."
yes | pkg install \
    python \
    clang \
    make \
    cmake \
    binutils \
    rust \
    pkg-config \
    libxml2 \
    libxslt \
    libffi \
    openssl \
    git

# ---- 3. Install Rust (for pydantic-core & tiktoken) ----
# pkg install rust above should handle this, but ensure cargo is available
if ! command -v cargo &>/dev/null; then
    echo "Rust (cargo) not found via pkg; installing via rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
fi

# Add armv7 Android target for cross-compilation within Rust crates
rustup target add armv7-linux-androideabi 2>/dev/null || true

# ---- 4. Install NanoBot ----
echo "[4/5] Installing NanoBot with source compilation..."

cd "$(dirname "$0")/.."

# Install core dependencies, compiling native packages from source
# --no-binary forces pip to compile wheels, which is required on armv7
# since manylinux wheels use glibc (incompatible with Termux's Bionic libc)
pip install \
    --no-binary pydantic \
    --no-binary dulwich \
    --no-binary msgpack \
    --no-binary websockets \
    --no-binary pyyaml \
    --no-binary cryptography \
    --no-binary openpyxl \
    -e ".[dev]"

# Optional: install tiktoken for precise token counting
# (requires Rust compilation, may take a while)
echo ""
echo "  Optional: install tiktoken for accurate token counting?"
echo "  (y/N)  "
read -r INSTALL_TIKTOKEN
if [[ "$INSTALL_TIKTOKEN" =~ ^[Yy] ]]; then
    echo "Installing tiktoken (compiling from Rust source)..."
    pip install --no-binary tiktoken "tiktoken>=0.12.0,<1.0.0"
fi

# ---- 5. Verify ----
echo "[5/5] Verifying installation..."
python3 -c "
from nanobot.cli.commands import app
print('✓ NanoBot CLI loaded successfully')
try:
    import tiktoken
    print('✓ tiktoken available (precise token counting)')
except ImportError:
    print('✓ tiktoken not installed (char-based fallback active)')
"

echo ""
echo "=============================================="
echo " Setup complete!"
echo ""
echo " Run:  nanobot gateway"
echo " Or:   nanobot --help"
echo "=============================================="
