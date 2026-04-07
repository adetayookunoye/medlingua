---
license: apache-2.0
language:
  - en
  - fr
  - es
  - sw
  - ha
  - yo
  - hi
  - bn
  - pt
  - ar
  - pcm
  - tw
library_name: transformers
tags:
  - gemma4
  - medical
  - triage
  - multilingual
  - qlora
  - unsloth
  - who-imci
  - healthcare
  - community-health
base_model: google/gemma-4-E4B-it
datasets:
  - medmcqa
  - custom
pipeline_tag: text-generation
---

# MedLingua — Fine-Tuned Gemma 4 E4B for Medical Triage

A QLoRA fine-tuned version of [google/gemma-4-E4B-it](https://huggingface.co/google/gemma-4-E4B-it) optimized for medical triage in low-resource healthcare settings. Designed for use by Community Health Workers following WHO IMCI protocols.

## Model Details

| Property | Value |
|----------|-------|
| **Base Model** | google/gemma-4-E4B-it (8B params, 4.5B effective) |
| **Fine-Tuning Method** | 4-bit QLoRA via Unsloth |
| **LoRA Rank** | 16 |
| **LoRA Alpha** | 16 |
| **Target Modules** | q_proj, k_proj, v_proj, o_proj, gate_proj, up_proj, down_proj |
| **Languages** | 12 (en, fr, es, sw, ha, yo, hi, bn, pt, ar, pcm, tw) |
| **Task** | Medical severity triage with structured JSON output |
| **License** | Apache 2.0 |

## Intended Use

This model is designed for **on-device medical triage assistance** for Community Health Workers in low-resource settings. It classifies patient presentations into four severity levels (emergency, urgent, standard, routine) following WHO IMCI protocols.

### Primary Use Case
- Community Health Workers performing initial patient assessments in the field
- Offline environments with no internet connectivity
- Multilingual communities requiring triage in local languages

### Out-of-Scope Use
- **NOT a replacement for professional medical diagnosis** — this is a decision support tool
- Not suitable for complex specialist referral decisions
- Not validated for adult emergency medicine (optimized for pediatric IMCI)

## Training Data

| Source | Purpose | Size |
|--------|---------|------|
| WHO IMCI Protocols | Evidence-based triage decision trees converted to conversational format | ~2K examples |
| Multilingual Translations | Medical terminology and symptom descriptions across 12 languages | ~5K examples |
| MedMCQA | Medical knowledge grounding from AIIMS/NEET exam questions | Subset |
| HealthCareMagic | Doctor-patient dialogue for conversational medical reasoning | Subset |

## Training Configuration

```python
# QLoRA Configuration
load_in_4bit = True
lora_rank = 16
lora_alpha = 16
lora_dropout = 0
target_modules = ["q_proj", "k_proj", "v_proj", "o_proj",
                  "gate_proj", "up_proj", "down_proj"]

# Training Hyperparameters
learning_rate = 2e-4
num_train_epochs = 3
per_device_train_batch_size = 2
gradient_accumulation_steps = 4
max_seq_length = 2048
warmup_steps = 5
optimizer = "adamw_8bit"
packing = True
```

**Hardware**: NVIDIA A100-SXM4-80GB on UGA Sapelo2 HPC cluster

## How to Use

### With Unsloth (Recommended for inference)

```python
from unsloth import FastModel

model, tokenizer = FastModel.from_pretrained(
    model_name="YOUR_USERNAME/medlingua-gemma4-e4b",
    max_seq_length=2048,
    load_in_4bit=True,
)

messages = [
    {"role": "system", "content": "You are MedLingua, a medical triage assistant following WHO IMCI protocols. Respond with JSON containing: severity, diagnosis, recommendation, danger_signs, confidence."},
    {"role": "user", "content": "Child 2 years, high fever 39.5°C for 3 days, fast breathing, refuses to drink, lethargic."},
]

prompt = tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
inputs = tokenizer(prompt, return_tensors="pt").to(model.device)
outputs = model.generate(**inputs, max_new_tokens=512, temperature=0.3)
print(tokenizer.decode(outputs[0][inputs["input_ids"].shape[-1]:], skip_special_tokens=True))
```

### Expected Output Format

```json
{
  "severity": "emergency",
  "diagnosis": "Possible severe pneumonia with dehydration",
  "recommendation": "Start first dose of antibiotics. Begin ORS rehydration. Refer to hospital immediately.",
  "danger_signs": ["fast breathing", "refuses to drink", "lethargic", "high fever >3 days"],
  "confidence": 0.92
}
```

## Benchmark Results

Run `python training/benchmark.py` for full evaluation. Metrics include:

- **Severity Classification Accuracy** — Across emergency/urgent/standard/routine
- **JSON Compliance Rate** — Structured output adherence
- **IMCI Keyword Adherence** — Protocol-appropriate medical terminology
- **Multilingual Performance** — Test cases in English, French, Spanish, Swahili
- **Inference Latency** — Average response time per assessment

## Limitations

- **Not a medical device** — Not FDA/CE cleared. For decision support only.
- **Training data bias** — Primarily trained on pediatric IMCI; adult presentations may be less accurate.
- **Language quality** — Performance may vary across languages; English and French have the most training data.
- **Hallucination risk** — Like all LLMs, may generate plausible-sounding but incorrect medical advice.
- **No real-time updates** — Model knowledge is frozen at training time.

## Ethical Considerations

- Model outputs should always be reviewed by qualified health personnel when possible
- Designed to assist, not replace, human clinical judgment
- Patient data processed on-device; no data transmitted to external servers
- Model should be validated with local clinical guidelines before deployment in new regions

## Citation

```bibtex
@misc{medlingua2025,
  title={MedLingua: Offline Multilingual Medical Triage Powered by Gemma 4},
  author={MedLingua Team},
  year={2025},
  howpublished={Gemma 4 Good Hackathon},
}
```

## Acknowledgments

- Google — Gemma 4 model family
- WHO — IMCI clinical protocols
- Unsloth — Efficient QLoRA fine-tuning
- University of Georgia — Sapelo2 HPC cluster
