#!/bin/bash
#SBATCH --job-name=medlingua-export
#SBATCH --partition=gpu_p
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --gres=gpu:A100:1
#SBATCH --mem=64G
#SBATCH --time=00:30:00
#SBATCH --output=training/logs/export_%j.out
#SBATCH --error=training/logs/export_%j.err
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=aoo29179@uga.edu

set -euo pipefail

PROJECT_DIR="${SLURM_SUBMIT_DIR:-$HOME/Gemma4}"
VENV_DIR="${TMPDIR:-/tmp}/medlingua-venv"

cd "$PROJECT_DIR"

echo "=========================================="
echo "MedLingua Model Export"
echo "Job ID:    $SLURM_JOB_ID"
echo "Node:      $SLURMD_NODENAME"
echo "Date:      $(date)"
echo "=========================================="

# Load modules including CMake and cURL for llama.cpp GGUF build
module purge
module load Python/3.11.5-GCCcore-13.2.0
module load CUDA/12.1.1
module load CMake/3.27.6-GCCcore-13.2.0
module load cURL/8.3.0-GCCcore-13.2.0

echo "Python: $(python3 --version)"
echo "CMake:  $(cmake --version | head -1)"
nvidia-smi

# Create venv and install deps
echo ""
echo "[1/3] Setting up environment..."
# Remove stale venv from previous jobs on the same node
rm -rf "$VENV_DIR" 2>/dev/null || true
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
python -m pip install --upgrade pip --quiet
python -m pip install unsloth --quiet
python -m pip install datasets huggingface_hub sentencepiece protobuf --quiet
echo "Packages installed."

# Export
echo ""
echo "[2/3] Exporting model..."
python training/export_model.py \
    --lora-path training/output/medlingua-lora \
    --output-dir training/output/medlingua-exported \
    --quantize int4 \
    --skip-gguf

# Summary
echo ""
echo "[3/3] Done!"
echo "=========================================="
echo "Exported files:"
find training/output/medlingua-exported -type f -exec ls -lh {} \;
echo ""
echo "To copy back: scp -r sapelo2:~/Gemma4/training/output/medlingua-exported ."
echo "Job finished at $(date)"
