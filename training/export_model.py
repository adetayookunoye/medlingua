"""
MedLingua — Export Fine-Tuned Model for On-Device Deployment

Merges the LoRA adapter with the base model and exports to formats compatible
with MediaPipe LLM Inference API for on-device deployment.

Export pipeline:
    1. Merge LoRA adapter with base model (full precision)
    2. Quantize to int8 or int4 for mobile
    3. Convert to MediaPipe-compatible format (.task or .bin)

Usage:
    # Default: merge + quantize + export
    python training/export_model.py

    # Custom paths
    python training/export_model.py \\
        --lora-path training/output/medlingua-lora \\
        --output-dir training/output/medlingua-exported \\
        --quantize int4

    # Export LoRA adapter only (for use with base model on device)
    python training/export_model.py --lora-only

Requirements:
    pip install -r training/requirements.txt
    (Also needs: mediapipe, ai-edge-litert for .task conversion)
"""

import argparse
import json
import os
import shutil
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description="Export fine-tuned Gemma for on-device deployment")
    parser.add_argument(
        "--base-model", type=str, default=None,
        help="Base model ID (reads from training config if not specified)"
    )
    parser.add_argument(
        "--lora-path", type=str, default=None,
        help="Path to LoRA adapter (default: training/output/medlingua-lora)"
    )
    parser.add_argument(
        "--output-dir", type=str, default=None,
        help="Output directory (default: training/output/medlingua-exported)"
    )
    parser.add_argument(
        "--quantize", type=str, choices=["int4", "int8", "fp16", "none"], default="int4",
        help="Quantization level (default: int4)"
    )
    parser.add_argument(
        "--lora-only", action="store_true",
        help="Export only the LoRA adapter file (no merge)"
    )
    parser.add_argument(
        "--push-to-hub", type=str, default=None,
        help="Push merged model to HuggingFace Hub"
    )
    args = parser.parse_args()

    training_dir = Path(__file__).resolve().parent
    if args.lora_path is None:
        args.lora_path = str(training_dir / "output" / "medlingua-lora")
    if args.output_dir is None:
        args.output_dir = str(training_dir / "output" / "medlingua-exported")

    # Load training config to get base model
    config_path = os.path.join(args.lora_path, "medlingua_training_config.json")
    if args.base_model is None:
        if os.path.exists(config_path):
            with open(config_path) as f:
                config = json.load(f)
            args.base_model = config.get("base_model", "unsloth/gemma-4-E4B-it-unsloth-bnb-4bit")
        else:
            args.base_model = "unsloth/gemma-4-E4B-it-unsloth-bnb-4bit"

    print("=" * 60)
    print("MedLingua Model Export")
    print("=" * 60)
    print(f"  Base model:   {args.base_model}")
    print(f"  LoRA adapter: {args.lora_path}")
    print(f"  Output:       {args.output_dir}")
    print(f"  Quantization: {args.quantize}")
    print(f"  LoRA only:    {args.lora_only}")
    print("=" * 60)

    if not os.path.exists(args.lora_path):
        print(f"ERROR: LoRA adapter not found at {args.lora_path}")
        print("Run first: python training/finetune.py")
        return

    os.makedirs(args.output_dir, exist_ok=True)

    if args.lora_only:
        _export_lora_only(args)
    else:
        _export_merged(args)


def _export_lora_only(args):
    """Export just the LoRA adapter for on-device LoRA loading."""
    print("\n[1/1] Exporting LoRA adapter...")

    # Copy LoRA adapter files
    lora_output = os.path.join(args.output_dir, "lora")
    os.makedirs(lora_output, exist_ok=True)

    important_files = [
        "adapter_config.json",
        "adapter_model.safetensors",
        "adapter_model.bin",
        "medlingua_training_config.json",
    ]

    copied = 0
    for fn in important_files:
        src = os.path.join(args.lora_path, fn)
        if os.path.exists(src):
            shutil.copy2(src, os.path.join(lora_output, fn))
            copied += 1

    print(f"  Copied {copied} adapter files to {lora_output}")
    print("\nTo use on-device with MediaPipe LLM Inference:")
    print("  1. Push the base model to the device")
    print("  2. Push the lora/ folder to the device")
    print("  3. Set loraPath in ModelConfig to the adapter path")
    print("=" * 60)


