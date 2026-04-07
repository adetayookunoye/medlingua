import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// On-device medical image classification service.
///
/// Uses a TFLite model (MedSigLIP-style) to classify medical images into
/// categories: skin_lesion, rash, wound, eye_condition, normal, unknown.
/// Falls back to heuristic analysis when the model is unavailable.
class VisionService {
  Interpreter? _interpreter;
  bool _isModelLoaded = false;
  bool _isProcessing = false;

  bool get isModelLoaded => _isModelLoaded;
  bool get isProcessing => _isProcessing;

  /// Supported medical image categories for triage.
  static const List<String> categories = [
    'skin_lesion',
    'rash',
    'wound',
    'eye_condition',
    'burn',
    'swelling',
    'normal',
    'unknown',
  ];

  /// Initialize the vision model.
  ///
  /// Attempts to load the TFLite model from assets. Falls back to
  /// heuristic mode if unavailable (demo/development).
  Future<void> initialize() async {
    try {
      _interpreter = await Interpreter.fromAsset('models/med_vision.tflite');
      _isModelLoaded = true;
      debugPrint('VisionService.initialize: TFLite model loaded');
    } catch (e) {
      debugPrint('VisionService.initialize: TFLite model not available ($e) — using heuristic mode');
      _isModelLoaded = false;
    }
  }

