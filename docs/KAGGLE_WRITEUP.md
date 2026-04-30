# MedLingua: An Offline Clinical Workflow System for Frontline Healthcare - Powered by Gemma 4

## Summary

MedLingua is not a medical chatbot - it is an offline, multilingual **clinical workflow system** that turns a single Android phone into a triage, documentation, referral, and public-health surveillance tool for Community Health Workers (CHWs) in low-resource settings. Running entirely on-device using Google's Gemma 4 E4B model via MediaPipe LiteRT, it supports 12 languages - including several African languages - and follows WHO IMCI protocols to classify patients by severity, generate explainable referral recommendations, and surface outbreak signals for supervisors. This writeup covers the problem, architecture, Gemma 4 integration, fine-tuning approach, evaluation, and deployment constraints.

## The Problem

Every year, over 5 million children under age 5 die from preventable causes. The majority of these deaths occur in sub-Saharan Africa and South Asia, regions where Community Health Workers are often the only healthcare access point for rural populations. These CHWs face three compounding challenges: limited medical training for complex triage decisions, unreliable or nonexistent internet connectivity, and language barriers between clinical protocols (written in English or French) and the communities they serve (speaking local languages like Hausa, Yoruba, Twi, or Swahili).

Existing mobile health tools require constant internet connectivity, operate only in major languages, or provide generic health information rather than actionable triage guidance. CHWs need a **field system** - not another assistant - that works offline, in their language, follows evidence-based protocols, and gives supervisors visibility into community health patterns.

## Why Gemma 4?

Gemma 4 E4B is suited for this application:

- **On-device deployment**: The 3.65 GB LiteRT model runs entirely on the phone without internet - critical for rural areas with no connectivity
- **Efficient architecture**: 8B total parameters with only 4.5B effective parameters via selective activation, enabling fast inference on mobile hardware
- **Multimodal native**: Built-in understanding of text, images, and audio — CHWs can photograph wounds, describe symptoms verbally, or type them
- **128K context window**: Handles detailed patient histories without truncation
- **Function calling**: Gemma 4's structured output capability produces consistent JSON triage assessments rather than free-text responses
- **Apache 2.0 license**: Enables free deployment in humanitarian settings

We specifically chose E4B over the larger 26B or 31B variants because on-device inference is a hard requirement — CHWs cannot depend on cloud APIs in the field.

- **Function calling**: Gemma 4's tool-use capability is central to MedLingua's clinical workflow. The model is instructed to call three tools - `classify_triage` for structured severity output, `dose_check` for weight-based medication dosing, and `interaction_check` for drug safety screening. Tool calls are executed locally against an on-device WHO formulary, keeping the entire pipeline offline.

## Why This Is Different

| Capability | Typical mHealth App | MedLingua |
|---|---|---|
| Offline triage inference | Often cloud-dependent | Fully on-device (Gemma 4 LiteRT) |
| Local-language workflow | Limited language support | 12 languages including African regional languages |
| Clinical output format | Free text guidance | Structured severity + recommendations + danger signs |
| Medication safety | Usually external reference | On-device dose + interaction checks via function calling |
| Supervisor visibility | Basic records | Outbreak heuristics + anonymised sync export |
| Privacy posture | Mixed cloud patterns | Default local-first, delayed anonymised sync |

## Architecture

MedLingua is built with Flutter for cross-platform compatibility, using Provider for state management. The core AI pipeline flows through several coordinated services:

**GemmaService** - The central AI engine loads Gemma 4 E4B via MediaPipe's LLM Inference API. It constructs system prompts establishing the model as a WHO IMCI-trained triage assistant, instructing it to respond in the patient's language with structured JSON containing severity classification, diagnosis, recommendations, danger signs, and confidence scores.

**ModelManager** - Handles model lifecycle: detecting available models on device storage, downloading from HuggingFace (`litert-community/gemma-4-E4B-it-litert-lm`), and providing fallback to the smaller E2B variant (2.3B effective parameters) for devices with limited storage.

**VoiceService** - Integrates speech-to-text for hands-free symptom input and text-to-speech for reading assessments aloud. TTS is configured with a slow speech rate (0.45) for medical clarity. Supports dictation in all 12 languages via platform STT engines.

**DatabaseService** - All encounters are stored in a local SQLite database with 14 fields per record. No data leaves the device by default, addressing privacy concerns in healthcare contexts.

**Referral Engine** - For emergency and urgent cases, MedLingua generates explicit referral recommendations with urgency level (IMMEDIATE or WITHIN HOURS), transport instructions, and a transparent "what this system did not check" disclaimer - ensuring health workers know the limits of the AI assessment.

**DoseCheckService** - An on-device WHO Essential Medicines formulary containing 10 first-line drugs (Amoxicillin, Paracetamol, ORS, Zinc, Artemether-Lumefantrine, Cotrimoxazole, Ibuprofen, Metronidazole, Gentamicin, Vitamin A) with weight-based and age-based dosing rules. When Gemma 4 recommends a medication, it calls the `dose_check` tool via function calling; the service calculates the correct dose from local data - no network required. It also exposes an `interaction_check` tool that evaluates 5 known drug-pair interactions (e.g., Gentamicin + Ibuprofen -> SEVERE nephrotoxicity risk). Results are displayed on the triage result screen alongside the severity assessment.

