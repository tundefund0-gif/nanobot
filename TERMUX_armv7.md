# NanoBot on Termux (32-bit armv7)

## Why source compilation?

PyPI distributes pre-built wheels for Linux (`manylinux`) which link against **glibc**.  
Termux on Android uses **Bionic libc** instead — so those wheels **cannot** be used.

All packages compile from source. This means you need build tools installed, but
everything **will** work on 32-bit ARM.

## One-command install

```bash
bash scripts/setup_termux_armv7.sh
```

This installs:
- Build tools: `clang`, `make`, `cmake`, `pkg-config`, `binutils`
- `rust` + `cargo` (for `pydantic-core`)
- Python 3.11+ and all NanoBot dependencies
- Configures pip with `--no-binary :all:` (required for Termux)

## Manual install

```bash
# 1. System packages
pkg update && pkg upgrade
pkg install python git clang make cmake pkg-config binutils \
         libxml2 libxslt libffi openssl rust

# 2. Configure pip (required for Termux!)
mkdir -p ~/.config/pip
cat > ~/.config/pip/pip.conf << 'EOF'
[global]
no-binary = :all:
EOF

# 3. Force pure-Python fallbacks (optional, avoids some C compilation)
export MSGPACK_PUREPYTHON=1

# 4. Install NanoBot
git clone https://github.com/tundefund0-gif/nanobot.git
cd nanobot
pip install -e .

# 5. Run it
nanobot gateway
```

## Detailed dependency breakdown

| Package | Type | armv7 Status |
|---------|------|-------------|
| `typer`, `anthropic`, `httpx`, `openai`, `beautifulsoup4`, `jinja2`, `rich`, `loguru`, `boto3`, `pypdf`, `python-docx`, `python-pptx`, `filelock`, `pydantic-settings`, `websocket-client`, `ddgs`, `oauth-cli-kit`, `croniter`, `dingtalk-stream`, `python-telegram-bot`, `lark-oapi`, `socksio`, `python-socketio`, `slack-sdk`, `slackify-markdown`, `qq-botpy`, `python-socks`, `prompt-toolkit`, `questionary`, `mcp`, `json-repair`, `chardet`, `segno`, `qrcode`, `PyJWT`, `mistune`, `langsmith`, `olostep`, `wecom-aibot-sdk-python` | Pure Python | ✅ Works directly |
| `websockets`, `msgpack`, `pyyaml`, `openpyxl` | C extensions with **pure Python fallback** | ✅ Auto-fallback |
| ~~`dulwich`~~ | C extension | ✅ **Replaced** with subprocess `git` calls |
| **`pydantic`** | **Rust (`pydantic-core`)** | 🔧 **Compiles via cargo** (setup script handles this) |
| ~~`tiktoken`~~ | Rust | ✅ **Moved to optional** `[tokenizer]` extra; char-based fallback |
| ~~`readability-lxml`~~ | C (`lxml`) | ✅ **Replaced** with `beautifulsoup4` |
| ~~`lxml-html-clean`~~ | C (`lxml`) | ✅ **Removed** (unused) |

### Optional features (may need extra compilation)

| Feature | Dependencies | Notes |
|---------|-------------|-------|
| `[api]` | `aiohttp` | C ext, compiles with clang |
| `[azure]` | `azure-identity` | Pure Python |
| `[msteams]` | `PyJWT`, `cryptography` | Rust `cryptography` compiles with cargo |
| `[weixin]` | `qrcode[pil]`, `pycryptodome` | C ext `pycryptodome` compiles with clang |
| `[discord]` | `discord.py` | Core is pure Python |
| `[matrix]` | `matrix-nio`, `aiohttp`, `mistune`, `nh3` | `nh3` is Rust, compiles with cargo |
| `[whatsapp]` | `neonize`, `segno` | `neonize` is Rust |
| `[pdf]` | `pymupdf` | C++ (MuPDF) — **hardest to compile** |
| `[langsmith]` | `langsmith` | Pure Python |

## Build time estimates (armv7)

| Package | Time | Notes |
|---------|------|-------|
| `pydantic` (pydantic-core) | 10–30 min | Rust compilation, longest step |
| `aiohttp` | 3–8 min | C extension with Cython |
| `cryptography` | 5–15 min | Rust + C mixed |
| `pycryptodome` | 2–5 min | C extensions |
| All other packages | < 1 min each | Pure Python or small C extensions |
