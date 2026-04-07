import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_mediapipe_chat/flutter_mediapipe_chat.dart';
import 'model_manager.dart';
import 'vision_service.dart';
import 'audio_classification_service.dart';

/// Service for on-device Gemma 4 inference via MediaPipe LLM Inference API
///
/// This is the core AI engine of MedLingua. It handles:
/// 1. Loading Gemma 4 E4B model on-device
/// 2. Processing multimodal inputs (text + image)
/// 3. Generating triage assessments following WHO IMCI protocols
/// 4. Function calling for structured output (severity, diagnosis, recommendation)
class GemmaService {
  final FlutterMediapipeChat _chat = FlutterMediapipeChat();
  final ModelManager _modelManager = ModelManager.instance;
  final VisionService _visionService = VisionService();
  final AudioClassificationService _audioService = AudioClassificationService();

  bool _isModelLoaded = false;
  bool _isProcessing = false;

  /// Set to true to use keyword-matching demo responses instead of the model.
  /// Useful for testing UI without the model file present.
  bool useDemoMode = false;

  bool get isModelLoaded => _isModelLoaded;
  bool get isProcessing => _isProcessing;

  /// Expose the model manager so the UI can observe download progress.
  ModelManager get modelManager => _modelManager;

  /// Expose vision service for direct image analysis.
  VisionService get visionService => _visionService;

  /// Expose audio classification service.
  AudioClassificationService get audioService => _audioService;

  /// Check whether any supported model file exists on-device.
  Future<bool> isModelDownloaded() async {
    return _modelManager.isModelAvailable();
  }

  /// Initialize and load the Gemma model on-device.
  ///
  /// Auto-detects available model files via [ModelManager] and loads the best
  /// one. Falls back to demo mode if no model is found.
  Future<void> loadModel() async {
    try {
      // Initialize multimodal services in parallel
      await Future.wait([
        _visionService.initialize(),
        _audioService.initialize(),
      ]);

      final found = await _modelManager.autoDetect();

      if (!found) {
        debugPrint('GemmaService.loadModel: No model found — entering demo mode');
        useDemoMode = true;
        _isModelLoaded = true;
        return;
      }

      final path = await _modelManager.modelPath;

      if (!File(path).existsSync()) {
        debugPrint('GemmaService.loadModel: Model file missing at $path — entering demo mode');
        useDemoMode = true;
        _isModelLoaded = true;
        return;
      }

      final config = ModelConfig(
        path: path,
        maxTokens: 1024,
        temperature: 0.3, // Low temp for medical accuracy
        topK: 20,
        randomSeed: 0,
      );

      await _chat.loadModel(config);

      useDemoMode = false;
      _isModelLoaded = true;
      debugPrint('GemmaService.loadModel: Loaded ${_modelManager.activeModel.displayName} from $path');
    } catch (e, stackTrace) {
      debugPrint('GemmaService.loadModel: Error: $e\n$stackTrace');
      // Fall back to demo mode so the app remains functional
      useDemoMode = true;
      _isModelLoaded = true;
    }
  }

  /// Process a triage request with text symptoms
  Future<TriageResponse> processTextTriage({
    required String symptoms,
    required String language,
    int? patientAge,
    String? patientGender,
  }) async {
    _isProcessing = true;

    try {
      final prompt = _buildTriagePrompt(
        symptoms: symptoms,
        language: language,
        patientAge: patientAge,
        patientGender: patientGender,
      );

      debugPrint('GemmaService.processTextTriage: Prompt length: ${prompt.length} chars');

      if (useDemoMode) {
        await Future.delayed(const Duration(seconds: 2));
        return _generateDemoResponse(symptoms, language);
      }

      final responseText = await _chat.generateResponse(prompt);
      if (responseText == null || responseText.isEmpty) {
        debugPrint('GemmaService.processTextTriage: Empty response — falling back to demo');
        return _generateDemoResponse(symptoms, language);
      }

      debugPrint('GemmaService.processTextTriage: Raw response length: ${responseText.length}');
      return _parseTriageResponse(responseText);
    } catch (e, stackTrace) {
      debugPrint('GemmaService.processTextTriage: Error: $e\n$stackTrace');
      return _generateDemoResponse(symptoms, language);
    } finally {
      _isProcessing = false;
    }
  }