**SyncService** - A delayed-sync outbreak surveillance engine. Every encounter is anonymised (patient names and raw symptoms stripped, retaining only age group, gender, language, severity, and diagnosis) and queued locally. When connectivity becomes available, supervisors can export a JSON sync package. The service also runs outbreak detection heuristics: >=3 emergency cases in 24 hours, >=5 matching diagnoses in 7 days, or a critical-case ratio above 50% all trigger alert signals. This transforms individual triage events into district-level epidemiological intelligence without ever exposing patient identity.

**Supervisor Dashboard** - Aggregates encounter data across time windows (today, 7 days, 30 days) to surface community-level insights: severity distribution, daily encounter trends, common diagnoses, language breakdown, automated **alert signals**, and a **data sync panel** for exporting anonymised packages and marking synced status.

The multimodal pipeline works as follows: text symptoms are sent directly to Gemma 4; images (wound/skin photos) are preprocessed through a TFLite vision model that extracts visual features before being combined with the text prompt; audio (cough recordings) passes through an audio classification model. All modalities converge into a single prompt that Gemma 4 processes to produce a structured triage assessment.

## Clinical Safety Boundaries and Known Limitations

MedLingua is a decision-support system for trained health workers. It is not a diagnostic replacement for licensed clinicians.

- **Human-in-the-loop required**: Final triage and treatment decisions remain with the CHW and supervising clinical authority.
- **Not a substitute for labs/imaging**: The system cannot run blood tests, imaging, or full physical examination.
- **Over-triage tendency**: Current model behavior favors safety via over-triage in some non-emergency cases.
- **Limited benchmark size**: Current benchmark includes 18 authored cases; broader external validation is still needed.
- **Formulary scope**: Dose and interaction checks currently cover a focused list of first-line medications.
- **Connectivity assumptions**: While inference is fully offline, sync/export actions require intermittent connectivity.

Safety controls currently implemented in-product:

- Explicit referral urgency labels (IMMEDIATE/WITHIN HOURS)
- Transparency disclaimer listing what the model did not evaluate
- Structured output schema with danger-sign extraction
- Local-first storage and anonymised delayed sync

## Fine-Tuning on Medical Data

We fine-tune Gemma 4 E4B using Unsloth's 4-bit QLoRA implementation. The training data pipeline merges four sources:

1. **WHO IMCI Protocol Decision Trees** — Converted into conversational format. Each IMCI decision node becomes a symptom-assessment pair with the correct severity classification and recommended actions.
2. **Multilingual Medical Translations** — Symptom descriptions and medical terminology translated across all 12 supported languages, ensuring the model can triage in any target language.
3. **MedMCQA** — Medical multiple-choice QA from AIIMS/NEET exams, providing broad medical knowledge grounding.
4. **HealthCareMagic** — Real doctor-patient dialogues teaching conversational medical reasoning.

The fine-tuning applies LoRA adapters to all attention projections (q, k, v, o) and MLP layers (gate, up, down), using rank 32 with alpha 64. We train with SFTTrainer using chat template formatting and sequence packing for efficiency. Of the model's 6.3B total parameters, only 84.8M (1.34%) are trainable through LoRA, keeping the fine-tuning efficient.

Training runs on the University of Georgia's Sapelo2 HPC cluster using NVIDIA A100-SXM4-80GB GPUs with Unsloth's 4-bit QLoRA implementation. Training completed 1,902 steps across 3 epochs in 43 minutes, achieving a final training loss of 1.362 (down from 11.76 at start). The fine-tuned LoRA adapter (324MB) is deployed alongside the base model for on-device inference.

## Benchmarking

Our evaluation suite tests the fine-tuned model against 18 medical triage scenarios covering emergency, urgent, standard, and routine severity levels across 11 clinical categories, including 3 multilingual cases (French, Spanish, Swahili).

**Results:**

| Metric | Score |
|---|---|
| Severity Classification Accuracy | 61.1% |
| JSON Compliance Rate | 77.8% |
| IMCI Keyword Adherence | 63.4% |
| Recommendation Rate | 77.8% |
| Danger Signs Detection | 77.8% |
| Avg Inference Latency (A100) | 35.3s |

**Critical safety finding**: The model achieves **100% accuracy on emergency cases** (7/7 correct). All misclassifications are false positives - the model over-triages (e.g., classifying "routine" as "standard" or "urgent") rather than under-triaging. This is the safer failure mode in medical triage, ensuring no emergency is missed in this benchmark.

**Label granularity note**: The WHO IMCI protocol uses broad triage bands, and the distinction between "routine" and "standard" is clinically narrow - both indicate non-urgent, scheduled follow-up. When these two adjacent severity levels are merged into a single "non-urgent" class (reflecting real-world clinical practice where the actionable decision is the same), **accuracy rises to 77.8%** (14/18). The 4-class breakdown is reported for transparency, but the 3-class grouping (emergency / urgent / non-urgent) better reflects how CHWs act on triage results in the field.

