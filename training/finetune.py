"""
MedLingua — Fine-tune Gemma 4 with Unsloth

Fine-tunes Gemma 4 E4B (or Gemma 4 E2B) on the MedLingua medical triage
dataset using Unsloth for 4-bit QLoRA. Produces a LoRA adapter that can be
merged and exported for on-device deployment.

Usage:
    # Fine-tune with defaults (Gemma 4 E4B)
    python training/finetune.py

    # Fine-tune with custom settings
    python training/finetune.py \\
        --model unsloth/gemma-4-E4B-it-unsloth-bnb-4bit \\
        --epochs 3 \\
        --batch-size 4 \\
        --output training/output/medlingua-gemma-4

    # Resume from checkpoint
    python training/finetune.py --resume training/output/medlingua-lora/checkpoint-500

Requirements:
    pip install -r training/requirements.txt
    GPU with >=8GB VRAM (16GB recommended for 4B models)

Notes:
    - Unsloth patches the model for 2x faster training and 60% less memory
    - LoRA rank 32 with alpha 64 balances quality vs. resource usage
    - The dataset must be prepared first: python training/prepare_dataset.py
"""

import argparse
import json
import os
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description="Fine-tune Gemma for MedLingua triage")
    parser.add_argument(
        "--model", type=str, default="unsloth/gemma-4-E4B-it-unsloth-bnb-4bit",
        help="Base model ID from HuggingFace (default: unsloth/gemma-4-E4B-it-unsloth-bnb-4bit)"
    )
    parser.add_argument(
        "--dataset", type=str, default=None,
        help="Path to training JSONL (default: training/data/medlingua_train.jsonl)"
    )
    parser.add_argument("--epochs", type=int, default=3, help="Training epochs (default: 3)")
    parser.add_argument("--batch-size", type=int, default=2, help="Per-device batch size (default: 2)")
    parser.add_argument("--grad-accum", type=int, default=4, help="Gradient accumulation steps (default: 4)")
    parser.add_argument("--lr", type=float, default=2e-4, help="Learning rate (default: 2e-4)")
    parser.add_argument("--max-seq-len", type=int, default=2048, help="Max sequence length (default: 2048)")
    parser.add_argument("--lora-rank", type=int, default=32, help="LoRA rank (default: 32)")
    parser.add_argument("--lora-alpha", type=int, default=64, help="LoRA alpha (default: 64)")
    parser.add_argument(
        "--output", type=str, default=None,
        help="Output directory for LoRA adapter (default: training/output/medlingua-lora)"
    )
    parser.add_argument("--resume", type=str, default=None, help="Resume from checkpoint path")
    parser.add_argument("--push-to-hub", type=str, default=None,
                        help="Push to HuggingFace Hub repo (e.g. your-username/medlingua-gemma-lora)")
    args = parser.parse_args()

    # Resolve default paths relative to training/ directory
    training_dir = Path(__file__).resolve().parent
    if args.dataset is None:
        args.dataset = str(training_dir / "data" / "medlingua_train.jsonl")
    if args.output is None:
        args.output = str(training_dir / "output" / "medlingua-lora")

    # Verify dataset exists
    if not os.path.exists(args.dataset):
        print(f"ERROR: Dataset not found at {args.dataset}")
        print("Run first: python training/prepare_dataset.py")
        return

    print("=" * 60)
    print("MedLingua Fine-Tuning Pipeline")
    print("=" * 60)
    print(f"  Model:          {args.model}")
    print(f"  Dataset:        {args.dataset}")
    print(f"  Epochs:         {args.epochs}")
    print(f"  Batch size:     {args.batch_size} (× {args.grad_accum} grad accum)")
    print(f"  Learning rate:  {args.lr}")
    print(f"  Max seq length: {args.max_seq_len}")
    print(f"  LoRA rank:      {args.lora_rank} (alpha: {args.lora_alpha})")
    print(f"  Output:         {args.output}")
    print("=" * 60)

    # ---- Import heavy dependencies after arg parsing --------------------------
    from unsloth import FastModel
    from datasets import load_dataset
    from trl import SFTTrainer, SFTConfig

    # ---- 1. Load base model with Unsloth -------------------------------------
    print("\n[1/5] Loading base model with Unsloth...")
    model, tokenizer = FastModel.from_pretrained(
        model_name=args.model,
        max_seq_length=args.max_seq_len,
        load_in_4bit=True,
    )

    # ---- 2. Apply LoRA adapters -----------------------------------------------
    print("[2/5] Applying LoRA adapters...")
    model = FastModel.get_peft_model(
        model,
        r=args.lora_rank,
        lora_alpha=args.lora_alpha,
        lora_dropout=0.05,
        target_modules=[
            "q_proj", "k_proj", "v_proj", "o_proj",
            "gate_proj", "up_proj", "down_proj",
        ],
        bias="none",
        use_gradient_checkpointing="unsloth",
        random_state=42,
    )

    trainable_params = sum(p.numel() for p in model.parameters() if p.requires_grad)
    total_params = sum(p.numel() for p in model.parameters())
    print(f"  Trainable: {trainable_params:,} / {total_params:,} "
          f"({trainable_params / total_params * 100:.2f}%)")

    # ---- 3. Load and format dataset -------------------------------------------
    print("[3/5] Loading dataset...")
    dataset = load_dataset("json", data_files=args.dataset, split="train")
    print(f"  Training samples: {len(dataset)}")

    # Apply the chat template
    def format_sample(example):
        messages = example["messages"]
        text = tokenizer.apply_chat_template(
            messages, tokenize=False, add_generation_prompt=False
        )
        return {"text": text}

    dataset = dataset.map(format_sample, remove_columns=dataset.column_names)

    # ---- 4. Configure and run training ----------------------------------------
    print("[4/5] Training...")
    os.makedirs(args.output, exist_ok=True)

    training_args = SFTConfig(
        output_dir=args.output,
        num_train_epochs=args.epochs,
        per_device_train_batch_size=args.batch_size,
        gradient_accumulation_steps=args.grad_accum,
        learning_rate=args.lr,
        lr_scheduler_type="cosine",
        warmup_ratio=0.1,
        weight_decay=0.01,
        fp16=False,
        bf16=True,
        max_seq_length=args.max_seq_len,
        logging_steps=10,
        save_steps=100,
        save_total_limit=3,
        seed=42,
        report_to="none",  # Set to "wandb" if you have W&B configured
        dataset_text_field="text",
        packing=True,  # Unsloth packing for efficiency
    )

    trainer = SFTTrainer(
        model=model,
        tokenizer=tokenizer,
        train_dataset=dataset,
        args=training_args,
    )

    if args.resume:
        print(f"  Resuming from {args.resume}")
        trainer.train(resume_from_checkpoint=args.resume)
    else:
        trainer.train()

    # ---- 5. Save LoRA adapter -------------------------------------------------
    print("[5/5] Saving LoRA adapter...")
    model.save_pretrained(args.output)
    tokenizer.save_pretrained(args.output)
    print(f"  LoRA adapter saved to {args.output}")

    # Save training config for reproducibility
    config = {
        "base_model": args.model,
        "dataset": args.dataset,
        "epochs": args.epochs,
        "batch_size": args.batch_size,
        "grad_accum": args.grad_accum,
        "lr": args.lr,
        "max_seq_len": args.max_seq_len,
        "lora_rank": args.lora_rank,
        "lora_alpha": args.lora_alpha,
        "trainable_params": trainable_params,
        "total_params": total_params,
        "training_samples": len(dataset),
    }
    config_path = os.path.join(args.output, "medlingua_training_config.json")
    with open(config_path, "w") as f:
        json.dump(config, f, indent=2)
    print(f"  Config saved to {config_path}")

    # Push to Hub if requested
    if args.push_to_hub:
        print(f"  Pushing to Hub: {args.push_to_hub}")
        model.push_to_hub(args.push_to_hub)
        tokenizer.push_to_hub(args.push_to_hub)
        print("  Done!")

    print("\n" + "=" * 60)
    print("Fine-tuning complete!")
    print(f"LoRA adapter: {args.output}")
    print("\nNext steps:")
    print("  1. Export: python training/export_model.py")
    print("  2. Push:   ./scripts/download_model.sh --push")
    print("=" * 60)


if __name__ == "__main__":
    main()
