import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlingua/services/vision_service.dart';

void main() {
  group('VisionService', () {
    late VisionService service;

    setUp(() {
      service = VisionService();
    });

    test('categories list is populated', () {
      expect(VisionService.categories, isNotEmpty);
      expect(VisionService.categories, contains('rash'));
      expect(VisionService.categories, contains('wound'));
      expect(VisionService.categories, contains('skin_lesion'));
      expect(VisionService.categories, contains('normal'));
      expect(VisionService.categories, contains('unknown'));
    });

    test('initial state is not loaded and not processing', () {
      expect(service.isModelLoaded, false);
      expect(service.isProcessing, false);
    });

    test('initialize runs without error in test environment', () async {
      // TFLite model won't be available in tests; should fall back
      await service.initialize();
      // In test environment, model file won't exist — heuristic mode
      expect(service.isModelLoaded, false);
    });

    test('analyzeImage throws for non-existent file', () async {
      await service.initialize();
      expect(
        () => service.analyzeImage('/nonexistent/image.jpg'),
        throwsA(isA<VisionServiceException>()),
      );
    });

    test('analyzeImage returns result for valid image', () async {
      await service.initialize();

      // Create a minimal valid PNG file (1x1 red pixel)
      final tempDir = Directory.systemTemp.createTempSync('vision_test_');
      final testImage = File('${tempDir.path}/test.ppm');

      // Create a simple PPM P6 image (3x3 red pixels)
      final header = 'P6\n3 3\n255\n';
      final pixels = Uint8List(3 * 3 * 3);
      for (int i = 0; i < pixels.length; i += 3) {
        pixels[i] = 255;     // R
        pixels[i + 1] = 50;  // G
        pixels[i + 2] = 50;  // B
      }
      final bytes = BytesBuilder();
      bytes.add(header.codeUnits);
      bytes.add(pixels);
      testImage.writeAsBytesSync(bytes.toBytes());

      try {
        final result = await service.analyzeImage(testImage.path);
        expect(result.category, isNotEmpty);
        expect(result.confidence, greaterThan(0.0));
        expect(result.confidence, lessThanOrEqualTo(1.0));
        expect(result.findings, isNotEmpty);
        expect(result.triageHint, isNotEmpty);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('dispose resets state', () {
      service.dispose();
      expect(service.isModelLoaded, false);
    });
  });

  group('VisionResult', () {
    test('holds values correctly', () {
      const result = VisionResult(
        category: 'rash',
        confidence: 0.75,
        findings: 'Widespread redness',
        triageHint: 'Check for fever',
      );
      expect(result.category, 'rash');
      expect(result.confidence, 0.75);
      expect(result.findings, 'Widespread redness');
      expect(result.triageHint, 'Check for fever');
    });
  });
}
