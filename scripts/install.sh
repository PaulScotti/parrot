#!/usr/bin/env bash
# parrot installer.
#   curl -fsSL https://raw.githubusercontent.com/PaulScotti/parrot/main/scripts/install.sh | sh
#
# Fetches the latest arm64 macOS release, installs the binary and Qwen MLX
# support scripts, then prepares the isolated local model runtime.
#
# Apple Silicon only. MLX runs Qwen3-ASR on Apple unified memory.

set -euo pipefail

REPO="PaulScotti/parrot"
BIN_NAME="parrot"
if [ -d "/opt/homebrew/bin" ]; then
    DEFAULT_INSTALL_DIR="/opt/homebrew/bin"
else
    DEFAULT_INSTALL_DIR="/usr/local/bin"
fi
INSTALL_DIR="${PARROT_INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
PARROT_HOME="${PARROT_HOME:-$HOME/Library/Application Support/Parrot}"
ASSET="parrot-macos-arm64.tar.gz"

red()    { printf "\033[31m%s\033[0m\n" "$*" >&2; }
green()  { printf "\033[32m%s\033[0m\n" "$*"; }
dim()    { printf "\033[2m%s\033[0m\n" "$*"; }

# 1. sanity
if [ "$(uname -s)" != "Darwin" ]; then
    red "parrot is macOS-only (detected $(uname -s))"
    exit 1
fi

ARCH=$(uname -m)
if [ "$ARCH" != "arm64" ]; then
    red "parrot requires Apple Silicon (detected $ARCH)"
    red "the on-device MLX inference engine does not support Intel Macs."
    exit 1
fi

for cmd in curl tar; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        red "missing dependency: $cmd"
        exit 1
    fi
done

# 2. resolve latest release
dim "→ resolving latest release..."
TAG=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | grep -E '"tag_name"' \
    | head -1 \
    | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')

if [ -z "${TAG:-}" ]; then
    red "couldn't determine latest release tag"
    exit 1
fi
dim "  ${TAG}"

URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET}"

# 3. download + extract
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

dim "→ downloading ${ASSET}..."
curl -fsSL "$URL" -o "$TMP/${ASSET}"

dim "→ extracting..."
tar -xzf "$TMP/${ASSET}" -C "$TMP"

if [ ! -f "$TMP/${BIN_NAME}" ] || [ ! -f "$TMP/scripts/setup-qwen-mlx.sh" ]; then
    red "archive did not contain the parrot binary and Qwen MLX support files"
    exit 1
fi

chmod +x "$TMP/${BIN_NAME}"
chmod +x "$TMP/scripts/qwen_mlx_worker.py" "$TMP/scripts/setup-qwen-mlx.sh"

# 4. strip quarantine so Gatekeeper lets the unsigned binary run
xattr -d com.apple.quarantine "$TMP/${BIN_NAME}" 2>/dev/null || true

# 5. install
SUDO=""
if [ ! -w "$INSTALL_DIR" ]; then
    if [ ! -d "$INSTALL_DIR" ]; then
        dim "→ creating ${INSTALL_DIR} (sudo)..."
        sudo mkdir -p "$INSTALL_DIR"
    fi
    SUDO="sudo"
fi

dim "→ installing to ${INSTALL_DIR}/${BIN_NAME}..."
$SUDO mv "$TMP/${BIN_NAME}" "${INSTALL_DIR}/${BIN_NAME}"
$SUDO chmod +x "${INSTALL_DIR}/${BIN_NAME}"

dim "→ installing Qwen MLX support files in ${PARROT_HOME}/scripts..."
mkdir -p "$PARROT_HOME/scripts"
cp "$TMP/scripts/qwen_mlx_worker.py" "$PARROT_HOME/scripts/"
cp "$TMP/scripts/qwen-mlx-requirements.lock" "$PARROT_HOME/scripts/"
cp "$TMP/scripts/setup-qwen-mlx.sh" "$PARROT_HOME/scripts/"
chmod +x "$PARROT_HOME/scripts/qwen_mlx_worker.py" "$PARROT_HOME/scripts/setup-qwen-mlx.sh"

if ! command -v uv >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
        dim "→ installing the uv Python runtime manager..."
        brew install uv
    else
        red "uv is required for the Qwen MLX runtime."
        red "Install Homebrew from https://brew.sh, then rerun this installer."
        exit 1
    fi
fi

dim "→ preparing Qwen3-ASR 1.7B MLX 8-bit..."
PARROT_HOME="$PARROT_HOME" "$PARROT_HOME/scripts/setup-qwen-mlx.sh"

green "✓ parrot ${TAG} installed at ${INSTALL_DIR}/${BIN_NAME}"
green "✓ Qwen runtime installed at ${PARROT_HOME}"
echo
echo "next:"
echo "  parrot setup                       # grant mic + accessibility"
echo "  parrot install --launch-at-login --hotkey backslash --model qwen3-asr-1.7b-mlx-8bit"
echo "  parrot                             # run the daemon"
