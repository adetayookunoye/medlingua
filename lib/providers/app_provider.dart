import 'package:flutter/material.dart';
import '../models/language.dart';
import '../models/triage_encounter.dart';
import '../services/gemma_service.dart';
import '../services/database_service.dart';
import '../services/voice_service.dart';
import '../services/vision_service.dart';
import '../services/audio_classification_service.dart';
import '../services/model_manager.dart';
import 'package:uuid/uuid.dart';

/// Central state management for the MedLingua app
class AppProvider extends ChangeNotifier {
  final GemmaService _gemmaService = GemmaService();
  final DatabaseService _dbService = DatabaseService();
  final VoiceService _voiceService = VoiceService();

  // State
  AppLanguage _currentLanguage = SupportedLanguages.all.first;
  bool _isModelLoading = false;
  bool _isProcessing = false;
  bool _isDownloadingModel = false;
  double _downloadProgress = 0.0;
  String? _downloadError;
  bool _modelFileAvailable = false;
  List<TriageEncounter> _encounters = [];
  Map<String, int> _stats = {};
  TriageEncounter? _currentEncounter;
  String _voiceInput = '';

  // Getters
  AppLanguage get currentLanguage => _currentLanguage;
  bool get isModelLoaded => _gemmaService.isModelLoaded;
  bool get isModelLoading => _isModelLoading;
  bool get isProcessing => _isProcessing;
  bool get isListening => _voiceService.isListening;
  bool get isDownloadingModel => _isDownloadingModel;
  double get downloadProgress => _downloadProgress;
  String? get downloadError => _downloadError;
  bool get modelFileAvailable => _modelFileAvailable;
  bool get isUsingDemoMode => _gemmaService.useDemoMode;
  ModelManager get modelManager => _gemmaService.modelManager;
  List<TriageEncounter> get encounters => _encounters;
  Map<String, int> get stats => _stats;
  TriageEncounter? get currentEncounter => _currentEncounter;
  String get voiceInput => _voiceInput;
  GemmaService get gemmaService => _gemmaService;
  VoiceService get voiceService => _voiceService;
  VisionService get visionService => _gemmaService.visionService;
  AudioClassificationService get audioClassService => _gemmaService.audioService;

  /// Initialize app: load model + fetch stored encounters
  Future<void> initialize() async {
    _isModelLoading = true;
    notifyListeners();

    try {
      _modelFileAvailable = await _gemmaService.isModelDownloaded();
      await _gemmaService.loadModel();
      try {
        await _voiceService.initialize();
      } catch (e) {
        debugPrint('VoiceService unavailable on this platform: $e');
      }
      await refreshEncounters();
      await refreshStats();
    } finally {
      _isModelLoading = false;
      notifyListeners();
    }
  }

  /// Download the Gemma model from HuggingFace.
  ///
  /// [hfToken] is required for the E4B model (needs license acceptance).
  /// Progress is pushed via [notifyListeners].
  Future<void> downloadModel({String? hfToken}) async {
    _isDownloadingModel = true;
    _downloadProgress = 0.0;
    _downloadError = null;
    notifyListeners();

    final subscription = modelManager.progressStream.listen((progress) {
      _downloadProgress = progress;
      notifyListeners();
    });

    try {
      await modelManager.downloadModel(hfToken: hfToken);
      _modelFileAvailable = true;
      _downloadProgress = 1.0;

      // Reload the model now that the file is available
      await _gemmaService.loadModel();
    } on ModelDownloadException catch (e) {
      _downloadError = e.message;
      debugPrint('AppProvider.downloadModel: $e');
    } catch (e) {
      _downloadError = 'Download failed: $e';
      debugPrint('AppProvider.downloadModel: $e');
    } finally {
      _isDownloadingModel = false;
      await subscription.cancel();
      notifyListeners();
    }
  }

  /// Switch model variant and reload.
  Future<void> switchModelVariant(String variant) async {
    modelManager.setVariant(variant);
    _modelFileAvailable = await _gemmaService.isModelDownloaded();
    if (_modelFileAvailable) {
      _isModelLoading = true;
      notifyListeners();
      try {
        await _gemmaService.loadModel();
      } finally {
        _isModelLoading = false;
        notifyListeners();
      }
    } else {
      notifyListeners();
    }
  }

  /// Change the active language
  void setLanguage(AppLanguage language) {
    _currentLanguage = language;
    notifyListeners();
  }