  /// Process a triage request with image (wound/skin/rash photo)
  ///
  /// Uses VisionService for image classification, then fuses the visual
  /// findings with the LLM prompt for multi-modal triage assessment.
  Future<TriageResponse> processImageTriage({
    required String imagePath,
    String? additionalSymptoms,
    required String language,
    int? patientAge,
    String? patientGender,
  }) async {
    _isProcessing = true;

    try {
      // Step 1: Analyze image with VisionService
      VisionResult? visionResult;
      try {
        visionResult = await _visionService.analyzeImage(imagePath);
        debugPrint('GemmaService.processImageTriage: Vision result: $visionResult');
      } catch (e) {
        debugPrint('GemmaService.processImageTriage: Vision analysis failed: $e');
      }

      if (useDemoMode) {
        await Future.delayed(const Duration(seconds: 2));
        return _generateDemoImageResponse(language, visionResult: visionResult);
      }

      // Step 2: Build multi-modal prompt combining vision findings + symptoms
      final prompt = _buildImageTriagePrompt(
        additionalSymptoms: additionalSymptoms,
        language: language,
        patientAge: patientAge,
        patientGender: patientGender,
        visionFindings: visionResult?.findings,
        visionCategory: visionResult?.category,
        visionTriageHint: visionResult?.triageHint,
      );

      debugPrint('GemmaService.processImageTriage: Prompt length: ${prompt.length} chars');

      final responseText = await _chat.generateResponse(prompt);
      if (responseText == null || responseText.isEmpty) {
        debugPrint('GemmaService.processImageTriage: Empty response — falling back to demo');
        return _generateDemoImageResponse(language, visionResult: visionResult);
      }

      debugPrint('GemmaService.processImageTriage: Raw response length: ${responseText.length}');
      return _parseTriageResponse(responseText);
    } catch (e, stackTrace) {
      debugPrint('GemmaService.processImageTriage: Error: $e\n$stackTrace');
      return _generateDemoImageResponse(language);
    } finally {
      _isProcessing = false;
    }
  }