**Per-category highlights**: 100% accuracy on critical illness, dehydration, neurological, maternal, and infectious disease categories. Multilingual performance at 67% accuracy with strong emergency detection in French and Spanish.

**Benchmark scope**: This evaluation covers 18 hand-crafted clinical vignettes across 11 categories and 3 languages. While the test set is intentionally compact (designed for rapid iteration during QLoRA fine-tuning on HPC), it spans the full severity spectrum and common IMCI presentation types. Each case was authored to match real CHW encounter patterns, prioritizing clinical diversity over volume. We report per-category breakdowns and a full confusion matrix in `training/output/benchmark_results.json` for reproducibility.

**Evaluation procedure**: Ground-truth labels were assigned from WHO IMCI guidance and reviewed during benchmark construction. Each case is scored for severity, JSON schema validity, recommendation presence, and danger-sign extraction. This is a development benchmark for model iteration, not a formal clinical trial.

## Deployment Constraints and Operational Profile

- **Model footprint**: 3.65 GB for Gemma 4 E4B LiteRT model file
- **Storage requirement**: Additional space for local SQLite history and export packages
- **Fallback path**: E2B model variant for lower-resource devices
- **Inference mode**: Fully on-device for triage; no cloud dependency for assessment generation
- **Sync mode**: Optional delayed export when connectivity is available

Current latency reported in this writeup is from A100-based benchmarking for rapid evaluation throughput. Device-level latency profiling on representative Android hardware is the next deployment validation step and will be reported in a future update.

## Language Support

MedLingua supports 12 languages chosen based on CHW population distribution and healthcare need:

English, Nigerian Pidgin (Naija), Hausa, Yoruba, Twi (Akan), Swahili, French, Hindi, Bengali, Portuguese, Spanish, and Arabic. This covers major languages across West Africa, East Africa, South Asia, and Latin America — regions with the highest CHW density and child mortality rates.

The system prompt instructs Gemma 4 to respond in the detected input language, and the voice I/O system handles language-specific STT/TTS locales.

## Impact & Future Work

MedLingua addresses UN Sustainable Development Goal 3 (Good Health and Well-Being) by expanding access to evidence-based triage support in low-connectivity settings. A single phone deployment can support frontline CHW workflows for triage, referral, and follow-up where connectivity and clinical staffing are constrained.

**Three layers of impact:**
- **Personal**: A CHW makes faster, more accurate triage decisions in their native language. Emergency cases get flagged for immediate referral — no child is sent home when they need a hospital.
- **Institutional**: The Supervisor Dashboard gives clinic managers real-time visibility into caseloads, severity trends, and common conditions across their community.
- **Public health**: Automated alert signals detect emergency clusters and recurring diagnoses, surfacing early outbreak indicators that would otherwise go unnoticed until it was too late.

**Future directions**:
- Expanding to iOS for broader device coverage
- Adding more regional languages (Igbo, Amharic, Zulu)
- Integrating with national health information systems for anonymized epidemiological surveillance
- On-device model updates via periodic sync when connectivity is available
- Clinical validation studies with partner health organizations

## Reproducibility Checklist

Use this checklist so reviewers can quickly verify claims:

1. Clone repository and install dependencies.
2. Download model file(s) using `scripts/download_model.sh`.
3. Run app in offline mode and execute the included triage demo case from this writeup.
4. Run benchmark script (`training/benchmark.py`) and export JSON results.
5. Compare generated metrics against values reported in this document.
6. Inspect confusion matrix and per-case outputs in `training/output/benchmark_results.json`.

For strict reproducibility, pin the exact project revision used for submission:

- **Git commit/tag**: `[ADD_SUBMISSION_COMMIT_OR_TAG]`
- **Benchmark config/prompt version**: `[ADD_CONFIG_ID_OR_FILE_PATH]`
- **Demo build artifact**: `[ADD_APK_OR_WEB_BUILD_LINK]`

## Technical Stack

- **App**: Flutter 3.x, Provider, Material Design 3
- **On-device AI**: Gemma 4 E4B via MediaPipe LiteRT (function calling for dose_check, interaction_check, classify_triage)
- **Dose Formulary**: WHO Essential Medicines (10 drugs, 5 interaction pairs, weight/age-based dosing)
- **Sync**: Delayed-sync outbreak surveillance with anonymised JSON export
- **Fine-Tuning**: Unsloth, 4-bit QLoRA, Gemma 4 E4B, SFTTrainer
- **Training Infrastructure**: UGA Sapelo2 HPC (A100-SXM4-80GB, SLURM)
- **Data**: WHO IMCI, MedMCQA, HealthCareMagic, custom multilingual translations
- **Storage**: SQLite (local, offline, private)
- **Voice**: speech_to_text, flutter_tts (12 language locales)

## Links

- **GitHub**: https://github.com/adetayookunoye/medlingua
- **Demo Video**: [ADD_FINAL_VIDEO_URL]
- **Model Weights**: https://huggingface.co/adeto/medlingua-gemma4-lora
- **Benchmark Results**: See `training/output/benchmark_results.json`
