"""Upload MedLingua LoRA adapter to HuggingFace Hub."""

import os
from huggingface_hub import HfApi, create_repo

REPO_ID = "adeto/medlingua-gemma4-lora"
ADAPTER_DIR = os.path.expanduser("~/Gemma4/training/output/medlingua-lora")

# Files to upload (skip checkpoints)
INCLUDE = [
    "adapter_config.json",
    "adapter_model.safetensors",
    "chat_template.jinja",
    "medlingua_training_config.json",
    "processor_config.json",
    "tokenizer.json",
    "tokenizer_config.json",
    "README.md",
]

def main():
    token = os.environ.get("HF_TOKEN")
    if not token:
        raise ValueError("Set HF_TOKEN environment variable")

    api = HfApi(token=token)

    # Create repo if it doesn't exist
    try:
        create_repo(REPO_ID, token=token, repo_type="model", exist_ok=True)
        print(f"Repository {REPO_ID} ready")
    except Exception as e:
        print(f"Repo creation: {e}")

    # Upload each file
    for fname in INCLUDE:
        fpath = os.path.join(ADAPTER_DIR, fname)
        if os.path.exists(fpath):
            size_mb = os.path.getsize(fpath) / (1024 * 1024)
            print(f"Uploading {fname} ({size_mb:.1f} MB)...")
            api.upload_file(
                path_or_fileobj=fpath,
                path_in_repo=fname,
                repo_id=REPO_ID,
                repo_type="model",
            )
            print(f"  ✓ {fname}")
        else:
            print(f"  ✗ {fname} not found, skipping")

    print(f"\nDone! https://huggingface.co/{REPO_ID}")

if __name__ == "__main__":
    main()
