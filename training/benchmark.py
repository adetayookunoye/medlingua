"""
MedLingua — Benchmark Fine-Tuned Gemma 4 on Medical Triage

Evaluates the fine-tuned model on a held-out medical triage test set and
produces benchmarks for publication alongside the model weights.

Metrics:
    - Severity classification accuracy (emergency/urgent/standard/routine)
    - JSON function-call compliance rate
    - IMCI protocol adherence (keyword-based heuristic)
    - Average inference latency

Usage:
    python training/benchmark.py
    python training/benchmark.py --model training/output/medlingua-lora --samples 200
"""

import argparse
import json
import os
import time
from pathlib import Path


# ---- Test cases for medical triage evaluation --------------------------------

TRIAGE_TEST_CASES = [
    {
        "symptoms": "Child with high fever 40°C for 3 days, neck stiffness, vomiting, refuses to drink",
        "expected_severity": "emergency",
        "expected_keywords": ["meningitis", "fever", "refer", "hospital"],
        "category": "critical_illness",
    },
    {
        "symptoms": "Infant 6 months, severe diarrhea for 2 days, sunken eyes, dry mouth, lethargic",
        "expected_severity": "emergency",
        "expected_keywords": ["dehydration", "ORS", "refer", "fluid"],
        "category": "dehydration",
    },
    {
        "symptoms": "Child 3 years, fast breathing 55 breaths/min, chest indrawing, cough for 5 days",
        "expected_severity": "emergency",
        "expected_keywords": ["pneumonia", "breathing", "antibiotic", "refer"],
        "category": "respiratory",
    },
    {
        "symptoms": "Child 2 years, convulsions lasting 5 minutes, high fever, unconscious",
        "expected_severity": "emergency",
        "expected_keywords": ["convulsion", "seizure", "emergency", "refer"],
        "category": "neurological",
    },
    {
        "symptoms": "Child with fever 38.5°C, rash on trunk spreading to limbs, runny nose",
        "expected_severity": "urgent",
        "expected_keywords": ["measles", "rash", "isolate", "vitamin"],
        "category": "infectious",
    },
    {
        "symptoms": "Infant 9 months, ear pain, yellow discharge from ear for 3 days, mild fever",
        "expected_severity": "urgent",
        "expected_keywords": ["ear", "infection", "otitis", "antibiotic"],
        "category": "ENT",
    },
    {
        "symptoms": "Child 4 years, bloody diarrhea with mucus, abdominal cramps, mild dehydration",
        "expected_severity": "urgent",
        "expected_keywords": ["dysentery", "blood", "stool", "refer"],
        "category": "GI",
    },
    {
        "symptoms": "Child 18 months, persistent cough for 3 weeks, weight loss, night sweats",
        "expected_severity": "urgent",
        "expected_keywords": ["tuberculosis", "TB", "cough", "refer", "test"],
        "category": "respiratory",
    },
    {
        "symptoms": "Child 5 years, mild cough for 2 days, runny nose, no fever, eating well",
        "expected_severity": "routine",
        "expected_keywords": ["cold", "cough", "fluid", "rest", "follow"],
        "category": "respiratory",
    },
    {
        "symptoms": "Child 3 years, small wound on knee from fall, no bleeding, clean edges",
        "expected_severity": "routine",
        "expected_keywords": ["wound", "clean", "bandage", "tetanus"],
        "category": "injury",
    },
    {
        "symptoms": "Infant 4 months, mild diaper rash, no fever, feeding normally",
        "expected_severity": "routine",
        "expected_keywords": ["rash", "diaper", "cream", "clean"],
        "category": "dermatology",
    },
    {
        "symptoms": "Child 6 years, itchy scalp, white nits visible in hair, no other symptoms",
        "expected_severity": "routine",
        "expected_keywords": ["lice", "hair", "shampoo", "comb"],
        "category": "dermatology",
    },
    {
        "symptoms": "Child 2 years, watery diarrhea started today, some dehydration, still drinking",
        "expected_severity": "urgent",  # IMCI Plan B: "some dehydration" = urgent
        "expected_keywords": ["diarrhea", "ORS", "hydration", "monitor"],
        "category": "GI",
    },
    {
        "symptoms": "Child 4 years, fever 38°C, sore throat, swollen lymph nodes, eating poorly",
        "expected_severity": "standard",
        "expected_keywords": ["throat", "fever", "tonsillitis", "fluid"],
        "category": "ENT",
    },
    {
        "symptoms": "Pregnant woman, severe headache, blurred vision, swollen feet, blood pressure elevated",
        "expected_severity": "emergency",
        "expected_keywords": ["preeclampsia", "blood pressure", "refer", "emergency"],
        "category": "maternal",
    },
    {
        "symptoms": "Enfant de 3 ans, fièvre élevée 39.5°C, diarrhée aqueuse, yeux enfoncés",
        "expected_severity": "emergency",
        "expected_keywords": ["déshydrat", "fièvre", "ORS", "référ"],
        "language": "French",
        "category": "multilingual",
    },
    {
        "symptoms": "Niño de 2 años, tos persistente, respiración rápida, tiraje subcostal",
        "expected_severity": "emergency",
        "expected_keywords": ["neumonía", "respirat", "antibiótic", "refer"],
        "language": "Spanish",
        "category": "multilingual",
    },
    {
        "symptoms": "Mtoto wa miaka 4, kuhara kwa damu, homa, tumbo kuumwa sana",
        "expected_severity": "urgent",
        "expected_keywords": ["damu", "homa", "refer"],
        "language": "Swahili",
        "category": "multilingual",
    },
]


