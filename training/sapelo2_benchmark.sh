#!/bin/bash
#SBATCH --job-name=medlingua-bench
#SBATCH --partition=gpu_p
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --gres=gpu:A100:1
#SBATCH --mem=64G
#SBATCH --time=00:30:00
#SBATCH --output=training/logs/bench_%j.out
#SBATCH --error=training/logs/bench_%j.err
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=aoo29179@uga.edu

set -euo pipefail

PROJECT_DIR="${SLURM_SUBMIT_DIR:-$HOME/Gemma4}"
VENV_DIR="${TMPDIR:-/tmp}/medlingua-venv"

cd "$PROJECT_DIR"

echo "=========================================="
echo "MedLingua Benchmark"
echo "Job ID:    $SLURM_JOB_ID"
echo "Node:      $SLURMD_NODENAME"
echo "Date:      $(date)"
echo "=========================================="

module purge
module load Python/3.11.5-GCCcore-13.2.0
module load CUDA/12.1.1

echo "Python: $(python3 --version)"
nvidia-smi

# Create venv and install deps
echo ""
echo "[1/3] Setting up environment..."
rm -rf "$VENV_DIR" 2>/dev/null || true
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
python -m pip install --upgrade pip --quiet
python -m pip install unsloth --quiet
python -m pip install datasets huggingface_hub sentencepiece protobuf --quiet
echo "Packages installed."

# Benchmark
echo ""
echo "[2/3] Running benchmark..."
python training/benchmark.py \
    --model training/output/medlingua-lora \
    --output training/output/benchmark_results.json

# Summary
echo ""
echo "[3/3] Done!"
echo "=========================================="
echo "Results saved to training/output/benchmark_results.json"
cat training/output/benchmark_results.json
echo ""
echo "Job finished at $(date)"
