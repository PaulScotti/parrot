#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PARROT_ROOT=${PARROT_HOME:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}
RUNTIME_DIR="$PARROT_ROOT/runtime/qwen-mlx"
VENV_DIR="$RUNTIME_DIR/venv"
PYTHON_INSTALL_DIR="$RUNTIME_DIR/python"
MODEL_CACHE="$PARROT_ROOT/models/huggingface"
UV_CACHE_DIR="$PARROT_ROOT/runtime/caches/uv"
MODEL_ID="mlx-community/Qwen3-ASR-1.7B-8bit"

if [ "$(uname -s)" != "Darwin" ] || [ "$(uname -m)" != "arm64" ]; then
    echo "Qwen MLX requires an Apple Silicon Mac." >&2
    exit 1
fi

if ! command -v uv >/dev/null 2>&1; then
    echo "uv is required. Install it with: brew install uv" >&2
    exit 1
fi

mkdir -p "$RUNTIME_DIR" "$MODEL_CACHE" "$UV_CACHE_DIR"
echo "Preparing project-local Python 3.12..."
UV_CACHE_DIR="$UV_CACHE_DIR" uv python install \
    --install-dir "$PYTHON_INSTALL_DIR" \
    --no-bin \
    --no-progress \
    3.12
PYTHON_BIN=$(UV_PYTHON_INSTALL_DIR="$PYTHON_INSTALL_DIR" \
    UV_CACHE_DIR="$UV_CACHE_DIR" uv python find --managed-python 3.12)

CURRENT_BASE=""
if [ -x "$VENV_DIR/bin/python" ]; then
    CURRENT_BASE=$("$VENV_DIR/bin/python" -c 'import sys; print(sys.base_prefix)' 2>/dev/null || true)
fi
case "$CURRENT_BASE" in
    "$PYTHON_INSTALL_DIR"/*) ;;
    *) UV_CACHE_DIR="$UV_CACHE_DIR" uv venv --clear --python "$PYTHON_BIN" "$VENV_DIR" ;;
esac

echo "Installing the pinned MLX Audio runtime..."
UV_CACHE_DIR="$UV_CACHE_DIR" uv pip sync \
    --link-mode copy \
    --quiet \
    --python "$VENV_DIR/bin/python" \
    "$SCRIPT_DIR/qwen-mlx-requirements.lock"

echo "Downloading and loading $MODEL_ID. This is about 2.47 GB."
HF_HOME="$MODEL_CACHE" \
HF_HUB_CACHE="$MODEL_CACHE/hub" \
XDG_CACHE_HOME="$PARROT_ROOT/runtime/caches" \
HF_HUB_DISABLE_PROGRESS_BARS=1 \
PYTHONUNBUFFERED=1 \
"$VENV_DIR/bin/python" "$SCRIPT_DIR/qwen_mlx_worker.py" \
    --model "$MODEL_ID" --check

echo "Qwen3-ASR 1.7B is ready."
