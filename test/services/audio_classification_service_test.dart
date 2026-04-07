import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlingua/services/audio_classification_service.dart';

void main() {
  group('AudioClassificationService', () {
    late AudioClassificationService service;

    setUp(() {
      service = AudioClassificationService();
    });

    test('categories list is populated', () {
      expect(AudioClassificationService.categories, isNotEmpty);
      expect(AudioClassificationService.categories, contains('cough'));
      expect(AudioClassificationService.categories, contains('wheeze'));
      expect(AudioClassificationService.categories, contains('stridor'));
      expect(AudioClassificationService.categories, contains('crackles'));
      expect(AudioClassificationService.categories, contains('normal_breathing'));
    });

    test('initial state is not loaded and not processing', () {
      expect(service.isModelLoaded, false);
      expect(service.isProcessing, false);
    });

    test('initialize runs without error in test environment', () async {
      await service.initialize();
      expect(service.isModelLoaded, false); // No model in test env
    });

    test('classifyAudio throws for non-existent file', () async {
      await service.initialize();
      expect(
        () => service.classifyAudio('/nonexistent/audio.wav'),
        throwsA(isA<AudioClassException>()),
      );
    });

    test('classifyAudio returns result for valid WAV', () async {
      await service.initialize();

      // Generate a synthetic WAV file with a cough-like burst
      final wav = _generateTestWav(sampleRate: 16000, durationSec: 1.0);
      final tempDir = Directory.systemTemp.createTempSync('audio_test_');
      final testFile = File('${tempDir.path}/test.wav');
      testFile.writeAsBytesSync(wav);

      try {
        final result = await service.classifyAudio(testFile.path);
        expect(result.category, isNotEmpty);
        expect(result.confidence, greaterThan(0.0));
        expect(result.confidence, lessThanOrEqualTo(1.0));
        expect(result.findings, isNotEmpty);
        expect(result.triageHint, isNotEmpty);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('classifyAudio handles silent audio', () async {
      await service.initialize();

      // Generate a silent WAV
      final wav = _generateSilentWav(sampleRate: 16000, durationSec: 1.0);
      final tempDir = Directory.systemTemp.createTempSync('audio_test_');
      final testFile = File('${tempDir.path}/silent.wav');
      testFile.writeAsBytesSync(wav);

      try {
        final result = await service.classifyAudio(testFile.path);
        // Silent audio should be normal_breathing or unknown
        expect(
          ['normal_breathing', 'unknown'],
          contains(result.category),
        );
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('classifyAudio handles raw PCM bytes', () async {
      await service.initialize();

      // Generate raw PCM (no WAV header)
      final pcm = _generateRawPCM(sampleRate: 16000, durationSec: 0.5);
      final tempDir = Directory.systemTemp.createTempSync('audio_test_');
      final testFile = File('${tempDir.path}/raw.pcm');
      testFile.writeAsBytesSync(pcm);

      try {
        final result = await service.classifyAudio(testFile.path);
        expect(result.category, isNotEmpty);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('dispose resets state', () {
      service.dispose();
      expect(service.isModelLoaded, false);
    });
  });

  group('AudioClassResult', () {
    test('holds values correctly', () {
      const result = AudioClassResult(
        category: 'cough',
        confidence: 0.80,
        findings: 'Detected cough bursts',
        triageHint: 'Count respiratory rate',
      );
      expect(result.category, 'cough');
      expect(result.confidence, 0.80);
    });
  });
}

/// Generate a WAV file with noise (simulates audio with content).
Uint8List _generateTestWav({required int sampleRate, required double durationSec}) {
  final numSamples = (sampleRate * durationSec).round();
  final rng = Random(42);
  final pcmData = ByteData(numSamples * 2);

  for (int i = 0; i < numSamples; i++) {
    // Mix noise with a burst in the middle (cough-like)
    double sample;
    final pos = i / numSamples;
    if (pos > 0.3 && pos < 0.4) {
      // High-energy burst
      sample = (rng.nextDouble() - 0.5) * 2.0 * 0.8;
    } else {
      // Low-level background noise
      sample = (rng.nextDouble() - 0.5) * 2.0 * 0.05;
    }
    pcmData.setInt16(i * 2, (sample * 32767).round().clamp(-32768, 32767), Endian.little);
  }

  return _buildWav(sampleRate, pcmData.buffer.asUint8List());
}

/// Generate a silent WAV file.
Uint8List _generateSilentWav({required int sampleRate, required double durationSec}) {
  final numSamples = (sampleRate * durationSec).round();
  final pcmData = Uint8List(numSamples * 2); // All zeros = silence
  return _buildWav(sampleRate, pcmData);
}

/// Generate raw PCM (no WAV header).
Uint8List _generateRawPCM({required int sampleRate, required double durationSec}) {
  final numSamples = (sampleRate * durationSec).round();
  final rng = Random(7);
  final data = ByteData(numSamples * 2);
  for (int i = 0; i < numSamples; i++) {
    final sample = (rng.nextDouble() - 0.5) * 0.3;
    data.setInt16(i * 2, (sample * 32767).round().clamp(-32768, 32767), Endian.little);
  }
  return data.buffer.asUint8List();
}

/// Build a complete WAV file from PCM data.
Uint8List _buildWav(int sampleRate, Uint8List pcmData) {
  final header = ByteData(44);
  final dataSize = pcmData.length;
  final fileSize = dataSize + 36;

  // RIFF header
  header.setUint8(0, 0x52); // R
  header.setUint8(1, 0x49); // I
  header.setUint8(2, 0x46); // F
  header.setUint8(3, 0x46); // F
  header.setUint32(4, fileSize, Endian.little);
  header.setUint8(8, 0x57);  // W
  header.setUint8(9, 0x41);  // A
  header.setUint8(10, 0x56); // V
  header.setUint8(11, 0x45); // E

  // fmt chunk
  header.setUint8(12, 0x66); // f
  header.setUint8(13, 0x6D); // m
  header.setUint8(14, 0x74); // t
  header.setUint8(15, 0x20); // (space)
  header.setUint32(16, 16, Endian.little); // chunk size
  header.setUint16(20, 1, Endian.little);  // PCM format
  header.setUint16(22, 1, Endian.little);  // mono
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * 2, Endian.little); // byte rate
  header.setUint16(32, 2, Endian.little); // block align
  header.setUint16(34, 16, Endian.little); // bits per sample

  // data chunk
  header.setUint8(36, 0x64); // d
  header.setUint8(37, 0x61); // a
  header.setUint8(38, 0x74); // t
  header.setUint8(39, 0x61); // a
  header.setUint32(40, dataSize, Endian.little);

  final result = BytesBuilder();
  result.add(header.buffer.asUint8List());
  result.add(pcmData);
  return result.toBytes();
}
