import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// On-device audio classification service for respiratory sound analysis.
///
/// Classifies audio recordings into categories relevant for medical triage:
/// cough, wheeze, stridor, crackles, normal_breathing, unknown.
///
/// Uses a TFLite model (HeAR-style) for classification when available,
/// with a signal-processing fallback for basic cough detection.
class AudioClassificationService {
  Interpreter? _interpreter;
  bool _isModelLoaded = false;
  bool _isProcessing = false;

  bool get isModelLoaded => _isModelLoaded;
  bool get isProcessing => _isProcessing;

  /// Supported audio classification categories.
  static const List<String> categories = [
    'cough',
    'wheeze',
    'stridor',
    'crackles',
    'normal_breathing',
    'unknown',
  ];

  /// Initialize the audio classification model.
  Future<void> initialize() async {
    try {
      _interpreter = await Interpreter.fromAsset('models/audio_classifier.tflite');
      _isModelLoaded = true;
      debugPrint('AudioClassificationService.initialize: TFLite model loaded');
    } catch (e) {
      debugPrint('AudioClassificationService.initialize: TFLite model not available ($e) — using signal-processing mode');
      _isModelLoaded = false;
    }
  }

  /// Classify an audio recording file.
  ///
  /// Accepts WAV or raw PCM audio files. Returns an [AudioClassResult]
  /// with the detected sound category and confidence.
  Future<AudioClassResult> classifyAudio(String audioPath) async {
    _isProcessing = true;
    try {
      final file = File(audioPath);
      if (!await file.exists()) {
        throw AudioClassException('Audio file not found: $audioPath');
      }

      final bytes = await file.readAsBytes();

      if (_isModelLoaded) {
        return await _classifyWithModel(bytes);
      } else {
        return _classifyWithSignalProcessing(bytes);
      }
    } on AudioClassException {
      rethrow;
    } catch (e, stackTrace) {
      debugPrint('AudioClassificationService.classifyAudio: $e\n$stackTrace');
      throw AudioClassException('Audio classification failed: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// Run inference with the TFLite model.
  ///
  /// Extracts a mel-spectrogram-like feature vector from the audio,
  /// feeds it through the TFLite interpreter, and returns the top prediction.
  Future<AudioClassResult> _classifyWithModel(Uint8List audioBytes) async {
    // Parse WAV to get PCM samples
    List<double> samples;
    int sampleRate = 16000;

    if (audioBytes.length > 44 &&
        String.fromCharCodes(audioBytes.sublist(0, 4)) == 'RIFF') {
      final byteData = ByteData.sublistView(audioBytes);
      sampleRate = byteData.getUint32(24, Endian.little);
      final bitsPerSample = byteData.getUint16(34, Endian.little);
      samples = [];
      if (bitsPerSample == 16) {
        for (int i = 44; i < audioBytes.length - 1; i += 2) {
          samples.add(byteData.getInt16(i, Endian.little) / 32768.0);
        }
      } else {
        for (int i = 44; i < audioBytes.length; i++) {
          samples.add((audioBytes[i] - 128) / 128.0);
        }
      }
    } else {
      final byteData = ByteData.sublistView(audioBytes);
      samples = [];
      for (int i = 0; i < audioBytes.length - 1; i += 2) {
        samples.add(byteData.getInt16(i, Endian.little) / 32768.0);
      }
    }

    // Pad or truncate to fixed length (1 second = sampleRate samples)
    final targetLen = sampleRate;
    final padded = List<double>.filled(targetLen, 0.0);
    for (int i = 0; i < min(samples.length, targetLen); i++) {
      padded[i] = samples[i];
    }

    // Compute mel-spectrogram features (simplified: 64 mel bins x 16 time frames)
    final nMels = 64;
    final nFrames = 16;
    final frameLen = targetLen ~/ nFrames;
    final features = Float32List(1 * nFrames * nMels);

    int idx = 0;
    for (int t = 0; t < nFrames; t++) {
      final frameStart = t * frameLen;
      // Simplified mel-like features via DFT magnitude at spaced frequencies
      for (int m = 0; m < nMels; m++) {
        final freq = (m + 1) * sampleRate / (2 * nMels);
        double re = 0, im = 0;
        for (int n = frameStart; n < frameStart + frameLen && n < targetLen; n++) {
          final angle = -2 * pi * freq * n / sampleRate;
          re += padded[n] * cos(angle);
          im += padded[n] * sin(angle);
        }
        features[idx++] = sqrt(re * re + im * im).clamp(0.0, 100.0) / 100.0;
      }
    }

    // Run TFLite inference
    final input = features.reshape([1, nFrames, nMels]);
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

    return AudioClassResult(
      category: category,
      confidence: confidence,
      findings: _categoryToFindings(category, confidence),
      triageHint: _categoryToHint(category),
    );
  }

  String _categoryToFindings(String category, double confidence) {
    final pct = (confidence * 100).toStringAsFixed(0);
    switch (category) {
      case 'cough':
        return 'Cough detected ($pct% confidence) — short high-energy respiratory bursts';
      case 'wheeze':
        return 'Wheeze detected ($pct% confidence) — sustained tonal breathing sound';
      case 'stridor':
        return 'Stridor detected ($pct% confidence) — high-pitched inspiratory noise suggesting airway obstruction';
      case 'crackles':
        return 'Crackles detected ($pct% confidence) — intermittent popping sounds suggesting fluid in lungs';
      case 'normal_breathing':
        return 'Normal breathing pattern ($pct% confidence) — no abnormal sounds detected';
      default:
        return 'Classification uncertain ($pct% confidence) — clinical auscultation recommended';
    }
  }

  String _categoryToHint(String category) {
    switch (category) {
      case 'cough':
        return 'Count respiratory rate. Check for chest indrawing. If productive, note sputum color.';
      case 'wheeze':
        return 'Assess for asthma or bronchiolitis. Note if during inspiration, expiration, or both.';
      case 'stridor':
        return 'URGENT: Stridor in a calm child is a danger sign. Check for croup, foreign body, or epiglottitis.';
      case 'crackles':
        return 'May indicate pneumonia or fluid in lungs. Count respiratory rate and check for chest indrawing.';
      case 'normal_breathing':
        return 'No concerning sounds. Monitor if symptoms persist.';
      default:
        return 'Combine with symptom history and respiratory rate count.';
    }
  }

  /// Signal-processing based classification (fallback).
  ///
  /// Analyzes audio characteristics to detect coughs and wheezes:
  /// - Cough: short burst of high energy with rapid onset
  /// - Wheeze: sustained tonal component (periodic signal)
  /// - Stridor: high-pitched inspiratory noise
  AudioClassResult _classifyWithSignalProcessing(Uint8List audioBytes) {
    // Parse WAV header if present, otherwise treat as raw PCM
    List<double> samples;
    int sampleRate = 16000;

    if (audioBytes.length > 44 &&
        String.fromCharCodes(audioBytes.sublist(0, 4)) == 'RIFF') {
      // WAV file — extract PCM data after 44-byte header
      final byteData = ByteData.sublistView(audioBytes);
      sampleRate = byteData.getUint32(24, Endian.little);
      final bitsPerSample = byteData.getUint16(34, Endian.little);

      samples = [];
      final dataStart = 44;
      if (bitsPerSample == 16) {
        for (int i = dataStart; i < audioBytes.length - 1; i += 2) {
          final sample = byteData.getInt16(i, Endian.little);
          samples.add(sample / 32768.0); // Normalize to [-1, 1]
        }
      } else {
        // 8-bit PCM
        for (int i = dataStart; i < audioBytes.length; i++) {
          samples.add((audioBytes[i] - 128) / 128.0);
        }
      }
    } else {
      // Assume raw 16-bit PCM
      final byteData = ByteData.sublistView(audioBytes);
      samples = [];
      for (int i = 0; i < audioBytes.length - 1; i += 2) {
        final sample = byteData.getInt16(i, Endian.little);
        samples.add(sample / 32768.0);
      }
    }

    if (samples.isEmpty) {
      return const AudioClassResult(
        category: 'unknown',
        confidence: 0.3,
        findings: 'Audio too short or empty for analysis',
        triageHint: 'Record at least 3 seconds of audio',
      );
    }

    // Compute features
    final rms = _computeRMS(samples);
    final zeroCrossRate = _computeZeroCrossingRate(samples);
    final energyBursts = _detectEnergyBursts(samples, sampleRate);
    final spectralFeatures = _computeSpectralFeatures(samples, sampleRate);

    debugPrint('AudioClassification: RMS=$rms, ZCR=$zeroCrossRate, '
        'bursts=${energyBursts.length}, spectralCentroid=${spectralFeatures.centroid}');

    // Classification logic based on signal features
    // Cough: high-energy short bursts with high zero-crossing rate
    if (energyBursts.isNotEmpty && zeroCrossRate > 0.05) {
      final burstEnergy = energyBursts.map((b) => b.energy).reduce(max);
      if (burstEnergy > rms * 2.5) {
        return AudioClassResult(
          category: 'cough',
          confidence: 0.70,
          findings: 'Detected ${energyBursts.length} cough-like burst(s) — '
              'short high-energy episodes with rapid onset',
          triageHint: 'Count respiratory rate. Check for chest indrawing. '
              'If productive cough, note sputum color.',
        );
      }
    }

    // Wheeze: sustained periodic component with higher spectral centroid
    if (spectralFeatures.centroid > 800 &&
        spectralFeatures.tonality > 0.3 &&
        zeroCrossRate > 0.08) {
      return AudioClassResult(
        category: 'wheeze',
        confidence: 0.60,
        findings: 'Detected sustained tonal component — '
            'possible wheeze or whistling sound during breathing',
        triageHint: 'Assess for asthma or bronchiolitis. '
            'Note if wheeze is during inspiration, expiration, or both.',
      );
    }

    // Stridor: very high frequency periodic sound
    if (spectralFeatures.centroid > 1500 && spectralFeatures.tonality > 0.4) {
      return AudioClassResult(
        category: 'stridor',
        confidence: 0.55,
        findings: 'Detected high-pitched sound — '
            'possible stridor (inspiratory noise suggesting airway obstruction)',
        triageHint: 'URGENT: Stridor in a calm child is a danger sign. '
            'Check for croup, foreign body, or epiglottitis.',
      );
    }

    // Crackles: intermittent high-frequency transients
    if (energyBursts.length > 5 && spectralFeatures.centroid > 500) {
      return AudioClassResult(
        category: 'crackles',
        confidence: 0.50,
        findings: 'Detected multiple short transient sounds — '
            'possible crackles or crepitations',
        triageHint: 'May indicate pneumonia or fluid in lungs. '
            'Count respiratory rate and check for chest indrawing.',
      );
    }

    // Normal or too quiet
    if (rms < 0.02) {
      return const AudioClassResult(
        category: 'normal_breathing',
        confidence: 0.55,
        findings: 'Audio signal is quiet — no prominent abnormal sounds detected',
        triageHint: 'If abnormal sounds are audible clinically but not detected, '
            'record with device closer to chest.',
      );
    }

    return const AudioClassResult(
      category: 'unknown',
      confidence: 0.40,
      findings: 'Audio characteristics do not clearly match known patterns — '
          'clinical auscultation recommended',
      triageHint: 'Combine with symptom history and respiratory rate count.',
    );
  }

  // ---- Signal processing utilities ------------------------------------------

  double _computeRMS(List<double> samples) {
    if (samples.isEmpty) return 0.0;
    final sumSquares = samples.fold<double>(0.0, (s, x) => s + x * x);
    return sqrt(sumSquares / samples.length);
  }

  double _computeZeroCrossingRate(List<double> samples) {
    if (samples.length < 2) return 0.0;
    int crossings = 0;
    for (int i = 1; i < samples.length; i++) {
      if ((samples[i] >= 0 && samples[i - 1] < 0) ||
          (samples[i] < 0 && samples[i - 1] >= 0)) {
        crossings++;
      }
    }
    return crossings / (samples.length - 1);
  }

  /// Detect short high-energy bursts (characteristic of coughs).
  List<_EnergyBurst> _detectEnergyBursts(List<double> samples, int sampleRate) {
    final frameSize = (sampleRate * 0.025).round(); // 25ms frames
    final hopSize = (sampleRate * 0.010).round(); // 10ms hop
    final bursts = <_EnergyBurst>[];

    if (samples.length < frameSize) return bursts;

    // Compute frame energies
    final energies = <double>[];
    for (int start = 0; start + frameSize < samples.length; start += hopSize) {
      double energy = 0;
      for (int i = start; i < start + frameSize; i++) {
        energy += samples[i] * samples[i];
      }
      energies.add(energy / frameSize);
    }

    if (energies.isEmpty) return bursts;

    final meanEnergy = energies.reduce((a, b) => a + b) / energies.length;
    final threshold = meanEnergy * 3; // Burst = 3x mean energy

    bool inBurst = false;
    int burstStart = 0;
    double burstMaxEnergy = 0;

    for (int i = 0; i < energies.length; i++) {
      if (energies[i] > threshold) {
        if (!inBurst) {
          inBurst = true;
          burstStart = i;
          burstMaxEnergy = energies[i];
        } else {
          if (energies[i] > burstMaxEnergy) {
            burstMaxEnergy = energies[i];
          }
        }
      } else if (inBurst) {
        final durationMs = ((i - burstStart) * hopSize * 1000 / sampleRate).round();
        // Cough bursts are typically 100-500ms
        if (durationMs >= 50 && durationMs <= 800) {
          bursts.add(_EnergyBurst(
            startFrame: burstStart,
            endFrame: i,
            energy: burstMaxEnergy,
            durationMs: durationMs,
          ));
        }
        inBurst = false;
      }
    }

    return bursts;
  }

  /// Compute spectral features using a simple DFT on a representative frame.
  _SpectralFeatures _computeSpectralFeatures(List<double> samples, int sampleRate) {
    // Take a frame from the loudest part of the signal
    final frameSize = min(1024, samples.length);

    // Find loudest frame
    int bestStart = 0;
    double bestEnergy = 0;
    for (int start = 0; start + frameSize <= samples.length; start += frameSize ~/ 2) {
      double energy = 0;
      for (int i = start; i < start + frameSize; i++) {
        energy += samples[i] * samples[i];
      }
      if (energy > bestEnergy) {
        bestEnergy = energy;
        bestStart = start;
      }
    }

    final frame = samples.sublist(bestStart, bestStart + frameSize);

    // Compute magnitude spectrum (simplified DFT for key frequencies)
    final halfN = frameSize ~/ 2;
    final magnitudes = Float64List(halfN);
    double totalMagnitude = 0;
    double weightedSum = 0;
    double maxMag = 0;

    for (int k = 0; k < halfN; k++) {
      double re = 0, im = 0;
      for (int n = 0; n < frameSize; n++) {
        final angle = -2 * pi * k * n / frameSize;
        re += frame[n] * cos(angle);
        im += frame[n] * sin(angle);
      }
      magnitudes[k] = sqrt(re * re + im * im);
      final freq = k * sampleRate / frameSize;
      totalMagnitude += magnitudes[k];
      weightedSum += freq * magnitudes[k];
      if (magnitudes[k] > maxMag) maxMag = magnitudes[k];
    }

    final centroid = totalMagnitude > 0 ? weightedSum / totalMagnitude : 0.0;

    // Tonality: ratio of peak magnitude to mean magnitude
    final meanMag = totalMagnitude / halfN;
    final tonality = meanMag > 0 ? (maxMag / meanMag - 1) / 10.0 : 0.0;

    return _SpectralFeatures(
      centroid: centroid,
      tonality: tonality.clamp(0.0, 1.0),
    );
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isModelLoaded = false;
    debugPrint('AudioClassificationService.dispose: Resources released');
  }
}

class _EnergyBurst {
  final int startFrame;
  final int endFrame;
  final double energy;
  final int durationMs;

  const _EnergyBurst({
    required this.startFrame,
    required this.endFrame,
    required this.energy,
    required this.durationMs,
  });
}

class _SpectralFeatures {
  final double centroid;
  final double tonality;

  const _SpectralFeatures({required this.centroid, required this.tonality});
}

/// Result from audio classification.
class AudioClassResult {
  /// Detected sound category.
  final String category;

  /// Classification confidence (0.0–1.0).
  final double confidence;

  /// Human-readable description of audio findings.
  final String findings;

  /// Suggested clinical action based on audio analysis.
  final String triageHint;

  const AudioClassResult({
    required this.category,
    required this.confidence,
    required this.findings,
    required this.triageHint,
  });

  @override
  String toString() => 'AudioClassResult($category, ${(confidence * 100).toStringAsFixed(0)}%)';
}

/// Exception thrown by audio classification operations.
class AudioClassException implements Exception {
  final String message;
  const AudioClassException(this.message);

  @override
  String toString() => 'AudioClassException: $message';
}
