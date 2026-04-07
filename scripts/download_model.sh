#!/usr/bin/env bash
# ==============================================================================
# MedLingua — Download Gemma model and push to Android device
# ==============================================================================
#
# This script downloads a Gemma model from HuggingFace and optionally pushes
# it to a connected Android device via adb.
#
# Usage:
#   ./scripts/download_model.sh              # Download + push to device
#   ./scripts/download_model.sh --download   # Download only (no adb push)
#   ./scripts/download_model.sh --push       # Push existing file to device
#
# Prerequisites:
#   1. Install huggingface-cli:  pip install huggingface_hub
#   2. Log in:                   huggingface-cli login
#   3. Accept the Gemma license at https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm
#   4. (For push) Have adb installed and a device connected
#
# Models available:
#   - gemma-4-E4B  (default, ~3.65 GB): litert-community/gemma-4-E4B-it-litert-lm
#   - gemma-4-E2B  (lighter,  ~2.0 GB): litert-community/gemma-4-E2B-it-litert-lm
#
# Environment variables:
#   MODEL_VARIANT   — "e4b" (default) or "1b"
#   HF_TOKEN        — HuggingFace token (optional if already logged in)
# ==============================================================================

set -euo pipefail

# ---- Configuration -----------------------------------------------------------

MODEL_VARIANT="${MODEL_VARIANT:-e4b}"
LOCAL_DIR="$(cd "$(dirname "$0")/.." && pwd)/models"
DEVICE_DIR="/storage/emulated/0/Documents/models"

case "$MODEL_VARIANT" in
  e4b)
    REPO_ID="litert-community/gemma-4-E4B-it-litert-lm"
    MODEL_FILE="gemma-4-E4B-it.litertlm"
    ;;
  e2b)
    REPO_ID="litert-community/gemma-4-E2B-it-litert-lm"
    MODEL_FILE="gemma-4-E2B-it.litertlm"
    ;;
  *)
    echo "Error: Unknown MODEL_VARIANT '$MODEL_VARIANT'. Use 'e4b' or 'e2b'."
    exit 1
    ;;
esac

# ---- Helpers -----------------------------------------------------------------

info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m    $*"; }
err()   { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

check_command() {
  if ! command -v "$1" &>/dev/null; then
    err "'$1' is not installed. $2"
    exit 1
  fi
}

# ---- Parse flags -------------------------------------------------------------

DO_DOWNLOAD=true
DO_PUSH=true

if [[ "${1:-}" == "--download" ]]; then
  DO_PUSH=false
elif [[ "${1:-}" == "--push" ]]; then
  DO_DOWNLOAD=false
fi

# ---- Download ----------------------------------------------------------------

if $DO_DOWNLOAD; then
  check_command "huggingface-cli" "Install with: pip install huggingface_hub"

  mkdir -p "$LOCAL_DIR"
  info "Downloading $MODEL_FILE from $REPO_ID ..."
  info "Destination: $LOCAL_DIR/$MODEL_FILE"

  HF_ARGS=("download" "$REPO_ID" "$MODEL_FILE" "--local-dir" "$LOCAL_DIR")
  if [[ -n "${HF_TOKEN:-}" ]]; then
    HF_ARGS+=("--token" "$HF_TOKEN")
  fi

  huggingface-cli "${HF_ARGS[@]}"

  if [[ -f "$LOCAL_DIR/$MODEL_FILE" ]]; then
    SIZE=$(du -h "$LOCAL_DIR/$MODEL_FILE" | cut -f1)
    ok "Downloaded: $LOCAL_DIR/$MODEL_FILE ($SIZE)"
  else
    err "Download failed — file not found at $LOCAL_DIR/$MODEL_FILE"
    exit 1
  fi
fi

# ---- Push to device ----------------------------------------------------------

if $DO_PUSH; then
  check_command "adb" "Install Android SDK platform-tools"

  if ! adb devices | grep -q "device$"; then
    err "No Android device connected. Connect via USB and enable USB debugging."
    exit 1
  fi

  MODEL_PATH="$LOCAL_DIR/$MODEL_FILE"
  if [[ ! -f "$MODEL_PATH" ]]; then
    err "Model file not found at $MODEL_PATH. Run with --download first."
    exit 1
  fi

  info "Creating directory on device: $DEVICE_DIR"
  adb shell mkdir -p "$DEVICE_DIR"

  info "Pushing model to device (this may take a few minutes) ..."
  adb push "$MODEL_PATH" "$DEVICE_DIR/$MODEL_FILE"

  ok "Model pushed to $DEVICE_DIR/$MODEL_FILE"
  ok "The app will auto-detect the model on next launch."
fi

echo ""
info "Done! Launch MedLingua and the model will load automatically."
