#!/usr/bin/env bash
# parrot installer.
#   curl -fsSL https://raw.githubusercontent.com/PaulScotti/parrot/main/scripts/install.sh | sh

set -euo pipefail

REPO="PaulScotti/parrot"
BIN_NAME="parrot"
if [ -d "/opt/homebrew/bin" ]; then
    DEFAULT_INSTALL_DIR="/opt/homebrew/bin"
else
    DEFAULT_INSTALL_DIR="/usr/local/bin"
fi
INSTALL_DIR="${PARROT_INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
ASSET="parrot-macos-arm64.tar.gz"

red()    { printf "\033[31m%s\033[0m\n" "$*" >&2; }
green()  { printf "\033[32m%s\033[0m\n" "$*"; }
dim()    { printf "\033[2m%s\033[0m\n" "$*"; }

if [ "$(uname -s)" != "Darwin" ]; then
    red "parrot is macOS-only (detected $(uname -s))"
    exit 1
fi

ARCH=$(uname -m)
if [ "$ARCH" != "arm64" ]; then
    red "the prebuilt parrot release requires Apple Silicon (detected $ARCH)"
    exit 1
fi

for cmd in curl tar; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        red "missing dependency: $cmd"
        exit 1
    fi
done

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
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

dim "→ downloading ${ASSET}..."
curl -fsSL "$URL" -o "$TMP/${ASSET}"
dim "→ extracting..."
tar -xzf "$TMP/${ASSET}" -C "$TMP"

if [ ! -f "$TMP/${BIN_NAME}" ]; then
    red "archive did not contain the parrot binary"
    exit 1
fi

chmod +x "$TMP/${BIN_NAME}"
xattr -d com.apple.quarantine "$TMP/${BIN_NAME}" 2>/dev/null || true

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

green "✓ parrot ${TAG} installed at ${INSTALL_DIR}/${BIN_NAME}"
echo
echo "next:"
echo "  save your Azure Speech key at \$HOME/.config/parrot/azure-api-key"
echo "  parrot setup"
echo "  parrot install --launch-at-login --hotkey backslash --azure-resource YOUR_AZURE_RESOURCE"
echo "  parrot"