  /// Process audio recording for respiratory sound classification.
  ///
  /// Analyzes cough/wheeze/stridor sounds and fuses with text symptoms
  /// for a combined multi-modal triage assessment.
  Future<TriageResponse> processAudioTriage({
    required String audioPath,
    String? additionalSymptoms,
    required String language,
    int? patientAge,
    String? patientGender,
  }) async {
    _isProcessing = true;

    try {
      // Step 1: Classify audio
      AudioClassResult? audioResult;
      try {
        audioResult = await _audioService.classifyAudio(audioPath);
        debugPrint('GemmaService.processAudioTriage: Audio result: $audioResult');
      } catch (e) {
        debugPrint('GemmaService.processAudioTriage: Audio classification failed: $e');
      }

      if (useDemoMode) {
        await Future.delayed(const Duration(seconds: 2));
        return _generateDemoAudioResponse(language, audioResult: audioResult);
      }

      // Step 2: Build prompt with audio findings
      final audioContext = audioResult != null
          ? 'Audio analysis: ${audioResult.findings}\n'
            'Detected sound: ${audioResult.category} '
            '(confidence: ${(audioResult.confidence * 100).toStringAsFixed(0)}%)\n'
            'Clinical hint: ${audioResult.triageHint}'
          : 'Audio analysis: Not available';

      final symptomText = additionalSymptoms ?? 'No additional symptoms reported';
      final prompt = '''
<system>
You are MedLingua, a medical triage assistant for Community Health Workers.
Follow WHO IMCI (Integrated Management of Childhood Illness) protocols.
Respond in $language language.

You have been provided with audio analysis results from a respiratory sound recording.
Combine the audio findings with the reported symptoms for your assessment.
You MUST use the classify_triage function to provide structured output.

IMPORTANT: You are a triage SUPPORT tool, not a doctor. Always recommend
professional medical consultation for serious conditions.
</system>

<tools>
[{
  "name": "classify_triage",
  "description": "Classify the medical triage severity and provide guidance",
  "parameters": {
    "severity": "emergency|urgent|standard|routine",
    "diagnosis": "Brief suspected condition",
    "recommendation": "Actionable steps for the CHW",
    "danger_signs": ["list of danger signs to watch for"],
    "confidence": 0.0-1.0
  }
}]
</tools>

Patient Info:
- Age: ${patientAge ?? 'Unknown'}
- Gender: ${patientGender ?? 'Unknown'}
- Additional symptoms: $symptomText
- $audioContext
- Setting: Remote community, limited medical resources

Assess the severity based on audio findings and symptoms. Provide triage guidance.
''';

      final responseText = await _chat.generateResponse(prompt);
      if (responseText == null || responseText.isEmpty) {
        return _generateDemoAudioResponse(language, audioResult: audioResult);
      }

      return _parseTriageResponse(responseText);
    } catch (e, stackTrace) {
      debugPrint('GemmaService.processAudioTriage: Error: $e\n$stackTrace');
      return _generateDemoAudioResponse(language);
    } finally {
      _isProcessing = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Prompt builders
  // ---------------------------------------------------------------------------

  /// Build the medical triage prompt following WHO IMCI guidelines
  String _buildTriagePrompt({
    required String symptoms,
    required String language,
    int? patientAge,
    String? patientGender,
  }) {
    return '''
<system>
You are MedLingua, a medical triage assistant for Community Health Workers.
Follow WHO IMCI (Integrated Management of Childhood Illness) protocols.
Respond in $language language.

You MUST use the classify_triage function to provide structured output.

IMPORTANT: You are a triage SUPPORT tool, not a doctor. Always recommend 
professional medical consultation for serious conditions.
</system>

<tools>
[{
  "name": "classify_triage",
  "description": "Classify the medical triage severity and provide guidance",
  "parameters": {
    "severity": "emergency|urgent|standard|routine",
    "diagnosis": "Brief suspected condition",
    "recommendation": "Actionable steps for the CHW",
    "danger_signs": ["list of danger signs to watch for"],
    "confidence": 0.0-1.0
  }
}]
</tools>

Patient Info:
- Age: ${patientAge ?? 'Unknown'}
- Gender: ${patientGender ?? 'Unknown'}
- Symptoms: $symptoms
- Setting: Remote community, limited medical resources

Assess the severity and provide triage guidance.
''';
  }

  /// Build prompt for image-based triage with multi-modal fusion.
  String _buildImageTriagePrompt({
    String? additionalSymptoms,
    required String language,
    int? patientAge,
    String? patientGender,
    String? visionFindings,
    String? visionCategory,
    String? visionTriageHint,
  }) {
    final symptomText = additionalSymptoms ?? 'No additional symptoms reported';
    final visionContext = visionFindings != null
        ? 'Image analysis results:\n'
          '- Category: $visionCategory\n'
          '- Findings: $visionFindings\n'
          '- Clinical hint: $visionTriageHint'
        : 'Image analysis: Not available — assess based on symptoms alone';

    return '''
<system>
You are MedLingua, a medical triage assistant for Community Health Workers.
Follow WHO IMCI (Integrated Management of Childhood Illness) protocols.
Respond in $language language.

You have been provided with image analysis results from a medical photo.
Combine the visual findings with any reported symptoms for your assessment.
You MUST use the classify_triage function to provide structured output.

IMPORTANT: You are a triage SUPPORT tool, not a doctor. Always recommend 
professional medical consultation for serious conditions.
</system>

<tools>
[{
  "name": "classify_triage",
  "description": "Classify the medical triage severity and provide guidance",
  "parameters": {
    "severity": "emergency|urgent|standard|routine",
    "diagnosis": "Brief suspected condition",
    "recommendation": "Actionable steps for the CHW",
    "danger_signs": ["list of danger signs to watch for"],
    "confidence": 0.0-1.0
  }
}]
</tools>

Patient Info:
- Age: ${patientAge ?? 'Unknown'}
- Gender: ${patientGender ?? 'Unknown'}
- Additional symptoms: $symptomText
- $visionContext
- Setting: Remote community, limited medical resources

Analyze the visual findings and assess the severity. Provide triage guidance.
''';
  }

  // ---------------------------------------------------------------------------
  // Response parsing
  // ---------------------------------------------------------------------------

  /// Parse the model's function-call response into a TriageResponse.
  TriageResponse _parseTriageResponse(String rawResponse) {
    try {
      // Try to extract JSON from the response (model may wrap it in markdown)
      final jsonMatch = RegExp(
        r'\{[^{}]*"severity"[^{}]*\}',
        dotAll: true,
      ).firstMatch(rawResponse);

      if (jsonMatch != null) {
        final json = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
        return TriageResponse(
          severity: _normalizeSeverity(json['severity'] as String? ?? 'routine'),
          diagnosis: json['diagnosis'] as String? ?? 'Assessment pending',
          recommendation: json['recommendation'] as String? ?? 'Seek professional evaluation',
          dangerSigns: (json['danger_signs'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              ['Seek immediate help if condition worsens'],
          confidence: (json['confidence'] as num?)?.toDouble() ?? 0.5,
        );
      }

      // Fallback: try to parse the whole response as JSON
      final json = jsonDecode(rawResponse) as Map<String, dynamic>;
      // Check if it's wrapped in a function call
      final params = json['parameters'] as Map<String, dynamic>? ?? json;
      return TriageResponse(
        severity: _normalizeSeverity(params['severity'] as String? ?? 'routine'),
        diagnosis: params['diagnosis'] as String? ?? 'Assessment pending',
        recommendation: params['recommendation'] as String? ?? 'Seek professional evaluation',
        dangerSigns: (params['danger_signs'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            ['Seek immediate help if condition worsens'],
        confidence: (params['confidence'] as num?)?.toDouble() ?? 0.5,
      );
    } catch (e) {
      debugPrint('GemmaService._parseTriageResponse: Parse failed: $e');
      // If parsing fails, extract what we can from free text
      return _extractFromFreeText(rawResponse);
    }
  }

  /// Normalize severity strings the model might return.
  String _normalizeSeverity(String raw) {
    final lower = raw.toLowerCase().trim();
    if (lower.contains('emergency')) return 'emergency';
    if (lower.contains('urgent')) return 'urgent';
    if (lower.contains('standard')) return 'standard';
    if (lower.contains('routine')) return 'routine';
    return 'standard';
  }

  /// Best-effort extraction from unstructured model output.
  TriageResponse _extractFromFreeText(String text) {
    final lower = text.toLowerCase();
    String severity = 'standard';
    if (lower.contains('emergency') || lower.contains('critical') || lower.contains('danger')) {
      severity = 'emergency';
    } else if (lower.contains('urgent') || lower.contains('serious')) {
      severity = 'urgent';
    } else if (lower.contains('routine') || lower.contains('mild') || lower.contains('minor')) {
      severity = 'routine';
    }

    return TriageResponse(
      severity: severity,
      diagnosis: text.length > 200 ? '${text.substring(0, 200)}...' : text,
      recommendation: 'Please review the full AI response above. '
          'Seek professional medical consultation for accurate diagnosis.',
      dangerSigns: [
        'Unable to eat or drink',
        'High fever (>38.5°C)',
        'Severe pain',
        'Condition worsening rapidly',
      ],
      confidence: 0.4,
    );
  }

  // ---------------------------------------------------------------------------
  // Demo fallback responses
  // ---------------------------------------------------------------------------

  /// Demo response for text-based triage
  TriageResponse _generateDemoResponse(String symptoms, String language) {
    final lowerSymptoms = symptoms.toLowerCase();

    if (lowerSymptoms.contains('fever') && lowerSymptoms.contains('rash')) {
      return TriageResponse(
        severity: 'urgent',
        diagnosis: 'Possible measles or viral exanthem — fever with rash requires evaluation',
        recommendation:
            '1. Check for Koplik spots (white spots inside cheeks)\n'
            '2. Monitor temperature every 2 hours\n'
            '3. Ensure adequate hydration — ORS if available\n'
            '4. Isolate from other children\n'
            '5. Refer to nearest health facility within 4 hours',
        dangerSigns: [
          'Difficulty breathing',
          'Persistent vomiting',
          'Altered consciousness',
          'Temperature above 39.5°C',
        ],
        confidence: 0.82,
      );
    } else if (lowerSymptoms.contains('diarr') || lowerSymptoms.contains('vomit')) {
      return TriageResponse(
        severity: 'urgent',
        diagnosis: 'Acute gastroenteritis with risk of dehydration',
        recommendation:
            '1. Begin oral rehydration therapy immediately (ORS)\n'
            '2. Assess dehydration: check skin turgor, dry mouth, sunken eyes\n'
            '3. Continue breastfeeding if infant\n'
            '4. Zinc supplementation if child under 5\n'
            '5. Refer if signs of severe dehydration',
        dangerSigns: [
          'Blood in stool',
          'Unable to drink or breastfeed',
          'Sunken eyes or fontanelle',
          'Very sleepy or unconscious',
        ],
        confidence: 0.88,
      );
    } else if (lowerSymptoms.contains('cough') || lowerSymptoms.contains('breath')) {
      return TriageResponse(
        severity: 'standard',
        diagnosis: 'Acute respiratory infection',
        recommendation:
            '1. Count respiratory rate for 1 full minute\n'
            '2. Check for chest indrawing\n'
            '3. Warm fluids and rest\n'
            '4. If breathing fast: possible pneumonia — refer to clinic\n'
            '5. Follow up in 2 days if no improvement',
        dangerSigns: [
          'Chest indrawing',
          'Stridor when calm',
          'Cannot drink',
          'Cyanosis (blue lips)',
        ],
        confidence: 0.79,
      );
    } else {
      return TriageResponse(
        severity: 'routine',
        diagnosis: 'Initial symptom assessment — further evaluation recommended',
        recommendation:
            '1. Record all symptoms in detail\n'
            '2. Take vital signs if equipment available\n'
            '3. Provide basic comfort measures\n'
            '4. Schedule follow-up in 2-3 days\n'
            '5. Advise to return immediately if condition worsens',
        dangerSigns: [
          'Unable to eat or drink',
          'High fever (>38.5°C)',
          'Severe pain',
          'Bleeding',
        ],
        confidence: 0.65,
      );
    }
  }

  /// Demo response for image-based triage
  TriageResponse _generateDemoImageResponse(String language, {VisionResult? visionResult}) {
    if (visionResult != null && visionResult.category != 'unknown') {
      // Use vision findings to generate a more specific demo response
      final severity = _visionCategoryToSeverity(visionResult.category);
      return TriageResponse(
        severity: severity,
        diagnosis: 'Image analysis: ${visionResult.findings}',
        recommendation:
            '1. ${visionResult.triageHint}\n'
            '2. Clean affected area with clean water and mild soap\n'
            '3. Do not apply traditional remedies\n'
            '4. Take photos for follow-up comparison\n'
            '5. Refer to health facility for clinical assessment',
        dangerSigns: [
          'Rapid spreading or worsening',
          'Signs of infection (pus, warmth, red streaks)',
          'Fever accompanying skin changes',
          'Pain increasing',
        ],
        confidence: visionResult.confidence,
      );
    }

    return TriageResponse(
      severity: 'standard',
      diagnosis: 'Skin lesion detected — requires clinical evaluation for proper identification',
      recommendation:
          '1. Clean the area with clean water and mild soap\n'
          '2. Do not apply traditional remedies\n'
          '3. Cover with clean bandage if open wound\n'
          '4. Take photos for follow-up comparison\n'
          '5. Refer to health facility for dermatological assessment',
      dangerSigns: [
        'Rapid spreading',
        'Signs of infection (pus, warmth, red streaks)',
        'Fever accompanying skin changes',
        'Pain increasing',
      ],
      confidence: 0.71,
    );
  }

  /// Demo response for audio-based triage
  TriageResponse _generateDemoAudioResponse(String language, {AudioClassResult? audioResult}) {
    if (audioResult != null && audioResult.category != 'unknown') {
      final severity = _audioCategoryToSeverity(audioResult.category);
      return TriageResponse(
        severity: severity,
        diagnosis: 'Audio analysis: ${audioResult.findings}',
        recommendation:
            '1. ${audioResult.triageHint}\n'
            '2. Count respiratory rate for 1 full minute\n'
            '3. Check for chest indrawing\n'
            '4. Monitor oxygen saturation if pulse oximeter available\n'
            '5. Refer if danger signs present',
        dangerSigns: [
          'Chest indrawing',
          'Stridor when calm',
          'Cannot drink',
          'Cyanosis (blue lips)',
          'Very fast breathing',
        ],
        confidence: audioResult.confidence,
      );
    }

    return TriageResponse(
      severity: 'standard',
      diagnosis: 'Respiratory sound analysis — clinical assessment recommended',
      recommendation:
          '1. Count respiratory rate for 1 full minute\n'
          '2. Check for chest indrawing\n'
          '3. Warm fluids and rest\n'
          '4. If breathing fast: possible pneumonia — refer to clinic\n'
          '5. Follow up in 2 days if no improvement',
      dangerSigns: [
        'Chest indrawing',
        'Stridor when calm',
        'Cannot drink',
        'Cyanosis (blue lips)',
      ],
      confidence: 0.60,
    );
  }

  String _visionCategoryToSeverity(String category) {
    switch (category) {
      case 'wound':
        return 'urgent';
      case 'burn':
        return 'urgent';
      case 'eye_condition':
        return 'urgent';
      case 'rash':
        return 'standard';
      case 'skin_lesion':
        return 'standard';
      case 'swelling':
        return 'standard';
      default:
        return 'standard';
    }
  }

  String _audioCategoryToSeverity(String category) {
    switch (category) {
      case 'stridor':
        return 'emergency';
      case 'wheeze':
        return 'urgent';
      case 'cough':
        return 'standard';
      case 'crackles':
        return 'urgent';
      case 'normal_breathing':
        return 'routine';
      default:
        return 'standard';
    }
  }

  /// Dispose of model resources
  void dispose() {
    _isModelLoaded = false;
    _visionService.dispose();
    _audioService.dispose();
    debugPrint('GemmaService.dispose: Model resources released');
  }
}

/// Structured response from the Gemma 4 triage assessment
class TriageResponse {
  final String severity;
  final String diagnosis;
  final String recommendation;
  final List<String> dangerSigns;
  final double confidence;

  TriageResponse({
    required this.severity,
    required this.diagnosis,
    required this.recommendation,
    required this.dangerSigns,
    required this.confidence,
  });
}
