# MedLingua: Offline Multilingual Medical Triage Powered by Gemma 4

## Summary

MedLingua is a mobile application that brings AI-powered medical triage to Community Health Workers (CHWs) in low-resource settings. Running entirely offline on Android devices using Google's Gemma 4 E4B model via MediaPipe LiteRT, it supports 12 languages — including several African languages — and follows WHO IMCI protocols to classify patients by severity. This writeup covers the problem, architecture, Gemma 4 integration, fine-tuning approach, and impact potential.

## The Problem

Every year, over 5 million children under age 5 die from preventable causes. The majority of these deaths occur in sub-Saharan Africa and South Asia, regions where Community Health Workers are often the only healthcare access point for rural populations. These CHWs face three compounding challenges: limited medical training for complex triage decisions, unreliable or nonexistent internet connectivity, and language barriers between clinical protocols (written in English or French) and the communities they serve (speaking local languages like Hausa, Yoruba, Twi, or Swahili).

Existing mobile health tools require constant internet connectivity, operate only in major languages, or provide generic health information rather than actionable triage guidance. CHWs need a tool that works in the field — offline, in their language, following the evidence-based protocols they were trained on.

## Why Gemma 4?

Gemma 4 E4B is uniquely suited for this application:

- **On-device deployment**: The 3.65 GB LiteRT model runs entirely on the phone without internet — critical for rural areas with no connectivity
- **Efficient architecture**: 8B total parameters with only 4.5B effective parameters via selective activation, enabling fast inference on mobile hardware
- **Multimodal native**: Built-in understanding of text, images, and audio — CHWs can photograph wounds, describe symptoms verbally, or type them
- **128K context window**: Handles detailed patient histories without truncation
- **Function calling**: Gemma 4's structured output capability produces consistent JSON triage assessments rather than free-text responses
- **Apache 2.0 license**: Enables free deployment in humanitarian settings

We specifically chose E4B over the larger 26B or 31B variants because on-device inference is a hard requirement — CHWs cannot depend on cloud APIs in the field.

## Architecture

MedLingua is built with Flutter for cross-platform compatibility, using Provider for state management. The core AI pipeline flows through several coordinated services:

**GemmaService** — The central AI engine loads Gemma 4 E4B via MediaPipe's LLM Inference API. It constructs system prompts establishing the model as a WHO IMCI-trained triage assistant, instructing it to respond in the patient's language with structured JSON containing severity classification, diagnosis, recommendations, danger signs, and confidence scores.

**ModelManager** — Handles model lifecycle: detecting available models on device storage, downloading from HuggingFace (`litert-community/gemma-4-E4B-it-litert-lm`), and providing fallback to the smaller E2B variant (2.3B effective parameters) for devices with limited storage.

**VoiceService** — Integrates speech-to-text for hands-free symptom input and text-to-speech for reading assessments aloud. TTS is configured with a slow speech rate (0.45) for medical clarity. Supports dictation in all 12 languages via platform STT engines.

**DatabaseService** — All encounters are stored in a local SQLite database with 14 fields per record. No data leaves the device, addressing privacy concerns in healthcare contexts.

The multimodal pipeline works as follows: text symptoms are sent directly to Gemma 4; images (wound/skin photos) are preprocessed through a TFLite vision model that extracts visual features before being combined with the text prompt; audio (cough recordings) passes through an audio classification model. All modalities converge into a single prompt that Gemma 4 processes to produce a structured triage assessment.

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

**Critical safety finding**: The model achieves **100% accuracy on emergency cases** (7/7 correct). All misclassifications are false positives — the model over-triages (e.g., classifying "routine" as "standard" or "urgent") rather than under-triaging. This is the safer failure mode in medical triage, ensuring no emergency is missed.

**Per-category highlights**: 100% accuracy on critical illness, dehydration, neurological, maternal, and infectious disease categories. Multilingual performance at 67% accuracy with strong emergency detection in French and Spanish.

## Language Support

MedLingua supports 12 languages chosen based on CHW population distribution and healthcare need:

English, Nigerian Pidgin (Naija), Hausa, Yoruba, Twi (Akan), Swahili, French, Hindi, Bengali, Portuguese, Spanish, and Arabic. This covers major languages across West Africa, East Africa, South Asia, and Latin America — regions with the highest CHW density and child mortality rates.

The system prompt instructs Gemma 4 to respond in the detected input language, and the voice I/O system handles language-specific STT/TTS locales.

## Impact & Future Work

MedLingua addresses UN Sustainable Development Goal 3 (Good Health and Well-Being) by democratizing access to evidence-based medical triage. A single phone loaded with MedLingua can serve an entire village's primary care needs without connectivity infrastructure.

**Immediate impact**: CHWs can make faster, more accurate triage decisions by following structured, AI-guided assessments in their native language. Emergency cases get flagged immediately for referral rather than being missed.

**Future directions**:
- Expanding to iOS for broader device coverage
- Adding more regional languages (Igbo, Amharic, Zulu)
- Integrating with national health information systems for anonymized epidemiological surveillance
- On-device model updates via periodic sync when connectivity is available
- Clinical validation studies with partner health organizations

## Technical Stack

- **App**: Flutter 3.x, Provider, Material Design 3
- **On-Device AI**: Gemma 4 E4B via MediaPipe LiteRT
- **Fine-Tuning**: Unsloth, 4-bit QLoRA, Gemma 4 E4B, SFTTrainer
- **Training Infrastructure**: UGA Sapelo2 HPC (A100-SXM4-80GB, SLURM)
- **Data**: WHO IMCI, MedMCQA, HealthCareMagic, custom multilingual translations
- **Storage**: SQLite (local, offline, private)
- **Voice**: speech_to_text, flutter_tts (12 language locales)

## Links

- **GitHub**: https://github.com/adetayookunoye/medlingua
- **Demo Video**: [Video URL]
- **Model Weights**: [HuggingFace URL]
- **Benchmark Results**: See `training/output/benchmark_results.json`
