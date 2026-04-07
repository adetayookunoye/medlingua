import 'package:flutter_test/flutter_test.dart';
import 'package:medlingua/services/gemma_service.dart';

void main() {
  group('GemmaService', () {
    late GemmaService service;

    setUp(() {
      service = GemmaService();
    });

    test('initial state is not loaded and not processing', () {
      expect(service.isModelLoaded, false);
      expect(service.isProcessing, false);
      expect(service.useDemoMode, false);
    });

    test('exposes model manager', () {
      expect(service.modelManager, isNotNull);
    });

    test('exposes vision service', () {
      expect(service.visionService, isNotNull);
    });

    test('exposes audio service', () {
      expect(service.audioService, isNotNull);
    });
  });

  group('GemmaService demo mode', () {
    late GemmaService service;

    setUp(() {
      service = GemmaService();
      service.useDemoMode = true;
    });

    test('processTextTriage returns valid response for fever+rash', () async {
      final response = await service.processTextTriage(
        symptoms: 'fever and rash for 3 days',
        language: 'English',
        patientAge: 4,
        patientGender: 'Female',
      );

      expect(response.severity, 'urgent');
      expect(response.diagnosis, isNotEmpty);
      expect(response.recommendation, isNotEmpty);
      expect(response.dangerSigns, isNotEmpty);
      expect(response.confidence, greaterThan(0));
    });

    test('processTextTriage handles diarrhea symptoms', () async {
      final response = await service.processTextTriage(
        symptoms: 'diarrhea and vomiting',
        language: 'English',
      );

      expect(response.severity, 'urgent');
      expect(response.diagnosis.toLowerCase(), contains('dehydration'));
    });

    test('processTextTriage handles cough symptoms', () async {
      final response = await service.processTextTriage(
        symptoms: 'persistent cough for a week',
        language: 'English',
      );

      expect(response.severity, 'standard');
      expect(response.diagnosis.toLowerCase(), contains('respiratory'));
    });

    test('processTextTriage handles generic symptoms', () async {
      final response = await service.processTextTriage(
        symptoms: 'patient feels unwell',
        language: 'English',
      );

      expect(response.severity, 'routine');
      expect(response.recommendation, isNotEmpty);
    });

    test('processImageTriage returns valid response without actual image', () async {
      final response = await service.processImageTriage(
        imagePath: '/fake/path.jpg',
        language: 'English',
      );

      // Demo mode returns a response without needing the actual image file
      expect(response.severity, isNotEmpty);
      expect(response.diagnosis, isNotEmpty);
      expect(response.recommendation, isNotEmpty);
    });

    test('processAudioTriage returns valid response without actual audio', () async {
      final response = await service.processAudioTriage(
        audioPath: '/fake/audio.wav',
        language: 'English',
      );

      expect(response.severity, isNotEmpty);
      expect(response.diagnosis, isNotEmpty);
      expect(response.recommendation, isNotEmpty);
    });
  });

  group('TriageResponse', () {
    test('holds values correctly', () {
      final response = TriageResponse(
        severity: 'urgent',
        diagnosis: 'Possible malaria',
        recommendation: 'Refer to clinic',
        dangerSigns: ['High fever', 'Altered consciousness'],
        confidence: 0.85,
      );

      expect(response.severity, 'urgent');
      expect(response.diagnosis, 'Possible malaria');
      expect(response.dangerSigns.length, 2);
      expect(response.confidence, 0.85);
    });
  });
}