def parse_triage_response(text):
    """Extract structured triage data from model response."""
    import re

    # Try JSON extraction
    json_match = re.search(r'\{[^{}]*"severity"[^{}]*\}', text, re.DOTALL)
    if json_match:
        try:
            data = json.loads(json_match.group(0))
            return data
        except json.JSONDecodeError:
            pass

    # Fallback: keyword-based severity extraction
    lower = text.lower()
    if "emergency" in lower or "critical" in lower:
        severity = "emergency"
    elif "urgent" in lower or "serious" in lower:
        severity = "urgent"
    elif "routine" in lower or "mild" in lower or "minor" in lower:
        severity = "routine"
    else:
        severity = "standard"

    return {"severity": severity, "_raw": text}


def evaluate_response(response_data, test_case):
    """Score a single response against expected values."""
    results = {}

    # 1. Severity accuracy
    predicted = response_data.get("severity", "unknown").lower().strip()
    expected = test_case["expected_severity"]
    results["severity_correct"] = predicted == expected
    results["predicted_severity"] = predicted
    results["expected_severity"] = expected

    # 2. JSON compliance (did model return structured JSON?)
    results["json_compliant"] = "_raw" not in response_data

    # 3. IMCI keyword adherence
    raw_text = response_data.get("_raw", "") or json.dumps(response_data)
    raw_lower = raw_text.lower()
    matched = sum(1 for kw in test_case["expected_keywords"] if kw.lower() in raw_lower)
    results["keyword_score"] = matched / len(test_case["expected_keywords"])
    results["keywords_matched"] = matched
    results["keywords_total"] = len(test_case["expected_keywords"])

    # 4. Has recommendation
    results["has_recommendation"] = bool(response_data.get("recommendation"))

    # 5. Has danger signs
    results["has_danger_signs"] = bool(response_data.get("danger_signs"))

    return results


