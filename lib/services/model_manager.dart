import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Manages Gemma model lifecycle: detection, download progress, and file paths.
///
/// Supports two model variants:
/// - Gemma 4 E4B (~3.65 GB) — primary model for complex multimodal triage
/// - Gemma 4 E2B (~2.0 GB)  — lighter alternative for constrained devices
class ModelManager {
  ModelManager._();
  static final ModelManager instance = ModelManager._();

  /// Supported model variants the app can use.
  static const Map<String, ModelInfo> models = {
    'e4b': ModelInfo(
      id: 'e4b',
      displayName: 'Gemma 4 E4B',
      fileName: 'gemma-4-E4B-it.litertlm',
      sizeBytes: 3650000000, // ~3.65 GB
      repoId: 'litert-community/gemma-4-E4B-it-litert-lm',
      requiresLicense: false,
    ),
    'e2b': ModelInfo(
      id: 'e2b',
      displayName: 'Gemma 4 E2B',
      fileName: 'gemma-4-E2B-it.litertlm',
      sizeBytes: 2000000000, // ~2.0 GB
      repoId: 'litert-community/gemma-4-E2B-it-litert-lm',
      requiresLicense: false,
    ),
  };

  /// Active model variant key (matches [models] keys).
  String _activeVariant = 'e4b';
  String get activeVariant => _activeVariant;

  ModelInfo get activeModel => models[_activeVariant]!;

  /// Download state
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String? _downloadError;

  bool get isDownloading => _isDownloading;
  double get downloadProgress => _downloadProgress;
  String? get downloadError => _downloadError;

  /// Stream controller for download progress updates.
  final _progressController = StreamController<double>.broadcast();
  Stream<double> get progressStream => _progressController.stream;

  /// Set the active model variant.
  void setVariant(String variant) {
    if (models.containsKey(variant)) {
      _activeVariant = variant;
    }
  }

  /// Returns the directory where models are stored.
  Future<Directory> get _modelsDir async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/models');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Full path to the active model file.
  Future<String> get modelPath async {
    final dir = await _modelsDir;
    return '${dir.path}/${activeModel.fileName}';
  }

  /// Check if the active model file is present on-device.
  Future<bool> isModelAvailable() async {
    final path = await modelPath;
    return File(path).existsSync();
  }

  /// Check all variants and return info about what's available.
  Future<Map<String, bool>> checkAllModels() async {
    final dir = await _modelsDir;
    final result = <String, bool>{};
    for (final entry in models.entries) {
      result[entry.key] = File('${dir.path}/${entry.value.fileName}').existsSync();
    }
    return result;
  }

  /// Auto-detect which model is available and set it as active.
  /// Returns true if any model was found.
  Future<bool> autoDetect() async {
    final available = await checkAllModels();

    // Prefer E4B, fall back to E2B
    if (available['e4b'] == true) {
      _activeVariant = 'e4b';
      debugPrint('ModelManager.autoDetect: Found Gemma 4 E4B');
      return true;
    }
    if (available['e2b'] == true) {
      _activeVariant = 'e2b';
      debugPrint('ModelManager.autoDetect: Found Gemma 4 E2B');
      return true;
    }

    debugPrint('ModelManager.autoDetect: No model found on device');
    return false;
  }

  /// Download the active model from HuggingFace.
  ///
  /// [hfToken] is required for models that need license acceptance (e.g. E4B).
  /// Progress is reported via [progressStream].
  Future<void> downloadModel({String? hfToken}) async {
    if (_isDownloading) return;

    final info = activeModel;
    if (info.requiresLicense && (hfToken == null || hfToken.isEmpty)) {
      _downloadError = 'This model requires a HuggingFace token. '
          'Accept the license at https://huggingface.co/${info.repoId} '
          'and provide your token.';
      return;
    }

    _isDownloading = true;
    _downloadProgress = 0.0;
    _downloadError = null;
    _progressController.add(0.0);

    try {
      final url = Uri.parse(
        'https://huggingface.co/${info.repoId}/resolve/main/${info.fileName}',
      );

      final request = http.Request('GET', url);
      if (hfToken != null && hfToken.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $hfToken';
      }

      final client = http.Client();
      try {
        final response = await client.send(request);

        if (response.statusCode == 401 || response.statusCode == 403) {
          throw ModelDownloadException(
            'Access denied. Please accept the model license at '
            'https://huggingface.co/${info.repoId} and check your token.',
          );
        }
        if (response.statusCode != 200) {
          throw ModelDownloadException(
            'Download failed with HTTP ${response.statusCode}',
          );
        }

        final contentLength = response.contentLength ?? info.sizeBytes;
        final path = await modelPath;
        final file = File('$path.download'); // Write to temp, rename on success
        final sink = file.openWrite();

        int received = 0;
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          _downloadProgress = received / contentLength;
          _progressController.add(_downloadProgress);
        }

        await sink.flush();
        await sink.close();

        // Rename temp file to final name
        await file.rename(path);

        _downloadProgress = 1.0;
        _progressController.add(1.0);
        debugPrint('ModelManager.downloadModel: Completed — $path');
      } finally {
        client.close();
      }
    } on ModelDownloadException {
      rethrow;
    } catch (e, stackTrace) {
      debugPrint('ModelManager.downloadModel: Error: $e\n$stackTrace');
      _downloadError = 'Download failed: $e';

      // Clean up partial download
      final path = await modelPath;
      final partial = File('$path.download');
      if (await partial.exists()) {
        await partial.delete();
      }

      throw ModelDownloadException('Download failed: $e');
    } finally {
      _isDownloading = false;
    }
  }

  /// Cancel an in-progress download (best-effort).
  void cancelDownload() {
    // The http client closure in downloadModel will handle cleanup.
    // This flag lets the UI know to stop showing progress.
    _isDownloading = false;
    _downloadProgress = 0.0;
    _progressController.add(0.0);
  }

  /// Delete the active model from device storage.
  Future<void> deleteModel() async {
    final path = await modelPath;
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
      debugPrint('ModelManager.deleteModel: Deleted $path');
    }
  }

  /// Human-readable size of the active model.
  String get activeModelSizeLabel {
    final bytes = activeModel.sizeBytes;
    if (bytes >= 1000000000) {
      return '${(bytes / 1000000000).toStringAsFixed(1)} GB';
    }
    return '${(bytes / 1000000).toStringAsFixed(0)} MB';
  }

  void dispose() {
    _progressController.close();
  }
}

/// Metadata for a downloadable model variant.
class ModelInfo {
  final String id;
  final String displayName;
  final String fileName;
  final int sizeBytes;
  final String repoId;
  final bool requiresLicense;

  const ModelInfo({
    required this.id,
    required this.displayName,
    required this.fileName,
    required this.sizeBytes,
    required this.repoId,
    required this.requiresLicense,
  });
}

/// Exception thrown when model download fails.
class ModelDownloadException implements Exception {
  final String message;
  const ModelDownloadException(this.message);

  @override
  String toString() => 'ModelDownloadException: $message';
}
