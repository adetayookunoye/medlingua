# MedLingua

**Offline Multilingual Medical Triage for Community Health Workers — Powered by Gemma 4**

[![Gemma 4 Good Hackathon](https://img.shields.io/badge/Gemma%204%20Good-Hackathon%202025-blue)](https://www.kaggle.com/competitions/gemma-4-good)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![License](https://img.shields.io/badge/License-Apache%202.0-green)](LICENSE)

MedLingua is a mobile-first application that brings AI-powered medical triage to Community Health Workers (CHWs) in low-resource settings. It runs **entirely offline** on Android devices using Google's **Gemma 4 E4B** model via MediaPipe LiteRT, supporting **12 languages** including several African languages, and following **WHO IMCI** (Integrated Management of Childhood Illness) protocols.

---

## The Problem

Over **5 million children** under age 5 die each year, with most deaths occurring in sub-Saharan Africa and South Asia. Community Health Workers — often the only healthcare access for rural populations — must make rapid triage decisions with limited training, inconsistent connectivity, and language barriers.

## Our Solution

MedLingua puts a Gemma 4-powered medical assistant directly on a CHW's phone. It works without internet, speaks the community's language, and follows evidence-based WHO IMCI protocols to classify patients into severity levels: **Emergency → Urgent → Standard → Routine**.

### Key Features

| Feature | Description |
|---------|-------------|
| **Offline-First AI** | Gemma 4 E4B runs on-device via MediaPipe LiteRT — no internet required |
| **12 Languages** | English, Pidgin (Naija), Hausa, Yoruba, Twi, Swahili, French, Hindi, Bengali, Portuguese, Spanish, Arabic |
| **Multimodal Input** | Text symptoms, camera (wound/skin photos), voice dictation, and audio classification |
| **WHO IMCI Protocols** | Evidence-based severity classification with structured function calling |
| **Voice I/O** | Speech-to-text input and text-to-speech output for low-literacy users |
| **Encounter History** | All assessments saved locally in SQLite with search and statistics |
| **Demo Mode** | Keyword-based fallback when model isn't downloaded — no GPU needed for testing |

---

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                    MedLingua Flutter App                  │
├──────────────────────────────────────────────────────────┤
│  UI Layer                                                │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────────┐  │
│  │Dashboard │ │ Triage   │ │ History  │ │  Settings  │  │
│  │ Screen   │ │ Screen   │ │ Screen   │ │  Screen    │  │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └─────┬──────┘  │
│       └─────────┬───┴───────────┴──────────────┘         │
│                 ▼                                        │
│  ┌─────────────────────────────────┐                     │
│  │       AppProvider (State)       │ ◄── ChangeNotifier  │
│  └────┬──────────┬────────────┬────┘                     │
│       ▼          ▼            ▼                          │
│  ┌─────────┐ ┌─────────┐ ┌──────────┐                   │
│  │ Gemma   │ │  Voice  │ │ Database │                    │
│  │ Service │ │ Service │ │ Service  │                    │
│  └────┬────┘ └─────────┘ └──────────┘                    │
│       │                                                  │
│  ┌────┴───────────────────────────────────┐              │
│  │          Model Manager                 │              │
│  │  ┌────────────┐  ┌─────────────────┐   │              │
│  │  │  Vision    │  │ Audio           │   │              │
│  │  │  Service   │  │ Classification  │   │              │
│  │  └────────────┘  └─────────────────┘   │              │
│  └────────────────────────────────────────┘              │
├──────────────────────────────────────────────────────────┤
│  On-Device AI                                            │
│  ┌──────────────────────────────────────────────────┐    │
│  │ Gemma 4 E4B (8B params, 4.5B effective)          │    │
│  │ via MediaPipe LiteRT (.litertlm)                 │    │
│  │ Text + Image + Audio → Structured Triage JSON    │    │
│  └──────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────┘
```

---

## Getting Started

### Prerequisites

- **Flutter SDK** ≥ 3.7.2
- **Android SDK** with NDK for MediaPipe
- **Android device** with ≥ 4GB RAM (or emulator)
- **~3.7 GB** free storage for the Gemma 4 E4B model

### Installation

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/medlingua.git
cd medlingua

# Install Flutter dependencies
flutter pub get

# Build for Android
flutter build apk --release
```

### Download the Model

```bash
# Download Gemma 4 E4B LiteRT model and push to device
./scripts/download_model.sh e4b

# Or download the smaller E2B variant
./scripts/download_model.sh e2b
```

The model downloads from HuggingFace (`litert-community/gemma-4-E4B-it-litert-lm`) and is pushed to the device via `adb`.

### Run

```bash
# Run on connected device
flutter run

# The app works without the model in Demo Mode
# (keyword-based triage for development/testing)
```

---

## Fine-Tuning

MedLingua includes a custom fine-tuning pipeline for Gemma 4 using **Unsloth** with 4-bit QLoRA on medical triage data.

### Training Data Sources

| Dataset | Purpose |
|---------|---------|
| WHO IMCI Protocols | Evidence-based triage decision trees |
| Multilingual translations | 12-language symptom-response pairs |
| MedMCQA | Medical multiple-choice QA for general medical knowledge |
| HealthCareMagic | Doctor-patient dialogue for conversational medical reasoning |

### Run Fine-Tuning

```bash
# Local (requires NVIDIA GPU with ≥16GB VRAM)
pip install -r training/requirements.txt
python training/prepare_dataset.py
python training/finetune.py

# On Sapelo2 HPC cluster (A100-SXM4-80GB)
sbatch training/sapelo2_finetune.sh
```

### Benchmark

```bash
python training/benchmark.py --model training/output/medlingua-lora
```

Evaluates:
- Severity classification accuracy (emergency/urgent/standard/routine)
- JSON function-call compliance rate
- WHO IMCI keyword adherence
- Multilingual performance (French, Spanish, Swahili test cases)
- Inference latency

### Export for Mobile

```bash
python training/export_model.py --adapter training/output/medlingua-lora
```

---

## How Gemma 4 Is Used

MedLingua leverages **Gemma 4 E4B** (8B total parameters, 4.5B effective) for on-device inference:

1. **System Prompt** — Establishes the role as a WHO IMCI-trained triage assistant responding in the patient's language
2. **Structured Function Calling** — Model outputs JSON with `severity`, `diagnosis`, `recommendation`, `danger_signs`, and `confidence`
3. **Multimodal Input** — Vision service processes wound/skin photos; audio service classifies respiratory sounds (cough patterns)
4. **Temperature Tuning** — Uses `temperature: 0.3` for medical accuracy (lower randomness for clinical decisions)
5. **Fine-Tuned Weights** — QLoRA-adapted on medical triage conversations across 12 languages

### Why Gemma 4 E4B?

- **On-device deployment** — 3.65 GB LiteRT model runs without internet
- **Multimodal native** — Text, image, and audio understanding built-in
- **Efficient architecture** — 4.5B effective parameters from 8B total via selective activation
- **128K context window** — Handles detailed patient histories
- **Apache 2.0 license** — Free for commercial and humanitarian use

---

## Project Structure

```
medlingua/
├── lib/
│   ├── main.dart                    # App entry point + splash screen
│   ├── models/
│   │   ├── language.dart            # 12 supported languages
│   │   └── triage_encounter.dart    # Patient encounter data model
│   ├── providers/
│   │   └── app_provider.dart        # Central state management
│   ├── screens/
│   │   ├── dashboard_screen.dart    # Stats overview
│   │   ├── home_screen.dart         # Main navigation
│   │   ├── triage_screen.dart       # Patient intake form
│   │   ├── result_screen.dart       # Triage assessment results
│   │   ├── history_screen.dart      # Past encounters
│   │   └── settings_screen.dart     # Model & language config
│   ├── services/
│   │   ├── gemma_service.dart       # Core AI engine (Gemma 4)
│   │   ├── model_manager.dart       # Model download & lifecycle
│   │   ├── voice_service.dart       # Speech-to-text / TTS
│   │   └── database_service.dart    # SQLite persistence
│   ├── theme/
│   │   └── app_theme.dart           # Material Design 3 theme
│   └── widgets/                     # Reusable UI components
├── training/
│   ├── finetune.py                  # Unsloth 4-bit QLoRA training
│   ├── prepare_dataset.py           # Multi-source data pipeline
│   ├── export_model.py              # LoRA merge + GGUF export
│   ├── benchmark.py                 # Evaluation metrics
│   ├── sapelo2_finetune.sh          # HPC SLURM job script
│   ├── requirements.txt             # Python dependencies
│   └── MedLingua_FineTune.ipynb     # Interactive notebook walkthrough
├── scripts/
│   └── download_model.sh            # Model download + adb push
├── test/
│   └── widget_test.dart             # Flutter widget tests
└── android/                         # Android build configuration
```

---

## Supported Languages

| Language | Code | STT Locale | Region |
|----------|------|-----------|--------|
| English | en | en_US | Global |
| Pidgin (Naija) | pcm | en_NG | Nigeria |
| Hausa | ha | ha_NG | Nigeria / West Africa |
| Yoruba | yo | yo_NG | Nigeria / West Africa |
| Twi (Akan) | tw | ak_GH | Ghana |
| Swahili | sw | sw_KE | East Africa |
| French | fr | fr_FR | West/Central Africa |
| Hindi | hi | hi_IN | South Asia |
| Bengali | bn | bn_IN | South Asia |
| Portuguese | pt | pt_BR | Lusophone Africa |
| Spanish | es | es_ES | Latin America |
| Arabic | ar | ar_SA | North Africa / MENA |

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **Frontend** | Flutter 3.x, Material Design 3, Provider |
| **On-Device AI** | Gemma 4 E4B via MediaPipe LiteRT |
| **Voice** | speech_to_text, flutter_tts |
| **Vision** | TFLite Flutter, Camera API |
| **Storage** | SQLite (sqflite), SharedPreferences |
| **Fine-Tuning** | Unsloth, QLoRA, HuggingFace Transformers |
| **HPC** | UGA Sapelo2 (A100-SXM4-80GB, SLURM) |

---

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/improvement`)
3. Make your changes and add tests
4. Run tests: `flutter test`
5. Submit a pull request

---

## License

This project is licensed under the Apache License 2.0 — see [LICENSE](LICENSE) for details.

## Acknowledgments

- **Google** — Gemma 4 model family and MediaPipe LiteRT
- **WHO** — IMCI clinical protocols for childhood illness management
- **Unsloth** — Efficient fine-tuning with 4-bit QLoRA
- **University of Georgia** — Sapelo2 HPC cluster for model training
- **Kaggle** — Gemma 4 Good Hackathon platform
