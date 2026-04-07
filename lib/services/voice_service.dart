import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import '../models/language.dart';

/// Handles voice input (speech-to-text) and output (text-to-speech)
/// Critical for low-literacy users and hands-free operation in the field
class VoiceService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _isInitialized = false;
  bool _isListening = false;

  bool get isListening => _isListening;
  bool get isInitialized => _isInitialized;

  /// Initialize speech services
  Future<bool> initialize() async {
    final speechAvailable = await _speech.initialize(
      onStatus: (status) {
        _isListening = status == 'listening';
      },
      onError: (error) {
        _isListening = false;
      },
    );

    await _tts.setVolume(1.0);
    await _tts.setSpeechRate(0.45); // Slower for medical info clarity
    await _tts.setPitch(1.0);

    _isInitialized = speechAvailable;
    return speechAvailable;
  }

  /// Start listening for voice input
  Future<void> startListening({
    required AppLanguage language,
    required Function(String) onResult,
    required Function() onDone,
  }) async {
    if (!_isInitialized) await initialize();

    await _speech.listen(
      onResult: (result) {
        onResult(result.recognizedWords);
        if (result.finalResult) {
          onDone();
        }
      },
      localeId: language.sttLocale,
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        cancelOnError: false,
        partialResults: true,
      ),
    );
    _isListening = true;
  }

  /// Stop listening
  Future<void> stopListening() async {
    await _speech.stop();
    _isListening = false;
  }

  /// Speak text aloud (for triage results)
  Future<void> speak(String text, {String languageCode = 'en'}) async {
    await _tts.setLanguage(languageCode);
    await _tts.speak(text);
  }

  /// Stop speaking
  Future<void> stopSpeaking() async {
    await _tts.stop();
  }

  /// Get available locales for speech recognition
  Future<List<stt.LocaleName>> getAvailableLocales() async {
    if (!_isInitialized) await initialize();
    return await _speech.locales();
  }

  void dispose() {
    _speech.stop();
    _tts.stop();
  }
}
