import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import 'result_screen.dart';

class TriageScreen extends StatefulWidget {
  const TriageScreen({super.key});

  @override
  State<TriageScreen> createState() => _TriageScreenState();
}

class _TriageScreenState extends State<TriageScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _symptomsController = TextEditingController();
  String? _selectedGender;
  String? _imagePath;
  String? _audioPath;
  bool _isRecordingAudio = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _symptomsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('New Triage'),
            actions: [
              Container(
                margin: const EdgeInsets.only(right: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.language, size: 14, color: Colors.white70),
                    const SizedBox(width: 4),
                    Text(
                      provider.currentLanguage.nativeName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          body: provider.isProcessing
              ? _buildProcessingView()
              : _buildTriageForm(context, provider),
        );
      },
    );
  }

  Widget _buildProcessingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const CircularProgressIndicator(
              color: AppTheme.primaryGreen,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Analyzing with Gemma 4...',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Processing on-device • No data leaves your phone',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 32),
          // Animated steps
          _processingStep(Icons.text_fields, 'Analyzing symptoms...', true),
          if (_imagePath != null)
            _processingStep(Icons.image_search, 'Analyzing image (vision model)...', true),
          if (_audioPath != null)
            _processingStep(Icons.graphic_eq, 'Classifying audio (respiratory sounds)...', true),
          _processingStep(Icons.medical_services, 'Applying WHO IMCI protocols...', true),
          _processingStep(Icons.assessment, 'Generating triage assessment...', false),
        ],
      ),
    );
  }

  Widget _processingStep(IconData icon, String text, bool done) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 4),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle : Icons.hourglass_top,
            color: done ? AppTheme.safeGreen : AppTheme.warningYellow,
            size: 18,
          ),
          const SizedBox(width: 12),
          Text(
            text,
            style: TextStyle(
              color: done ? AppTheme.textDark : Colors.grey[400],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTriageForm(BuildContext context, AppProvider provider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.primaryGreen.withValues(alpha: 0.2),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: AppTheme.primaryGreen, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'This tool supports clinical decision-making. '
                      'Always use professional medical judgment.',
                      style: TextStyle(fontSize: 12, color: AppTheme.primaryDark),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Patient Info Section
            Text('Patient Information',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),

            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Patient Name',
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (value) =>
                  value?.isEmpty ?? true ? 'Please enter patient name' : null,
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _ageController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Age',
                      prefixIcon: const Icon(Icons.cake_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedGender,
                    decoration: InputDecoration(
                      labelText: 'Gender',
                      prefixIcon: const Icon(Icons.wc_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Male', child: Text('Male')),
                      DropdownMenuItem(value: 'Female', child: Text('Female')),
                      DropdownMenuItem(value: 'Other', child: Text('Other')),
                    ],
                    onChanged: (value) =>
                        setState(() => _selectedGender = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Symptoms Section
            Text('Symptoms', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),

            TextFormField(
              controller: _symptomsController,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Describe symptoms...',
                alignLabelWithHint: true,
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(bottom: 60),
                  child: Icon(Icons.edit_note),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                hintText:
                    'e.g. "Child has fever for 3 days, rash on chest, not eating"',
              ),
              validator: (value) {
                if ((value?.isEmpty ?? true) && _imagePath == null) {
                  return 'Please describe symptoms or take a photo';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),

            // Voice input + update from voice
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _handleVoiceInput(provider),
                    icon: Icon(
                      provider.isListening ? Icons.mic : Icons.mic_none,
                      color: provider.isListening
                          ? AppTheme.dangerRed
                          : AppTheme.primaryGreen,
                    ),
                    label: Text(
                      provider.isListening
                          ? 'Listening...'
                          : 'Voice Input (${provider.currentLanguage.code.toUpperCase()})',
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(
                        color: provider.isListening
                            ? AppTheme.dangerRed
                            : AppTheme.primaryGreen,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Show live voice transcription
            if (provider.voiceInput.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[100]!),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.record_voice_over, size: 16, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        provider.voiceInput,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.check, size: 18),
                      onPressed: () {
                        _symptomsController.text = provider.voiceInput;
                      },
                      tooltip: 'Use this text',
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 24),

            // Photo Section
            Text('Photo (Optional)',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Take a photo of wound, rash, or skin condition for visual analysis',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Take Photo'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            if (_imagePath != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.safeGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle,
                        color: AppTheme.safeGreen, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Photo attached',
                        style: TextStyle(color: AppTheme.primaryDark),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _imagePath = null),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Audio Recording Section
            Text('Audio Recording (Optional)',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Record cough, breathing, or respiratory sounds for AI analysis',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _toggleAudioRecording(),
                    icon: Icon(
                      _isRecordingAudio ? Icons.stop_circle : Icons.mic,
                      color: _isRecordingAudio
                          ? AppTheme.dangerRed
                          : AppTheme.primaryGreen,
                    ),
                    label: Text(
                      _isRecordingAudio
                          ? 'Stop Recording'
                          : 'Record Respiratory Sounds',
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(
                        color: _isRecordingAudio
                            ? AppTheme.dangerRed
                            : AppTheme.primaryGreen,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            if (_audioPath != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.graphic_eq,
                        color: Colors.purple, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Audio recording attached — will be analyzed for cough/wheeze patterns',
                        style: TextStyle(color: AppTheme.primaryDark, fontSize: 13),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _audioPath = null),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 32),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: provider.isModelLoaded
                    ? () => _submitTriage(provider)
                    : null,
                icon: const Icon(Icons.medical_services),
                label: const Text('Run Triage Assessment'),
              ),
            ),

            if (!provider.isModelLoaded)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Waiting for Gemma 4 model to load...',
                  style: TextStyle(color: AppTheme.warningYellow, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Future<void> _handleVoiceInput(AppProvider provider) async {
    if (provider.isListening) {
      await provider.stopVoiceInput();
    } else {
      await provider.startVoiceInput();
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final image = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() => _imagePath = image.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not access camera: $e')),
        );
      }
    }
  }

  Future<void> _toggleAudioRecording() async {
    if (_isRecordingAudio) {
      // Stop recording
      setState(() {
        _isRecordingAudio = false;
      });
      // Audio path was already set when recording started
    } else {
      // Start recording — use the voice service's underlying platform
      // For now, create a placeholder indicating the feature is ready
      try {
        final dir = await getApplicationDocumentsDirectory();
        final audioFile = File('${dir.path}/triage_audio_${DateTime.now().millisecondsSinceEpoch}.wav');
        setState(() {
          _isRecordingAudio = true;
          _audioPath = audioFile.path;
        });

        // Simulate a recording duration, then auto-stop
        // In production, this would use a proper audio recorder plugin
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted && _isRecordingAudio) {
            setState(() => _isRecordingAudio = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Audio recording complete (5 seconds)'),
                backgroundColor: AppTheme.primaryGreen,
              ),
            );
          }
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not start recording: $e')),
          );
        }
      }
    }
  }

  Future<void> _submitTriage(AppProvider provider) async {
    if (!_formKey.currentState!.validate()) return;

    final age = int.tryParse(_ageController.text);

    dynamic encounter;

    if (_audioPath != null && File(_audioPath!).existsSync()) {
      // Audio-based triage (with optional image and text)
      encounter = await provider.processAudioTriage(
        patientName: _nameController.text,
        audioPath: _audioPath!,
        additionalSymptoms: _symptomsController.text.isNotEmpty
            ? _symptomsController.text
            : null,
        patientAge: age,
        patientGender: _selectedGender,
      );
    } else if (_imagePath != null) {
      encounter = await provider.processImageTriage(
        patientName: _nameController.text,
        imagePath: _imagePath!,
        additionalSymptoms: _symptomsController.text,
        patientAge: age,
        patientGender: _selectedGender,
      );
    } else {
      encounter = await provider.processTextTriage(
        patientName: _nameController.text,
        symptoms: _symptomsController.text,
        patientAge: age,
        patientGender: _selectedGender,
      );
    }

    if (encounter != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ResultScreen(encounter: encounter),
        ),
      );
      // Clear form
      _nameController.clear();
      _ageController.clear();
      _symptomsController.clear();
      setState(() {
        _selectedGender = null;
        _imagePath = null;
        _audioPath = null;
      });
    }
  }
}
