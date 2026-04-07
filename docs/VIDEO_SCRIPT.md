# MedLingua — 3-Minute Video Script

> **Target**: 3 minutes | **Judging Weight**: 30% of score
> **Tone**: Urgent but hopeful — this is about saving children's lives
> **Format**: Screen recording + voiceover + b-roll suggestions

---

## [0:00 – 0:25] THE PROBLEM (Hook)

**[VISUAL: Map of sub-Saharan Africa, statistics fading in]**

> "Every year, over five million children under age five die from preventable causes. Most of these deaths happen in rural communities across sub-Saharan Africa and South Asia — places where a Community Health Worker is often the only link to healthcare."

**[VISUAL: Stock photo/video of CHW in village setting with phone]**

> "These health workers make life-or-death triage decisions every day, but they face three critical barriers: limited medical training, no internet connectivity, and language gaps between clinical protocols and the communities they serve."

**[VISUAL: Quick montage — no signal bars, WHO manual in English, confused patient interaction]**

> "We built MedLingua to solve all three."

---

## [0:25 – 0:50] THE SOLUTION (Overview)

**[VISUAL: MedLingua app icon → splash screen → home screen]**

> "MedLingua is a mobile app that puts an AI-powered medical triage assistant directly on a health worker's phone. It runs completely offline, speaks twelve languages including Hausa, Yoruba, Swahili, and Pidgin, and follows the WHO's evidence-based IMCI protocols."

**[VISUAL: Quick highlight — language selector showing all 12 languages]**

> "Powered by Google's Gemma 4 E4B model running on-device through MediaPipe LiteRT, MedLingua turns a phone into a clinical decision support tool that works anywhere — no internet, no cloud, no cost."

---

## [0:50 – 1:50] LIVE DEMO (Core of the video)

### Text Triage [0:50 – 1:10]

**[VISUAL: Screen recording of the app]**

> "Let me show you how it works. A health worker opens the triage screen, enters the patient's name and age..."

**[TYPE: "Child 3 years, high fever for 3 days, fast breathing, refuses to drink"]**

> "...types in the symptoms they're observing, and taps Assess."

**[VISUAL: Loading animation → Result screen with EMERGENCY severity badge]**

> "Gemma 4 instantly classifies this as an Emergency — possible pneumonia — and provides specific recommendations: start antibiotics, give ORS, and refer to the nearest hospital immediately. All following WHO IMCI protocols."

### Voice Input [1:10 – 1:25]

**[VISUAL: Tap microphone icon, speak symptoms]**

> "For health workers who can't type easily, MedLingua supports voice input. Tap the microphone, describe symptoms in any supported language..."

**[VISUAL: Switch language to Hausa (or Swahili), dictate symptoms]**

> "...and the app transcribes and processes everything in that language. The assessment comes back in the same language the worker speaks."

### Multimodal — Image [1:25 – 1:40]

**[VISUAL: Tap camera icon, capture/select a wound photo]**

> "MedLingua is multimodal. Health workers can photograph a wound or skin condition, and Gemma 4's vision capability analyzes the image alongside the text symptoms for a more accurate assessment."

### History & Dashboard [1:40 – 1:50]

**[VISUAL: Navigate to History tab, then Dashboard]**

> "Every encounter is saved locally. The dashboard shows triage statistics — how many emergencies this week, most common conditions — giving health organizations visibility into community health patterns."

---

## [1:50 – 2:25] TECHNICAL DEPTH (How Gemma 4 is used)

**[VISUAL: Architecture diagram from README]**

> "Under the hood, MedLingua uses Gemma 4 E4B — eight billion parameters with four-point-five billion effective through selective activation. The model runs entirely on-device as a three-point-six-five gigabyte LiteRT file."

**[VISUAL: Code snippet showing system prompt / function calling setup]**

> "We use Gemma 4's native function calling to get structured JSON responses — severity level, diagnosis, recommendations, danger signs, and confidence score. This structured output is critical for medical applications where free-text responses aren't reliable enough."

**[VISUAL: Fine-tuning pipeline diagram or notebook screenshot]**

> "We fine-tuned Gemma 4 using Unsloth with four-bit QLoRA on a combination of WHO IMCI protocol data, medical QA datasets, and multilingual medical translations across all twelve languages. Training ran on A100 GPUs at the University of Georgia's Sapelo2 HPC cluster."

**[VISUAL: Benchmark results table/chart]**

> "Our benchmarks show [X]% severity classification accuracy and [X]% JSON compliance across eighteen test cases in five languages."

---

## [2:25 – 2:55] IMPACT & VISION

**[VISUAL: Map showing target regions highlighted — West Africa, East Africa, South Asia]**

> "MedLingua directly addresses UN Sustainable Development Goal 3 — Good Health and Well-Being. A single phone loaded with this app can serve an entire village's primary triage needs."

> "The twelve languages we support cover the highest-need regions: Hausa and Yoruba for Nigeria's 200 million people, Swahili for East Africa, Hindi and Bengali for South Asia, and French for Central and West Africa."

**[VISUAL: Side-by-side — before (CHW with paper manual) vs after (CHW with MedLingua)]**

> "We envision a future where no child dies because a health worker didn't have the knowledge or tools to recognize an emergency. MedLingua puts that knowledge in their pocket, in their language, available anytime."

---

## [2:55 – 3:00] CLOSE

**[VISUAL: MedLingua logo + tagline]**

> "MedLingua — offline multilingual medical triage, powered by Gemma 4. Saving lives, one assessment at a time."

**[VISUAL: GitHub URL, model weights URL, demo link]**

---

## Production Notes

- **Screen recording tool**: Use Android screen recorder or scrcpy for high-quality capture
- **Voiceover**: Record in a quiet room, use a lapel mic, speak slowly and clearly
- **B-roll**: Stock footage of CHWs available from WHO, UNICEF media libraries (Creative Commons)
- **Music**: Subtle, hopeful background track — keep volume low so narration is clear
- **Resolution**: Record at 1080p minimum, 16:9 aspect ratio
- **Timing tip**: The demo section (0:50-1:50) should feel brisk — practice the app interactions beforehand so there's no fumbling
- **Benchmark numbers**: Fill in [X]% placeholders after running `python training/benchmark.py`