  /// Analyze a medical image and return classification results.
  ///
  /// Returns a [VisionResult] with the predicted category, confidence,
  /// and descriptive findings for the triage prompt.
  Future<VisionResult> analyzeImage(String imagePath) async {
    _isProcessing = true;
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        throw VisionServiceException('Image file not found: $imagePath');
      }

      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) {
        throw VisionServiceException('Could not decode image');
      }

      if (_isModelLoaded) {
        return await _classifyWithModel(image, bytes);
      } else {
        return _classifyWithHeuristics(image);
      }
    } on VisionServiceException {
      rethrow;
    } catch (e, stackTrace) {
      debugPrint('VisionService.analyzeImage: $e\n$stackTrace');
      throw VisionServiceException('Image analysis failed: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// Classify using the TFLite model.
  Future<VisionResult> _classifyWithModel(img.Image image, Uint8List rawBytes) async {
    // Resize to model input size (224x224 for SigLIP-style models)
    final resized = img.copyResize(image, width: 224, height: 224);

    // Normalize pixel values to [0, 1]
    final inputBuffer = Float32List(1 * 224 * 224 * 3);
    int idx = 0;
    for (int y = 0; y < 224; y++) {
      for (int x = 0; x < 224; x++) {
        final pixel = resized.getPixel(x, y);
        inputBuffer[idx++] = pixel.r / 255.0;
        inputBuffer[idx++] = pixel.g / 255.0;
        inputBuffer[idx++] = pixel.b / 255.0;
      }
    }

    // Run inference
    final input = inputBuffer.reshape([1, 224, 224, 3]);
    final output = List.filled(categories.length, 0.0).reshape([1, categories.length]);
    _interpreter!.run(input, output);

    final scores = (output[0] as List<double>);
    double maxScore = scores[0];
    int maxIdx = 0;
    for (int i = 1; i < scores.length; i++) {
      if (scores[i] > maxScore) {
        maxScore = scores[i];
        maxIdx = i;
      }
    }

    final category = categories[maxIdx];
    final confidence = maxScore.clamp(0.0, 1.0);

    return VisionResult(
      category: category,
      confidence: confidence,
      findings: _categoryToFindings(category, confidence),
      triageHint: _categoryToHint(category),
    );
  }

  String _categoryToFindings(String category, double confidence) {
    final pct = (confidence * 100).toStringAsFixed(0);
    switch (category) {
      case 'wound':
        return 'Image classified as wound ($pct% confidence) — possible open injury requiring cleaning and assessment';
      case 'rash':
        return 'Image classified as rash ($pct% confidence) — possible allergic, infectious, or inflammatory skin condition';
      case 'skin_lesion':
        return 'Image classified as skin lesion ($pct% confidence) — abnormal pigmented area requiring evaluation';
      case 'burn':
        return 'Image classified as burn ($pct% confidence) — thermal or chemical injury with inflammation';
      case 'eye_condition':
        return 'Image classified as eye condition ($pct% confidence) — possible conjunctivitis, jaundice, or infection';
      case 'swelling':
        return 'Image classified as swelling ($pct% confidence) — localized edema or inflammation';
      case 'normal':
        return 'No abnormality detected ($pct% confidence) — image appears normal';
      default:
        return 'Classification uncertain ($pct% confidence) — clinical examination recommended';
    }
  }

  String _categoryToHint(String category) {
    switch (category) {
      case 'wound':
        return 'Check for active bleeding, wound depth, and signs of infection';
      case 'rash':
        return 'Note distribution pattern, check for fever, assess if spreading';
      case 'skin_lesion':
        return 'Assess size, borders, color changes, and whether area is painful';
      case 'burn':
        return 'Assess burn area percentage, depth, and presence of blisters';
      case 'eye_condition':
        return 'Check sclera color, presence of discharge, and vision changes';
      case 'swelling':
        return 'Check if warm to touch, measure extent, note associated pain';
      default:
        return 'Combine with symptom description for better assessment';
    }
  }

  /// Heuristic image analysis based on color distribution and texture.
  ///
  /// This provides reasonable triage guidance even without a dedicated
  /// vision model, by analyzing color patterns common in medical conditions.
  VisionResult _classifyWithHeuristics(img.Image image) {
    // Sample pixels for color analysis
    final width = image.width;
    final height = image.height;
    final sampleSize = 100;
    final stepX = (width / 10).floor().clamp(1, width);
    final stepY = (height / 10).floor().clamp(1, height);

    double totalR = 0, totalG = 0, totalB = 0;
    double redDominance = 0;
    double darkPixels = 0;
    int samples = 0;

    for (int y = 0; y < height && samples < sampleSize; y += stepY) {
      for (int x = 0; x < width && samples < sampleSize; x += stepX) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toDouble();
        final g = pixel.g.toDouble();
        final b = pixel.b.toDouble();

        totalR += r;
        totalG += g;
        totalB += b;

        // Red dominance (rash, inflammation, burns)
        if (r > 150 && r > g * 1.3 && r > b * 1.3) {
          redDominance++;
        }

        // Dark pixels (wounds, bruises, necrosis)
        if (r < 80 && g < 80 && b < 80) {
          darkPixels++;
        }

        samples++;
      }
    }

    if (samples == 0) {
      return VisionResult(
        category: 'unknown',
        confidence: 0.3,
        findings: 'Unable to analyze image — insufficient data',
        triageHint: 'Take a clearer photo in good lighting',
      );
    }

    final avgR = totalR / samples;
    final avgG = totalG / samples;
    final avgB = totalB / samples;
    final redRatio = redDominance / samples;
    final darkRatio = darkPixels / samples;

    // Classification heuristics
    if (redRatio > 0.3) {
      if (darkRatio > 0.1) {
        return VisionResult(
          category: 'wound',
          confidence: 0.65,
          findings: 'Image shows significant redness with dark areas — '
              'possible open wound, bruising, or deep tissue injury',
          triageHint: 'Check for active bleeding, wound depth, and signs of infection',
        );
      }
      return VisionResult(
        category: 'rash',
        confidence: 0.60,
        findings: 'Image shows widespread redness — '
            'possible rash, inflammation, or allergic reaction',
        triageHint: 'Note distribution pattern, check for fever, assess if spreading',
      );
    }

    if (darkRatio > 0.2) {
      return VisionResult(
        category: 'skin_lesion',
        confidence: 0.55,
        findings: 'Image shows dark pigmented areas — '
            'possible skin lesion, bruise, or burn',
        triageHint: 'Assess size, borders, color changes, and whether area is painful',
      );
    }

    // Check for yellowish tones (jaundice, pus)
    if (avgR > 150 && avgG > 130 && avgB < 100) {
      return VisionResult(
        category: 'eye_condition',
        confidence: 0.50,
        findings: 'Image shows yellowish coloration — '
            'possible jaundice, conjunctivitis, or infected discharge',
        triageHint: 'Check sclera color, presence of discharge, and vision changes',
      );
    }

    // Reddish-pink burn pattern
    if (avgR > 170 && avgG > 100 && avgG < 160 && avgB < 130) {
      return VisionResult(
        category: 'burn',
        confidence: 0.55,
        findings: 'Image shows reddish-pink coloration — '
            'possible burn or scald with inflammation',
        triageHint: 'Assess burn area percentage, depth, and presence of blisters',
      );
    }

    return VisionResult(
      category: 'unknown',
      confidence: 0.40,
      findings: 'No obvious abnormality detected from image analysis alone — '
          'clinical examination recommended',
      triageHint: 'Combine with symptom description for better assessment',
    );
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isModelLoaded = false;
    debugPrint('VisionService.dispose: Resources released');
  }
}

/// Result from medical image analysis.
class VisionResult {
  /// Predicted category (e.g., 'rash', 'wound', 'skin_lesion').
  final String category;

  /// Model confidence (0.0–1.0).
  final double confidence;

  /// Human-readable description of visual findings.
  final String findings;

  /// Suggested clinical actions based on the image.
  final String triageHint;

  const VisionResult({
    required this.category,
    required this.confidence,
    required this.findings,
    required this.triageHint,
  });

  @override
  String toString() => 'VisionResult($category, ${(confidence * 100).toStringAsFixed(0)}%)';
}

/// Exception thrown by vision service operations.
class VisionServiceException implements Exception {
  final String message;
  const VisionServiceException(this.message);

  @override
  String toString() => 'VisionServiceException: $message';
}
