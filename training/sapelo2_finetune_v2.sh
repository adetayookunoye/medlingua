#!/bin/bash
#SBATCH --job-name=medlingua-finetune-v2
#SBATCH --partition=gpu_p
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --gres=gpu:A100:1
#SBATCH --mem=64G
#SBATCH --time=02:00:00
#SBATCH --output=training/logs/finetune_v2_%j.out
#SBATCH --error=training/logs/finetune_v2_%j.err
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=aoo29179@uga.edu

# ==============================================================================
# MedLingua v2 — Fine-Tune with routine/standard boost data
# ==============================================================================
# Changes from v1:
#   - Adds 84 routine/standard examples to balance class distribution
#   - Saves to medlingua-lora-v2 to preserve v1 results
#   - Chains benchmark automatically after training
# ==============================================================================

set -euo pipefail

echo "=========================================="
echo "MedLingua Fine-Tuning v2 (routine boost)"
echo "Job ID:    $SLURM_JOB_ID"
echo "Node:      $SLURMD_NODENAME"
echo "GPU:       $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo 'checking...')"
echo "Date:      $(date)"
echo "=========================================="

PROJECT_DIR="${SLURM_SUBMIT_DIR:-$HOME/Gemma4}"
VENV_DIR="${TMPDIR:-/tmp}/medlingua-venv"
LOG_DIR="$PROJECT_DIR/training/logs"

cd "$PROJECT_DIR"
mkdir -p "$LOG_DIR"

# ---- Load modules ------------------------------------------------------------
module purge
module load Python/3.11.5-GCCcore-13.2.0
module load CUDA/12.1.1
module load CMake/3.27.6-GCCcore-13.2.0
module load cURL/8.3.0-GCCcore-13.2.0

echo "Python: $(python3 --version)"
echo "CUDA:   $(nvcc --version | grep 'release' || echo 'loaded via module')"
nvidia-smi

# ---- Set up virtual environment ----------------------------------------------
echo ""
echo "[1/6] Creating virtual environment..."
rm -rf "$VENV_DIR" 2>/dev/null || true
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
echo "Using Python: $(which python)"

# ---- Install dependencies ----------------------------------------------------
echo ""
echo "[2/6] Installing dependencies..."
python -m pip install --upgrade pip --quiet
python -m pip install unsloth --quiet
python -m pip install datasets huggingface_hub sentencepiece protobuf --quiet

echo "Packages installed."
echo "  torch: $(python -c 'import torch; print(torch.__version__)' 2>/dev/null)"
echo "  CUDA available: $(python -c 'import torch; print(torch.cuda.is_available())' 2>/dev/null)"

# ---- Prepare dataset (now includes routine_standard_boost.jsonl) -------------
echo ""
echo "[3/6] Preparing dataset (with routine/standard boost)..."
python training/prepare_dataset.py --max-medmcqa 3000 --max-healthcaremagic 2000

# ---- Fine-tune ---------------------------------------------------------------
echo ""
echo "[4/6] Fine-tuning..."
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
    --output training/output/medlingua-lora-v2

TRAIN_END=$(date +%s)
TRAIN_MINS=$(( (TRAIN_END - TRAIN_START) / 60 ))
echo "Training time: ${TRAIN_MINS} minutes"

# ---- Benchmark ---------------------------------------------------------------
echo ""
echo "[5/6] Running benchmark..."
python training/benchmark.py \
    --model training/output/medlingua-lora-v2 \
    --output training/output/benchmark_results_v2.json

# ---- Export ------------------------------------------------------------------
echo ""
echo "[6/6] Exporting model..."
python training/export_model.py \
    --lora-path training/output/medlingua-lora-v2 \
    --output-dir training/output/medlingua-exported-v2 \
    --quantize int4

# ---- Summary -----------------------------------------------------------------
echo ""
echo "=========================================="
echo "DONE! v2 training complete"
echo "=========================================="
echo "LoRA adapter:     training/output/medlingua-lora-v2/"
echo "Benchmark:        training/output/benchmark_results_v2.json"
echo "Exported model:   training/output/medlingua-exported-v2/"
echo ""
echo "Comparing v1 vs v2 accuracy:"
V1_ACC=$(python -c "import json; d=json.load(open('training/output/benchmark_results.json')); print(f\"{d['metrics']['severity_accuracy']*100:.1f}%\")" 2>/dev/null || echo "N/A")
V2_ACC=$(python -c "import json; d=json.load(open('training/output/benchmark_results_v2.json')); print(f\"{d['metrics']['severity_accuracy']*100:.1f}%\")" 2>/dev/null || echo "N/A")
echo "  v1: $V1_ACC"
echo "  v2: $V2_ACC"
echo ""
echo "To copy back:"
echo "  scp -r sapelo2:~/Gemma4/training/output/medlingua-lora-v2 ."
echo ""
echo "Job finished at $(date)"
