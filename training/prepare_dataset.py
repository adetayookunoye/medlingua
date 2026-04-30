"""
MedLingua — Dataset Preparation Pipeline

Merges multiple data sources into a single training-ready JSONL file:
1. Custom IMCI triage dataset (training/data/imci_triage_dataset.jsonl)
2. Multilingual IMCI translations (training/data/imci_multilingual.jsonl)
3. MedMCQA from HuggingFace (medical MCQs → triage-formatted)
4. HealthCareMagic from HuggingFace (doctor-patient dialogues → triage-formatted)

Output: training/data/medlingua_train.jsonl — ready for Unsloth fine-tuning.

Usage:
    python training/prepare_dataset.py
    python training/prepare_dataset.py --max-medmcqa 2000 --max-healthcaremagic 1000
    python training/prepare_dataset.py --imci-only          # IMCI + multilingual only
    python training/prepare_dataset.py --generate-multilingual  # Generate translations
"""

import argparse
import json
import os
import random
from pathlib import Path

try:
    from datasets import load_dataset
except ImportError:
    print("Install datasets: pip install datasets")
    raise


SCRIPT_DIR = Path(__file__).resolve().parent
DATA_DIR = SCRIPT_DIR / "data"
IMCI_FILE = DATA_DIR / "imci_triage_dataset.jsonl"
MULTILINGUAL_FILE = DATA_DIR / "imci_multilingual.jsonl"
ROUTINE_BOOST_FILE = DATA_DIR / "routine_standard_boost.jsonl"
OUTPUT_FILE = DATA_DIR / "medlingua_train.jsonl"

# The system prompt that matches GemmaService._buildTriagePrompt()
SYSTEM_PROMPT = """You are MedLingua, a medical triage assistant for Community Health Workers.
Follow WHO IMCI (Integrated Management of Childhood Illness) protocols.

You MUST use the classify_triage function to provide structured output.

IMPORTANT: You are a triage SUPPORT tool, not a doctor. Always recommend
professional medical consultation for serious conditions."""

TOOLS_BLOCK = """[{
  "name": "classify_triage",
  "description": "Classify the medical triage severity and provide guidance",
  "parameters": {
    "severity": "emergency|urgent|standard|routine",
    "diagnosis": "Brief suspected condition",
    "recommendation": "Actionable steps for the CHW",
    "danger_signs": ["list of danger signs to watch for"],
    "confidence": 0.0-1.0
  }
}]"""


def format_chat_template(instruction: str, input_text: str, output_text: str) -> dict:
    """Format a sample into the Gemma chat template used by Unsloth."""
    user_content = instruction
    if input_text:
        user_content += f"\n\n{input_text}"

    return {
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_content},
            {"role": "assistant", "content": output_text},
        ]
    }


