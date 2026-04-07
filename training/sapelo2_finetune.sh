#!/bin/bash
#SBATCH --job-name=medlingua-finetune
#SBATCH --partition=gpu_p
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --gres=gpu:A100:1
#SBATCH --mem=64G
#SBATCH --time=02:00:00
#SBATCH --output=training/logs/finetune_%j.out
#SBATCH --error=training/logs/finetune_%j.err
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=aoo29179@uga.edu

# ==============================================================================
# MedLingua — Fine-Tune Gemma on Sapelo2 (GACRC)
# ==============================================================================
#
# Usage:
#   ssh sapelo2
#   cd /home/$USER/Gemma4   (or wherever you cloned the repo)
#   sbatch training/sapelo2_finetune.sh
#
# Monitor:
#   squeue -u $USER
#   tail -f training/logs/finetune_<JOBID>.out
#
# Prerequisites:
#   1. Transfer the project to Sapelo2:
#      scp -r "/home/adetayo/Documents/CSCI Forms/Gemma4" sapelo2:~/Gemma4
#   2. Edit --mail-user above with your UGA email
# ==============================================================================

set -euo pipefail

echo "=========================================="
echo "MedLingua Fine-Tuning on Sapelo2"
echo "Job ID:    $SLURM_JOB_ID"
echo "Node:      $SLURMD_NODENAME"
echo "GPU:       $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo 'checking...')"
echo "Date:      $(date)"
echo "=========================================="

# ---- Paths -------------------------------------------------------------------
PROJECT_DIR="${SLURM_SUBMIT_DIR:-$HOME/Gemma4}"
VENV_DIR="$PROJECT_DIR/training/.venv"
LOG_DIR="$PROJECT_DIR/training/logs"

cd "$PROJECT_DIR"
mkdir -p "$LOG_DIR"

# ---- Load modules ------------------------------------------------------------
module purge
module load Python/3.11.5-GCCcore-13.2.0
module load CUDA/12.1.1

echo "Python: $(python3 --version)"
echo "CUDA:   $(nvcc --version | grep 'release' || echo 'loaded via module')"
nvidia-smi

# ---- Set up virtual environment ----------------------------------------------
# Use --clear to force a clean venv (avoids NFS rm -rf issues)
if [ ! -f "$VENV_DIR/bin/activate" ]; then
    echo ""
    echo "[1/5] Creating virtual environment..."
    python3 -m venv --clear "$VENV_DIR"
else
    echo ""
    echo "[1/5] Reusing existing virtual environment..."
fi

source "$VENV_DIR/bin/activate"
echo "Using Python: $(which python)"

# ---- Install dependencies ----------------------------------------------------
echo ""
echo "[2/5] Installing dependencies..."
pip install --upgrade pip --quiet

# Install PyTorch 2.5.1 + torchvision for CUDA 12.1
# Required by unsloth 2026.x which uses torch._inductor.config
pip install "torch==2.5.1" "torchvision==0.20.1" --index-url https://download.pytorch.org/whl/cu121 --quiet

# Fix CUDA library version mismatch (cusparse needs matching nvjitlink)
pip install nvidia-nvjitlink-cu12 --upgrade --quiet

# Install Unsloth and training deps
pip install "unsloth[cu121-torch250]" --quiet
pip install datasets huggingface_hub sentencepiece protobuf --quiet

echo "Packages installed."

# ---- Prepare dataset ---------------------------------------------------------
echo ""
echo "[3/5] Preparing dataset..."
python training/prepare_dataset.py --max-medmcqa 3000 --max-healthcaremagic 2000

# ---- Fine-tune ---------------------------------------------------------------
echo ""
echo "[4/5] Fine-tuning..."
TRAIN_START=$(date +%s)

python training/finetune.py \
    --model "unsloth/gemma-4-E4B-it-unsloth-bnb-4bit" \
    --epochs 3 \
    --batch-size 4 \
    --grad-accum 2 \
    --lr 2e-4 \
    --max-seq-len 2048 \
    --lora-rank 32 \
    --lora-alpha 64 \
    --output training/output/medlingua-lora

TRAIN_END=$(date +%s)
TRAIN_MINS=$(( (TRAIN_END - TRAIN_START) / 60 ))
echo "Training time: ${TRAIN_MINS} minutes"

# ---- Export ------------------------------------------------------------------
echo ""
echo "[5/5] Exporting model..."
python training/export_model.py \
    --lora-path training/output/medlingua-lora \
    --output-dir training/output/medlingua-exported \
    --quantize int4

# ---- Summary -----------------------------------------------------------------
echo ""
echo "=========================================="
echo "DONE!"
echo "=========================================="
echo "LoRA adapter: training/output/medlingua-lora/"
echo "Exported model: training/output/medlingua-exported/"
echo ""
echo "Exported files:"
find training/output/medlingua-exported -type f -exec ls -lh {} \;
echo ""
echo "To copy back to your local machine:"
echo "  scp -r sapelo2:~/Gemma4/training/output/medlingua-exported ."
echo ""
echo "Job finished at $(date)"