def _export_merged(args):
    """Merge LoRA, quantize, and export for on-device deployment."""
    from unsloth import FastModel

    # Step 1: Load base model + LoRA adapter
    print("\n[1/4] Loading model with LoRA adapter...")
    model, tokenizer = FastModel.from_pretrained(
        model_name=args.lora_path,
        max_seq_length=2048,
        load_in_4bit=True,
    )

    # Step 2: Save merged model in GGUF format (compatible with MediaPipe)
    print("[2/4] Merging and quantizing...")

    quant_method_map = {
        "int4": "q4_k_m",
        "int8": "q8_0",
        "fp16": "f16",
        "none": "f32",
    }
    quant_method = quant_method_map[args.quantize]

    merged_dir = os.path.join(args.output_dir, "merged")
    os.makedirs(merged_dir, exist_ok=True)

    # Unsloth can save directly to GGUF
    print(f"  Saving as GGUF ({quant_method})...")
    model.save_pretrained_gguf(
        merged_dir,
        tokenizer,
        quantization_method=quant_method,
    )

    # Find the generated GGUF file
    gguf_files = list(Path(merged_dir).glob("*.gguf"))
    if gguf_files:
        gguf_path = gguf_files[0]
        size_mb = gguf_path.stat().st_size / (1024 * 1024)
        print(f"  GGUF model: {gguf_path.name} ({size_mb:.0f} MB)")
    else:
        print("  WARNING: No GGUF file generated")

    # Step 3: Also save in safetensors for HF compatibility
    print("[3/4] Saving HuggingFace format...")
    hf_dir = os.path.join(args.output_dir, "hf")
    model.save_pretrained_merged(hf_dir, tokenizer, save_method="merged_16bit")
    print(f"  HuggingFace model saved to {hf_dir}")

    # Step 4: Generate deployment instructions
    print("[4/4] Generating deployment files...")

    deployment_info = {
        "base_model": args.base_model,
        "quantization": args.quantize,
        "gguf_file": str(gguf_files[0].name) if gguf_files else None,
        "deployment_steps": [
            "1. Copy the GGUF or .task file to your Android device:",
            "   adb push <model_file> /storage/emulated/0/Documents/models/",
            "2. Or use the MediaPipe Model Maker to convert HF format to .task:",
            "   python -m mediapipe.tasks.genai.converter --input_dir hf/ --output_file model.task",
            "3. Launch MedLingua — the model will be auto-detected",
        ],
        "lora_deployment": [
            "Alternatively, deploy the base model + LoRA adapter separately:",
            "1. Push base model to device",
            "2. Push lora/adapter_model.safetensors to device",
            "3. App loads base model with LoRA at runtime (smaller download)",
        ],
    }

    info_path = os.path.join(args.output_dir, "deployment_info.json")
    with open(info_path, "w") as f:
        json.dump(deployment_info, f, indent=2)

    # Push to Hub if requested
    if args.push_to_hub:
        print(f"\n  Pushing to Hub: {args.push_to_hub}")
        model.push_to_hub_merged(
            args.push_to_hub, tokenizer,
            save_method="merged_16bit",
        )
        # Also push GGUF
        if gguf_files:
            model.push_to_hub_gguf(
                args.push_to_hub, tokenizer,
                quantization_method=quant_method,
            )
        print("  Pushed to Hub!")

    print("\n" + "=" * 60)
    print("Export complete!")
    print(f"  GGUF model:  {merged_dir}/")
    print(f"  HF model:    {hf_dir}/")
    print(f"  Deploy info: {info_path}")
    print("\nNext steps:")
    print("  adb push <model_file> /storage/emulated/0/Documents/models/")
    print("  # Or use: ./scripts/download_model.sh --push")
    print("=" * 60)


if __name__ == "__main__":
    main()
