#!/bin/sh
# ============================================================================
# NanoBot — Alpine Linux armv7 Setup
#
# Alpine uses musl libc, so PyPI's manylinux (glibc) wheels are incompatible.
# This script:
#   1. Installs build tools + gcompat (glibc compat layer)
#   2. Installs pre-compiled Alpine packages for pydantic
#   3. Downloads manylinux wheels for Rust packages, patches .so names for musl
#   4. Installs pure-Python deps via pip
# ============================================================================
set -e

NANOBOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$NANOBOT_DIR"

echo "=== Step 1: System packages ==="
apk add --no-cache clang python3-dev musl-dev make gcompat wget 2>&1 | tail -3

echo "=== Step 2: Alpine Python packages (pre-compiled) ==="
apk add --no-cache py3-pydantic py3-pydantic-core py3-pydantic-settings 2>&1 | tail -3

echo "=== Step 3: Create venv ==="
python3 -m venv venv
. venv/bin/activate
pip install --upgrade pip 2>&1 | tail -2

echo "=== Step 4: Install Rust native wheels (patched for musl) ==="
SITE=$(python3 -c "import site; print([p for p in site.getsitepackages() if 'site-packages' in p][0])")

# Helper: download manylinux wheel, patch .so for musl, install
install_manylinux_wheel() {
    local url="$1"
    local name="$(basename "$url" | sed 's/-cp.*//')"
    echo "  Installing $name..."
    wget -q "$url" -O "/tmp/${name}.whl"

    python3 << PYEOF
import zipfile, os, shutil, sys
name = "$name"
whl = f"/tmp/{name}.whl"
site = "$SITE"
extract_dir = f"/tmp/{name}_extracted"
if os.path.exists(extract_dir):
    shutil.rmtree(extract_dir)

with zipfile.ZipFile(whl) as zf:
    zf.extractall(extract_dir)

# Rename .so: gnueabihf -> musleabihf, manylinux -> musllinux
for root, dirs, files in os.walk(extract_dir):
    for f in files:
        if f.endswith('.so'):
            old = os.path.join(root, f)
            new_f = f.replace('gnueabihf', 'musleabihf').replace('manylinux', 'musllinux')
            new = os.path.join(root, new_f)
            os.rename(old, new)
            print(f"  Renamed: {f} -> {new_f}")

# Copy to site-packages
pkg_name = name.split('-')[0]
for item in os.listdir(extract_dir):
    if item.endswith('.dist-info') or item == pkg_name:
        src = os.path.join(extract_dir, item)
        dst = os.path.join(site, item)
        if os.path.exists(dst):
            shutil.rmtree(dst)
        shutil.copytree(src, dst)
        print(f"  Installed: {item}")
PYEOF
}

install_manylinux_wheel \
  "https://files.pythonhosted.org/packages/cp312/j/jiter/jiter-0.15.0-cp312-cp312-manylinux_2_17_armv7l.manylinux2014_armv7l.whl"

install_manylinux_wheel \
  "https://files.pythonhosted.org/packages/cp312/r/rpds-py/rpds_py-2026.5.1-cp312-cp312-manylinux_2_17_armv7l.manylinux2014_armv7l.whl"

echo "=== Step 5: Install NanoBot ==="
export LD_PRELOAD=/usr/lib/libgcompat.so.0
export MSGPACK_PUREPYTHON=1
# Don't use --no-binary for packages we handle above
PIP_NO_BINARY= pip install --no-cache-dir --no-build-isolation -e . 2>&1 | tail -10

echo "=== Step 6: Verify ==="
export LD_PRELOAD=/usr/lib/libgcompat.so.0
python3 -c "from nanobot.cli.commands import app; print('NANOBOT OK')" 2>&1

echo ""
echo "=== ALL DONE! ==="
echo "Run: cd $NANOBOT_DIR && . venv/bin/activate && export LD_PRELOAD=/usr/lib/libgcompat.so.0 && nanobot gateway"