  /// Process text-based triage
  Future<TriageEncounter?> processTextTriage({
    required String patientName,
    required String symptoms,
    int? patientAge,
    String? patientGender,
  }) async {
    _isProcessing = true;
    notifyListeners();

    try {
      final response = await _gemmaService.processTextTriage(
        symptoms: symptoms,
        language: _currentLanguage.name,
        patientAge: patientAge,
        patientGender: patientGender,
      );

      final encounter = TriageEncounter(
        id: const Uuid().v4(),
        timestamp: DateTime.now(),
        patientName: patientName,
        patientAge: patientAge,
        patientGender: patientGender,
        symptoms: symptoms,
        inputLanguage: _currentLanguage.code,
        severity: _parseSeverity(response.severity),
        diagnosis: response.diagnosis,
        recommendation: response.recommendation,
        confidenceScore: response.confidence,
        isOffline: true,
      );

      await _dbService.saveEncounter(encounter);
      _currentEncounter = encounter;
      await refreshEncounters();
      await refreshStats();

      return encounter;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Process image-based triage
  Future<TriageEncounter?> processImageTriage({
    required String patientName,
    required String imagePath,
    String? additionalSymptoms,
    int? patientAge,
    String? patientGender,
  }) async {
    _isProcessing = true;
    notifyListeners();

    try {
      final response = await _gemmaService.processImageTriage(
        imagePath: imagePath,
        additionalSymptoms: additionalSymptoms,
        language: _currentLanguage.name,
        patientAge: patientAge,
        patientGender: patientGender,
      );

      final encounter = TriageEncounter(
        id: const Uuid().v4(),
        timestamp: DateTime.now(),
        patientName: patientName,
        patientAge: patientAge,
        patientGender: patientGender,
        symptoms: additionalSymptoms ?? 'Image-based assessment',
        imagePath: imagePath,
        inputLanguage: _currentLanguage.code,
        severity: _parseSeverity(response.severity),
        diagnosis: response.diagnosis,
        recommendation: response.recommendation,
        confidenceScore: response.confidence,
        isOffline: true,
      );

      await _dbService.saveEncounter(encounter);
      _currentEncounter = encounter;
      await refreshEncounters();
      await refreshStats();

      return encounter;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Process audio-based triage (cough/wheeze/stridor classification)
  Future<TriageEncounter?> processAudioTriage({
    required String patientName,
    required String audioPath,
    String? additionalSymptoms,
    int? patientAge,
    String? patientGender,
  }) async {
    _isProcessing = true;
    notifyListeners();

    try {
      final response = await _gemmaService.processAudioTriage(
        audioPath: audioPath,
        additionalSymptoms: additionalSymptoms,
        language: _currentLanguage.name,
        patientAge: patientAge,
        patientGender: patientGender,
      );

      final encounter = TriageEncounter(
        id: const Uuid().v4(),
        timestamp: DateTime.now(),
        patientName: patientName,
        patientAge: patientAge,
        patientGender: patientGender,
        symptoms: additionalSymptoms ?? 'Audio-based assessment',
        inputLanguage: _currentLanguage.code,
        severity: _parseSeverity(response.severity),
        diagnosis: response.diagnosis,
        recommendation: response.recommendation,
        confidenceScore: response.confidence,
        isOffline: true,
      );

      await _dbService.saveEncounter(encounter);
      _currentEncounter = encounter;
      await refreshEncounters();
      await refreshStats();

      return encounter;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Start voice input
  Future<void> startVoiceInput() async {
    _voiceInput = '';
    notifyListeners();

    await _voiceService.startListening(
      language: _currentLanguage,
      onResult: (text) {
        _voiceInput = text;
        notifyListeners();
      },
      onDone: () {
        notifyListeners();
      },
    );
    notifyListeners();
  }

  /// Stop voice input
  Future<void> stopVoiceInput() async {
    await _voiceService.stopListening();
    notifyListeners();
  }

  /// Speak triage results aloud
  Future<void> speakResults(String text) async {
    await _voiceService.speak(text, languageCode: _currentLanguage.code);
  }

  /// Refresh encounter list from database
  Future<void> refreshEncounters() async {
    _encounters = await _dbService.getAllEncounters();
    notifyListeners();
  }

  /// Refresh statistics
  Future<void> refreshStats() async {
    _stats = await _dbService.getEncounterStats();
    notifyListeners();
  }

  TriageSeverity _parseSeverity(String severity) {
    switch (severity.toLowerCase()) {
      case 'emergency':
        return TriageSeverity.emergency;
      case 'urgent':
        return TriageSeverity.urgent;
      case 'standard':
        return TriageSeverity.standard;
      case 'routine':
      default:
        return TriageSeverity.routine;
    }
  }

  @override
  void dispose() {
    _gemmaService.dispose();
    _voiceService.dispose();
    super.dispose();
  }
}