def load_imci_dataset() -> list[dict]:
    """Load the custom IMCI triage dataset."""
    samples = []
    with open(IMCI_FILE, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            raw = json.loads(line)
            samples.append(
                format_chat_template(
                    raw["instruction"], raw.get("input", ""), raw["output"]
                )
            )
    print(f"  IMCI dataset: {len(samples)} samples")
    return samples


# ---------------------------------------------------------------------------
# Multilingual data: West African + global South languages
# ---------------------------------------------------------------------------

# Translation templates per language for common IMCI scenarios.
# These teach the model to handle multilingual input from CHWs.

MULTILINGUAL_TEMPLATES: dict[str, list[dict]] = {
    "pcm": [  # Nigerian Pidgin
        {
            "instruction": "Pikin get high fever, e no fit drink water, body dey hot well well. E don sick for 2 days. Abeg assess am.",
            "input": "Age: 2 years\nGender: Male\nSymptoms: high fever, unable to drink, body very hot, sick 2 days",
            "severity": "emergency",
            "diagnosis": "Possible severe febrile illness — unable to drink is a general danger sign",
            "recommendation": "1. Give first dose of paracetamol suppository\n2. Treat to prevent low blood sugar\n3. URGENTLY refer to hospital\n4. Keep child cool with tepid sponging\n5. If convulsions occur, protect from injury",
        },
        {
            "instruction": "Small pikin dey purge for 3 days, eye don enter inside, e dey drink water well well. Wetin we go do?",
            "input": "Age: 1 year\nGender: Female\nSymptoms: diarrhea 3 days, sunken eyes, drinks eagerly",
            "severity": "urgent",
            "diagnosis": "Diarrhea with some dehydration",
            "recommendation": "1. Give ORS — 75ml/kg over 4 hours\n2. Continue breastfeeding\n3. Give zinc for 14 days\n4. Reassess after 4 hours\n5. Return if pikin no fit drink",
        },
        {
            "instruction": "Pikin dey cough, e dey breathe fast fast. No chest indrawing. E fit chop and drink. Fever small.",
            "input": "Age: 3 years\nGender: Male\nSymptoms: cough, fast breathing, no chest indrawing, eating normally, mild fever",
            "severity": "urgent",
            "diagnosis": "Pneumonia — fast breathing",
            "recommendation": "1. Give amoxicillin for 5 days\n2. Give paracetamol for fever\n3. Soothe throat with warm water and honey\n4. Follow up in 2 days\n5. Return immediately if breathing get worse",
        },
        {
            "instruction": "Baby wey born 2 weeks ago, e yellow for face and chest. E dey suck breast well, dey active. No fever.",
            "input": "Age: 2 weeks\nGender: Unknown\nSymptoms: jaundice face and chest, breastfeeding well, active, no fever",
            "severity": "routine",
            "diagnosis": "Physiological jaundice — mild",
            "recommendation": "1. Continue breastfeeding frequently\n2. Expose to indirect sunlight\n3. Follow up in 2 days\n4. Return if yellow reach belly or palm",
        },
    ],
    "ha": [  # Hausa
        {
            "instruction": "Yaro yana da zazzabi mai tsanani, ba ya iya shan ruwa, jikinsa yana zafi sosai. Ya yi rashin lafiya kwana 2. Da fatan za a tantance shi.",
            "input": "Age: 3 years\nGender: Male\nSymptoms: high fever, unable to drink, body hot, sick 2 days",
            "severity": "emergency",
            "diagnosis": "Possible severe febrile illness with general danger sign",
            "recommendation": "1. Give first dose of paracetamol\n2. Prevent low blood sugar\n3. URGENTLY refer to hospital\n4. Keep child cool\n5. Monitor for convulsions",
        },
        {
            "instruction": "Jariri na yin gudawa kwana 3, idanunsa sun shiga ciki, yana shan ruwa da karfi. Yaya za a yi?",
            "input": "Age: 10 months\nGender: Female\nSymptoms: diarrhea 3 days, sunken eyes, drinking eagerly",
            "severity": "urgent",
            "diagnosis": "Diarrhea with some dehydration",
            "recommendation": "1. Give ORS 75ml/kg over 4 hours\n2. Continue breastfeeding\n3. Give zinc 14 days\n4. Reassess after 4 hours\n5. Return if unable to drink",
        },
        {
            "instruction": "Yarinya tana tari, tana numfashi da sauri. Ba ta da matsin kirji. Tana ci da sha yadda ya kamata.",
            "input": "Age: 2 years\nGender: Female\nSymptoms: cough, fast breathing, no chest indrawing, eating normally",
            "severity": "urgent",
            "diagnosis": "Pneumonia — fast breathing",
            "recommendation": "1. Give amoxicillin 5 days\n2. Give paracetamol\n3. Warm fluids\n4. Follow up in 2 days\n5. Return if breathing worsens",
        },
    ],
    "yo": [  # Yoruba
        {
            "instruction": "Ọmọ ni ibà gíga, kò lè mu omi, ara rẹ̀ gbóná gan-an. Ó ti ṣàìsàn fún ọjọ́ méjì. Ẹ jọ̀wọ́ ẹ ṣàyẹ̀wò rẹ̀.",
            "input": "Age: 2 years\nGender: Male\nSymptoms: high fever, unable to drink, body very hot, sick 2 days",
            "severity": "emergency",
            "diagnosis": "Possible severe febrile illness — unable to drink is danger sign",
            "recommendation": "1. Give first dose of paracetamol\n2. Prevent low blood sugar\n3. URGENTLY refer to hospital\n4. Keep child cool\n5. Watch for convulsions",
        },
        {
            "instruction": "Ọmọ ń gbẹ́ fún ọjọ́ mẹ́ta, ojú rẹ̀ ti rì sínú, ó ń mu omi dáadáa. Kí la lè ṣe?",
            "input": "Age: 1 year\nGender: Female\nSymptoms: diarrhea 3 days, sunken eyes, drinks eagerly",
            "severity": "urgent",
            "diagnosis": "Diarrhea with some dehydration",
            "recommendation": "1. Give ORS 75ml/kg over 4 hours\n2. Continue breastfeeding\n3. Give zinc 14 days\n4. Check after 4 hours\n5. Return if cannot drink",
        },
        {
            "instruction": "Ọmọ ń ṣe ikọ́, ó ń mí kánkán. Kò sí àmì ìyọnu àyà. Ó ń jẹun, ó ń mu omi dáadáa.",
            "input": "Age: 4 years\nGender: Male\nSymptoms: cough, fast breathing, no chest indrawing, eating normally",
            "severity": "urgent",
            "diagnosis": "Pneumonia — fast breathing",
            "recommendation": "1. Give amoxicillin 5 days\n2. Paracetamol for fever\n3. Warm fluids\n4. Follow up in 2 days\n5. Return if breathing gets worse",
        },
    ],
    "tw": [  # Twi (Akan)
        {
            "instruction": "Abofra no wɔ atiridii kɛse, ɔntumi nnom nsuo, ne ho hyew paa. Wayare nnafua 2. Mesrɛ wo hwɛ no.",
            "input": "Age: 2 years\nGender: Male\nSymptoms: high fever, unable to drink, body very hot, sick 2 days",
            "severity": "emergency",
            "diagnosis": "Possible severe febrile illness with danger signs",
            "recommendation": "1. Give paracetamol\n2. Prevent low blood sugar\n3. URGENTLY refer to hospital\n4. Keep child cool\n5. Monitor for convulsions",
        },
        {
            "instruction": "Abofra no agyagya ne ho nnafua 3, n'ani akɔ mu, ɔnom nsuo yiye. Dɛn na yɛnyɛ?",
            "input": "Age: 9 months\nGender: Female\nSymptoms: diarrhea 3 days, sunken eyes, drinks eagerly",
            "severity": "urgent",
            "diagnosis": "Diarrhea with some dehydration",
            "recommendation": "1. Give ORS 75ml/kg for 4 hours\n2. Continue breastfeeding\n3. Give zinc 14 days\n4. Check after 4 hours\n5. Return if cannot drink",
        },
    ],
    "fr": [  # French (West Africa)
        {
            "instruction": "L'enfant a une forte fièvre, il ne peut pas boire, son corps est très chaud. Il est malade depuis 2 jours. Veuillez évaluer.",
            "input": "Âge: 2 ans\nSexe: Masculin\nSymptômes: forte fièvre, incapable de boire, corps très chaud, malade depuis 2 jours",
            "severity": "emergency",
            "diagnosis": "Maladie fébrile grave possible — incapacité de boire est un signe de danger",
            "recommendation": "1. Donner paracétamol en première dose\n2. Prévenir l'hypoglycémie\n3. RÉFÉRER D'URGENCE à l'hôpital\n4. Garder l'enfant au frais\n5. Surveiller les convulsions",
        },
        {
            "instruction": "Bébé a la diarrhée depuis 3 jours, les yeux sont enfoncés, il boit avidement. Que faire?",
            "input": "Âge: 1 an\nSexe: Féminin\nSymptômes: diarrhée 3 jours, yeux enfoncés, boit avidement",
            "severity": "urgent",
            "diagnosis": "Diarrhée avec déshydratation modérée",
            "recommendation": "1. Donner SRO 75ml/kg sur 4 heures\n2. Continuer l'allaitement\n3. Donner zinc pendant 14 jours\n4. Réévaluer après 4 heures\n5. Revenir si l'enfant ne peut pas boire",
        },
        {
            "instruction": "Enfant tousse, respire vite. Pas de tirage sous-costal. Il mange et boit normalement. Un peu de fièvre.",
            "input": "Âge: 3 ans\nSexe: Masculin\nSymptômes: toux, respiration rapide, pas de tirage, mange normalement, fièvre légère",
            "severity": "urgent",
            "diagnosis": "Pneumonie — respiration rapide",
            "recommendation": "1. Donner amoxicilline 5 jours\n2. Paracétamol pour la fièvre\n3. Liquides chauds\n4. Suivi dans 2 jours\n5. Revenir si respiration s'aggrave",
        },
        {
            "instruction": "Femme enceinte de 8 mois, maux de tête sévères, vision floue, gonflement des mains et du visage. Tension: 160/110.",
            "input": "Âge: 28 ans\nSexe: Féminin\nSymptômes: enceinte 8 mois, céphalées sévères, vision floue, œdème mains et visage, TA 160/110",
            "severity": "emergency",
            "diagnosis": "Pré-éclampsie sévère — risque d'éclampsie",
            "recommendation": "1. RÉFÉRER D'URGENCE à l'hôpital\n2. Si sulfate de magnésium disponible, donner dose de charge\n3. Position latérale gauche\n4. Surveiller signes vitaux toutes les 15 minutes\n5. Si convulsions: protéger, sulfate de magnésium, libérer voies aériennes",
        },
    ],
    "sw": [  # Swahili
        {
            "instruction": "Mtoto ana homa kali, hawezi kunywa maji, mwili wake una joto sana. Amekuwa mgonjwa kwa siku 2. Tafadhali mtathmini.",
            "input": "Umri: Miaka 2\nJinsia: Kiume\nDalili: homa kali, hawezi kunywa, mwili una joto, mgonjwa siku 2",
            "severity": "emergency",
            "diagnosis": "Ugonjwa mkali wa homa — kutoweza kunywa ni ishara ya hatari",
            "recommendation": "1. Mpe kipimo cha kwanza cha paracetamol\n2. Zuia sukari ya chini ya damu\n3. PELEKA HARAKA hospitalini\n4. Mweke mtoto baridi\n5. Angalia degedege",
        },
        {
            "instruction": "Mtoto ana kuharisha siku 3, macho yake yamezama, anakunywa maji kwa bidii. Tufanye nini?",
            "input": "Umri: Miezi 10\nJinsia: Kike\nDalili: kuharisha siku 3, macho yamezama, anakunywa kwa bidii",
            "severity": "urgent",
            "diagnosis": "Kuharisha na upungufu wa maji kiasi",
            "recommendation": "1. Mpe ORS 75ml/kg kwa masaa 4\n2. Endelea kunyonyesha\n3. Mpe zinki siku 14\n4. Tathmini baada ya masaa 4\n5. Rudi kama hawezi kunywa",
        },
    ],
    "hi": [  # Hindi
        {
            "instruction": "बच्चे को तेज बुखार है, पानी नहीं पी पा रहा, शरीर बहुत गर्म है। 2 दिन से बीमार है। कृपया जांच करें।",
            "input": "उम्र: 2 साल\nलिंग: पुरुष\nलक्षण: तेज बुखार, पानी नहीं पी सकता, शरीर बहुत गर्म, 2 दिन से बीमार",
            "severity": "emergency",
            "diagnosis": "Possible severe febrile illness — unable to drink is danger sign",
            "recommendation": "1. Give first dose of paracetamol\n2. Prevent low blood sugar\n3. URGENTLY refer to hospital\n4. Keep child cool\n5. Watch for convulsions",
        },
        {
            "instruction": "बच्चे को 3 दिन से दस्त हो रहे हैं, आंखें धंसी हुई हैं, बहुत प्यास लग रही है। क्या करें?",
            "input": "उम्र: 1 साल\nलिंग: महिला\nलक्षण: 3 दिन से दस्त, आंखें धंसी, बहुत पानी पी रहा",
            "severity": "urgent",
            "diagnosis": "Diarrhea with some dehydration",
            "recommendation": "1. Give ORS 75ml/kg over 4 hours\n2. Continue breastfeeding\n3. Give zinc 14 days\n4. Reassess after 4 hours\n5. Return if unable to drink",
        },
    ],
}


def generate_multilingual_samples() -> list[dict]:
    """Generate multilingual training samples from template translations."""
    samples = []
    for lang_code, templates in MULTILINGUAL_TEMPLATES.items():
        for tmpl in templates:
            output = json.dumps({
                "severity": tmpl["severity"],
                "diagnosis": tmpl["diagnosis"],
                "recommendation": tmpl["recommendation"],
                "danger_signs": ["Condition worsens", "Unable to eat or drink",
                                 "High fever persists", "Becomes lethargic"],
                "confidence": 0.85,
            })
            sample = format_chat_template(
                tmpl["instruction"], tmpl.get("input", ""), output
            )
            samples.append(sample)
    return samples


def load_multilingual_dataset() -> list[dict]:
    """Load pre-generated multilingual IMCI samples, or generate and save."""
    if MULTILINGUAL_FILE.exists():
        samples = []
        with open(MULTILINGUAL_FILE, "r") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                samples.append(json.loads(line))
        print(f"  Multilingual IMCI: {len(samples)} samples (loaded from file)")
        return samples

    # Generate and save
    samples = generate_multilingual_samples()
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(MULTILINGUAL_FILE, "w") as f:
        for s in samples:
            f.write(json.dumps(s, ensure_ascii=False) + "\n")
    print(f"  Multilingual IMCI: {len(samples)} samples (generated)")
    return samples


def severity_from_topic(topic: str, explanation: str) -> str:
    """Heuristic severity from MedMCQA topic name and explanation."""
    text = f"{topic} {explanation}".lower()
    emergency_kw = [
        "cardiac arrest", "myocardial infarction", "anaphylaxis", "status epilepticus",
        "tension pneumothorax", "hemorrhagic shock", "meningitis", "septic shock",
        "eclampsia", "pulmonary embolism", "intracranial hemorrhage",
    ]
    urgent_kw = [
        "pneumonia", "appendicitis", "fracture", "dehydration", "asthma",
        "diabetic ketoacidosis", "ectopic pregnancy", "peritonitis", "cellulitis",
        "malaria", "pyelonephritis",
    ]
    if any(kw in text for kw in emergency_kw):
        return "emergency"
    if any(kw in text for kw in urgent_kw):
        return "urgent"
    return "standard"


def convert_medmcqa_sample(sample: dict) -> dict | None:
    """Convert a MedMCQA sample to triage format."""
    question = sample.get("question", "")
    explanation = sample.get("exp", "") or ""
    topic = sample.get("topic_name", "") or ""
    subject = sample.get("subject_name", "") or ""

    # Skip samples without explanation (no useful teaching signal)
    if not explanation or len(explanation) < 30:
        return None

    # Get the correct answer
    options = [sample.get("opa", ""), sample.get("opb", ""),
               sample.get("opc", ""), sample.get("opd", "")]
    correct_idx = sample.get("cop", 0)
    if not isinstance(correct_idx, int) or correct_idx < 0 or correct_idx >= len(options):
        return None
    correct_answer = options[correct_idx]

    severity = severity_from_topic(topic, explanation)

    output = json.dumps({
        "severity": severity,
        "diagnosis": correct_answer,
        "recommendation": explanation,
        "danger_signs": ["Condition worsening", "Seek medical consultation for accurate diagnosis"],
        "confidence": 0.75,
    })

    instruction = (
        f"A patient presents with the following clinical scenario. "
        f"Subject area: {subject}. Topic: {topic}.\n\n{question}"
    )

    return format_chat_template(instruction, "", output)


def load_medmcqa(max_samples: int) -> list[dict]:
    """Load and convert MedMCQA dataset from HuggingFace."""
    print(f"  Loading MedMCQA (max {max_samples})...")
    try:
        ds = load_dataset("openlifescienceai/medmcqa", split="train", streaming=True)
    except Exception as e:
        print(f"  WARNING: Could not load MedMCQA: {e}")
        return []

    samples = []
    for sample in ds:
        converted = convert_medmcqa_sample(sample)
        if converted:
            samples.append(converted)
        if len(samples) >= max_samples:
            break

    print(f"  MedMCQA: {len(samples)} samples converted")
    return samples


def convert_healthcaremagic_sample(sample: dict) -> dict | None:
    """Convert a HealthCareMagic doctor-patient dialogue to triage format."""
    instruction_text = sample.get("instruction", "") or sample.get("input", "")
    response = sample.get("output", "") or sample.get("response", "")

    if not instruction_text or not response or len(response) < 50:
        return None

    lower = response.lower()
    if any(kw in lower for kw in ["emergency", "immediately", "911", "urgent care", "ER"]):
        severity = "emergency"
    elif any(kw in lower for kw in ["consult", "visit doctor", "see a doctor", "appointment"]):
        severity = "urgent"
    elif any(kw in lower for kw in ["over-the-counter", "home remedy", "rest", "self-care"]):
        severity = "routine"
    else:
        severity = "standard"

    output = json.dumps({
        "severity": severity,
        "diagnosis": response[:200] if len(response) > 200 else response,
        "recommendation": response,
        "danger_signs": ["Condition worsens", "Symptoms persist beyond expected duration",
                         "Seek professional medical consultation"],
        "confidence": 0.70,
    })

    return format_chat_template(
        "A patient describes the following symptoms. Assess and provide triage guidance.",
        instruction_text,
        output,
    )


def load_healthcaremagic(max_samples: int) -> list[dict]:
    """Load and convert HealthCareMagic dataset from HuggingFace."""
    print(f"  Loading HealthCareMagic (max {max_samples})...")
    try:
        ds = load_dataset(
            "lavita/ChatDoctor-HealthCareMagic-100k",
            split="train",
            streaming=True,
        )
    except Exception as e:
        print(f"  WARNING: Could not load HealthCareMagic: {e}")
        return []

    samples = []
    for sample in ds:
        converted = convert_healthcaremagic_sample(sample)
        if converted:
            samples.append(converted)
        if len(samples) >= max_samples:
            break

    print(f"  HealthCareMagic: {len(samples)} samples converted")
    return samples


def main():
    parser = argparse.ArgumentParser(description="Prepare MedLingua training dataset")
    parser.add_argument("--max-medmcqa", type=int, default=2000,
                        help="Max samples from MedMCQA (default: 2000)")
    parser.add_argument("--max-healthcaremagic", type=int, default=1000,
                        help="Max samples from HealthCareMagic (default: 1000)")
    parser.add_argument("--seed", type=int, default=42, help="Random seed")
    parser.add_argument("--imci-only", action="store_true",
                        help="Only use the IMCI dataset + multilingual (skip HuggingFace)")
    parser.add_argument("--generate-multilingual", action="store_true",
                        help="Regenerate multilingual samples even if file exists")
    args = parser.parse_args()

    random.seed(args.seed)
    os.makedirs(DATA_DIR, exist_ok=True)

    print("Preparing MedLingua training dataset...")
    print("=" * 60)

    # 1. Load IMCI (always)
    all_samples = load_imci_dataset()

    # 2. Load multilingual IMCI translations (always)
    if args.generate_multilingual and MULTILINGUAL_FILE.exists():
        MULTILINGUAL_FILE.unlink()
    multilingual_samples = load_multilingual_dataset()
    all_samples.extend(multilingual_samples)

    # 2b. Load routine/standard boost samples (always)
    if ROUTINE_BOOST_FILE.exists():
        boost_samples = []
        with open(ROUTINE_BOOST_FILE, "r") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                raw = json.loads(line)
                boost_samples.append(
                    format_chat_template(
                        raw["instruction"], raw.get("input", ""), raw["output"]
                    )
                )
        print(f"  Routine/standard boost: {len(boost_samples)} samples")
        all_samples.extend(boost_samples)
    else:
        print(f"  Routine/standard boost: skipped (file not found)")

    if not args.imci_only:
        # 3. Load MedMCQA
        medmcqa_samples = load_medmcqa(args.max_medmcqa)
        all_samples.extend(medmcqa_samples)

        # 4. Load HealthCareMagic
        hcm_samples = load_healthcaremagic(args.max_healthcaremagic)
        all_samples.extend(hcm_samples)

    # Shuffle
    random.shuffle(all_samples)

    # Write output
    with open(OUTPUT_FILE, "w") as f:
        for sample in all_samples:
            f.write(json.dumps(sample) + "\n")

    print("=" * 60)
    print(f"Total training samples: {len(all_samples)}")
    print(f"Output: {OUTPUT_FILE}")

    # Print severity distribution
    severity_counts: dict[str, int] = {}
    for s in all_samples:
        try:
            assistant_msg = s["messages"][-1]["content"]
            parsed = json.loads(assistant_msg)
            sev = parsed.get("severity", "unknown")
            severity_counts[sev] = severity_counts.get(sev, 0) + 1
        except (json.JSONDecodeError, KeyError):
            severity_counts["parse_error"] = severity_counts.get("parse_error", 0) + 1

    print("\nSeverity distribution:")
    for sev, count in sorted(severity_counts.items()):
        pct = count / len(all_samples) * 100
        print(f"  {sev:12s}: {count:5d} ({pct:.1f}%)")


if __name__ == "__main__":
    main()
    # Force-exit to avoid PyGILState_Release crash during interpreter
    # shutdown caused by datasets/pyarrow background threads.
    os._exit(0)
