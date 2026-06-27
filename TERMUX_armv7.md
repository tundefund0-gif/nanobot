# NanoBot on Termux (32-bit armv7)

NanoBot has been adapted to work on **32-bit ARM (armv7) Android** devices running Termux.

## Key changes from upstream

| Library | Upstream | This fork |
|---------|----------|-----------|
| `tiktoken` | Hard dependency (Rust, no armv7 wheel) | **Optional** — `pip install nanobot-ai[tokenizer]`; char-based fallback when missing |
| `readability-lxml` | Hard dependency (pulls in `lxml`) | Replaced with **beautifulsoup4** (pure Python) |
| `lxml-html-clean` | Hard dependency (not actually imported) | **Removed** |
| `pydantic` | Hard dependency (Rust `pydantic-core`) | Still required — **must compile from source** on armv7 |

## Quick start

```bash
# 1. Install build tools
pkg update && pkg upgrade
pkg install python clang make cmake binutils rust pkg-config libxml2 libxslt git

# 2. Install NanoBot (compiles native deps from source)
pip install --no-binary pydantic,dulwich,msgpack,websockets,pyyaml,openpyxl -e .

# 3. Optional: tiktoken for precise token counting
pip install --no-binary tiktoken tiktoken

# 4. Run it
nanobot gateway
```

## What works

- Core agent loop, chat channels, tools
- Token counting falls back to char-based estimation (~4 chars/token)

## What needs compilation (slow on armv7)

- **`pydantic`** — Rust `pydantic-core` takes ~10–30 min to compile
- **`dulwich`** — Git library with C extensions
- **`msgpack`**, **`websockets`**, **`pyyaml`** — Have pure-Python fallbacks but compiled is faster
- **`openpyxl`** — Excel support, mostly pure Python

## Optional features that won't work

Channels that depend on `cryptography` (Rust):
- `msteams` (`pip install nanobot-ai[msteams]`)
- `weixin` (`pip install nanobot-ai[weixin]`) — partially blocked

PDF extraction with `pymupdf`:
- `pip install nanobot-ai[pdf]` — MuPDF is C++, very hard to cross-compile
