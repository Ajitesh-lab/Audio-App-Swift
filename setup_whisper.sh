#!/usr/bin/env bash
set -euo pipefail

# setup_whisper.sh
# Creates a Python venv at ./venv and installs Whisper + WhisperX.
# By default installs CPU-only torch. If you have CUDA and want GPU, set USE_CUDA=1 and provide CUDA version.

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="$ROOT_DIR/.venv"

echo "Setting up Whisper environment in $VENV_DIR"

if [ ! -d "$VENV_DIR" ]; then
  python3 -m venv "$VENV_DIR"
fi

# shellcheck source=/dev/null
source "$VENV_DIR/bin/activate"

pip install --upgrade pip setuptools wheel

echo "Installing Python requirements..."

# Detect CUDA (optional)
USE_CUDA=${USE_CUDA:-0}
if [ "$USE_CUDA" != "0" ]; then
  echo "CUDA requested. Installing GPU-enabled torch. Ensure CUDA toolkit/drivers are installed."
  # This attempts to install a compatible torch; adjust if needed for your CUDA version
  pip install --upgrade --index-url https://download.pytorch.org/whl/cu118 torch torchvision torchaudio
else
  echo "Installing CPU-only torch and dependencies"
  pip install --upgrade --index-url https://download.pytorch.org/whl/cpu torch torchvision torchaudio
fi

pip install -r "$ROOT_DIR/requirements.txt"

echo "Note: system `ffmpeg` binary is required. On Ubuntu: sudo apt install ffmpeg ; Mac (Homebrew): brew install ffmpeg"

echo "Whisper environment ready. Activate with: source $VENV_DIR/bin/activate"