def main():
    parser = argparse.ArgumentParser(description="Benchmark fine-tuned Gemma 4 for MedLingua")
    parser.add_argument(
        "--model", type=str, default=None,
        help="Path to LoRA adapter (default: training/output/medlingua-lora)"
    )
    parser.add_argument("--samples", type=int, default=0,
                        help="Number of test cases to run (0 = all)")
    parser.add_argument("--output", type=str, default=None,
                        help="Output JSON file for results")
    args = parser.parse_args()

    training_dir = Path(__file__).resolve().parent
    if args.model is None:
        args.model = str(training_dir / "output" / "medlingua-lora")
    if args.output is None:
        args.output = str(training_dir / "output" / "benchmark_results.json")

    if not os.path.exists(args.model):
        print(f"ERROR: Model not found at {args.model}")
        print("Run first: python training/finetune.py")
        return

    # Load training config
    config_path = os.path.join(args.model, "medlingua_training_config.json")
    base_model = "unsloth/gemma-4-E4B-it-unsloth-bnb-4bit"
    if os.path.exists(config_path):
        with open(config_path) as f:
            config = json.load(f)
        base_model = config.get("base_model", base_model)

    print("=" * 60)
    print("MedLingua Benchmark")
    print("=" * 60)
    print(f"  Model:     {args.model}")
    print(f"  Base:      {base_model}")
    print(f"  Test cases: {len(TRIAGE_TEST_CASES)}")
    print("=" * 60)

    # ---- Load model -----------------------------------------------------------
    from unsloth import FastModel

    print("\nLoading model...")
    model, tokenizer = FastModel.from_pretrained(
        model_name=args.model,
        max_seq_length=2048,
        load_in_4bit=True,
    )

    # ---- Run evaluation -------------------------------------------------------
    test_cases = TRIAGE_TEST_CASES
    if args.samples > 0:
        test_cases = test_cases[:args.samples]

    all_results = []
    total_latency = 0

    print(f"\nRunning {len(test_cases)} test cases...\n")

    for i, tc in enumerate(test_cases):
        language = tc.get("language", "English")
        prompt_messages = [
            {
                "role": "system",
                "content": (
                    "You are MedLingua, a medical triage assistant for Community Health Workers. "
                    "Follow WHO IMCI protocols. Respond in " + language + " language. "
                    "You MUST respond with a JSON object containing: severity (emergency/urgent/standard/routine), "
                    "diagnosis, recommendation, danger_signs (list), and confidence (0-1)."
                ),
            },
            {
                "role": "user",
                "content": f"Patient symptoms: {tc['symptoms']}\n\nAssess severity and provide triage guidance.",
            },
        ]

        # tokenizer from FastModel is a Gemma4Processor (multimodal);
        # use its inner tokenizer for text-only inference
        text_tokenizer = getattr(tokenizer, "tokenizer", tokenizer)
        prompt = text_tokenizer.apply_chat_template(
            prompt_messages, tokenize=False, add_generation_prompt=True
        )
        inputs = text_tokenizer(prompt, return_tensors="pt").to(model.device)

        start = time.time()
        with __import__("torch").no_grad():
            outputs = model.generate(
                **inputs,
                max_new_tokens=512,
                temperature=0.3,
                top_k=20,
                do_sample=True,
            )
        latency = time.time() - start
        total_latency += latency

        response_text = text_tokenizer.decode(outputs[0][inputs["input_ids"].shape[-1]:], skip_special_tokens=True)
        parsed = parse_triage_response(response_text)
        scores = evaluate_response(parsed, tc)
        scores["latency_seconds"] = latency
        scores["category"] = tc["category"]
        scores["language"] = language

        status = "✓" if scores["severity_correct"] else "✗"
        print(f"  [{i+1:2d}/{len(test_cases)}] {status} {tc['category']:15s} "
              f"Expected: {tc['expected_severity']:10s} Got: {scores['predicted_severity']:10s} "
              f"({latency:.1f}s)")

        all_results.append(scores)

    # ---- Compute aggregate metrics -------------------------------------------
    n = len(all_results)
    severity_acc = sum(r["severity_correct"] for r in all_results) / n
    json_rate = sum(r["json_compliant"] for r in all_results) / n
    keyword_avg = sum(r["keyword_score"] for r in all_results) / n
    avg_latency = total_latency / n
    has_rec = sum(r["has_recommendation"] for r in all_results) / n
    has_danger = sum(r["has_danger_signs"] for r in all_results) / n

    # 3-class merged accuracy (emergency / urgent / non-urgent)
    # "routine" and "standard" are clinically equivalent (non-urgent follow-up)
    def merge_severity(s):
        return "non-urgent" if s in ("routine", "standard") else s

    severity_acc_3class = sum(
        1 for r in all_results
        if merge_severity(r["predicted_severity"]) == merge_severity(r["expected_severity"])
    ) / n

    # Per-category breakdown
    categories = set(r["category"] for r in all_results)
    per_category = {}
    for cat in sorted(categories):
        cat_results = [r for r in all_results if r["category"] == cat]
        per_category[cat] = {
            "count": len(cat_results),
            "severity_accuracy": sum(r["severity_correct"] for r in cat_results) / len(cat_results),
            "keyword_score": sum(r["keyword_score"] for r in cat_results) / len(cat_results),
        }

    # Severity confusion
    severity_levels = ["emergency", "urgent", "standard", "routine"]
    confusion = {exp: {pred: 0 for pred in severity_levels} for exp in severity_levels}
    for r in all_results:
        exp = r["expected_severity"]
        pred = r["predicted_severity"]
        if exp in confusion and pred in confusion[exp]:
            confusion[exp][pred] += 1

    print("\n" + "=" * 60)
    print("BENCHMARK RESULTS")
    print("=" * 60)
    print(f"  Severity Accuracy (4-class): {severity_acc * 100:.1f}%")
    print(f"  Severity Accuracy (3-class): {severity_acc_3class * 100:.1f}%  (routine+standard merged)")
    print(f"  JSON Compliance Rate:        {json_rate * 100:.1f}%")
    print(f"  IMCI Keyword Adherence:   {keyword_avg * 100:.1f}%")
    print(f"  Recommendation Rate:      {has_rec * 100:.1f}%")
    print(f"  Danger Signs Rate:        {has_danger * 100:.1f}%")
    print(f"  Avg Inference Latency:    {avg_latency:.2f}s")
    print(f"  Total Test Cases:         {n}")

    print("\n  Per-Category Breakdown:")
    for cat, stats in per_category.items():
        print(f"    {cat:20s}  acc={stats['severity_accuracy']*100:.0f}%  "
              f"kwds={stats['keyword_score']*100:.0f}%  (n={stats['count']})")

    print("\n  Severity Confusion Matrix:")
    print(f"    {'':15s} {'emergency':>10s} {'urgent':>10s} {'standard':>10s} {'routine':>10s}")
    for exp in severity_levels:
        row = [str(confusion[exp][pred]) for pred in severity_levels]
        print(f"    {exp:15s} {''.join(f'{v:>10s}' for v in row)}")

    # ---- Save results --------------------------------------------------------
    benchmark_output = {
        "model": args.model,
        "base_model": base_model,
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "metrics": {
            "severity_accuracy": round(severity_acc, 4),
            "severity_accuracy_3class": round(severity_acc_3class, 4),
            "json_compliance_rate": round(json_rate, 4),
            "imci_keyword_adherence": round(keyword_avg, 4),
            "recommendation_rate": round(has_rec, 4),
            "danger_signs_rate": round(has_danger, 4),
            "avg_inference_latency_s": round(avg_latency, 3),
            "total_test_cases": n,
        },
        "per_category": per_category,
        "confusion_matrix": confusion,
        "individual_results": all_results,
    }

    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    with open(args.output, "w") as f:
        json.dump(benchmark_output, f, indent=2)

    print(f"\n  Results saved to {args.output}")
    print("=" * 60)


if __name__ == "__main__":
    main()
