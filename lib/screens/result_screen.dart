import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/triage_encounter.dart';
import '../theme/app_theme.dart';

class ResultScreen extends StatelessWidget {
  final TriageEncounter encounter;

  const ResultScreen({super.key, required this.encounter});

  @override
  Widget build(BuildContext context) {
    final severityColor = _getSeverityColor(encounter.severity);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Triage Result'),
        backgroundColor: severityColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Severity Banner
            _buildSeverityBanner(severityColor),
            const SizedBox(height: 20),

            // Patient Info
            _buildSection(
              context,
              'Patient Information',
              Icons.person,
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _infoRow('Name', encounter.patientName),
                      if (encounter.patientAge != null)
                        _infoRow('Age', '${encounter.patientAge} years'),
                      if (encounter.patientGender != null)
                        _infoRow('Gender', encounter.patientGender!),
                      _infoRow('Language', encounter.inputLanguage.toUpperCase()),
                      _infoRow('Time', _formatTime(encounter.timestamp)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Diagnosis
            _buildSection(
              context,
              'Assessment',
              Icons.medical_services,
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Suspected Condition',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        encounter.diagnosis,
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text(
                            'Confidence: ',
                            style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _getConfidenceColor(encounter.confidenceScore)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${(encounter.confidenceScore * 100).toInt()}%',
                              style: TextStyle(
                                color:
                                    _getConfidenceColor(encounter.confidenceScore),
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Recommendations
            _buildSection(
              context,
              'Recommended Actions',
              Icons.checklist,
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    encounter.recommendation,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.6,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Disclaimer
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.warningYellow.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.warningYellow.withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber,
                      color: AppTheme.warningYellow, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'DISCLAIMER: This is an AI-assisted triage tool and does '
                      'not replace professional medical diagnosis. Always consult '
                      'a qualified healthcare provider for medical decisions.',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _shareReferralNote(context),
                    icon: const Icon(Icons.share),
                    label: const Text('Share Referral'),
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
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                    icon: const Icon(Icons.home),
                    label: const Text('Dashboard'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSeverityBanner(Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(
            _getSeverityIcon(encounter.severity),
            color: color,
            size: 48,
          ),
          const SizedBox(height: 8),
          Text(
            encounter.severity.label,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            encounter.severity.description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: color.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off, size: 14, color: AppTheme.textMuted),
                const SizedBox(width: 4),
                const Text(
                  'Processed on-device by Gemma 4',
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
      BuildContext context, String title, IconData icon, Widget content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: AppTheme.primaryGreen),
            const SizedBox(width: 8),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
        const SizedBox(height: 8),
        content,
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getSeverityColor(TriageSeverity severity) {
    switch (severity) {
      case TriageSeverity.emergency:
        return AppTheme.triageEmergency;
      case TriageSeverity.urgent:
        return AppTheme.triageUrgent;
      case TriageSeverity.standard:
        return AppTheme.triageStandard;
      case TriageSeverity.routine:
        return AppTheme.triageRoutine;
    }
  }

  IconData _getSeverityIcon(TriageSeverity severity) {
    switch (severity) {
      case TriageSeverity.emergency:
        return Icons.warning;
      case TriageSeverity.urgent:
        return Icons.schedule;
      case TriageSeverity.standard:
        return Icons.info_outline;
      case TriageSeverity.routine:
        return Icons.check_circle_outline;
    }
  }

  Color _getConfidenceColor(double score) {
    if (score >= 0.8) return AppTheme.safeGreen;
    if (score >= 0.6) return AppTheme.warningYellow;
    return AppTheme.dangerRed;
  }

  String _formatTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  /// Build a plain-text referral note from the encounter data.
  String _buildReferralNote() {
    final time = _formatTime(encounter.timestamp);
    final buffer = StringBuffer();
    buffer.writeln('═══════════════════════════════════════');
    buffer.writeln('  MEDLINGUA REFERRAL NOTE');
    buffer.writeln('═══════════════════════════════════════');
    buffer.writeln();
    buffer.writeln('Date: $time');
    buffer.writeln('Triage ID: ${encounter.id.substring(0, 8)}');
    buffer.writeln();
    buffer.writeln('── PATIENT INFORMATION ──');
    buffer.writeln('Name: ${encounter.patientName}');
    if (encounter.patientAge != null) {
      buffer.writeln('Age: ${encounter.patientAge} years');
    }
    if (encounter.patientGender != null) {
      buffer.writeln('Gender: ${encounter.patientGender}');
    }
    buffer.writeln('Language: ${encounter.inputLanguage.toUpperCase()}');
    buffer.writeln();
    buffer.writeln('── ASSESSMENT ──');
    buffer.writeln('Severity: ${encounter.severity.label}');
    buffer.writeln('Confidence: ${(encounter.confidenceScore * 100).toInt()}%');
    buffer.writeln();
    buffer.writeln('Presenting Symptoms:');
    buffer.writeln(encounter.symptoms);
    buffer.writeln();
    buffer.writeln('Suspected Condition:');
    buffer.writeln(encounter.diagnosis);
    buffer.writeln();
    buffer.writeln('── RECOMMENDED ACTIONS ──');
    buffer.writeln(encounter.recommendation);
    buffer.writeln();
    buffer.writeln('═══════════════════════════════════════');
    buffer.writeln('Generated by MedLingua (AI-assisted)');
    buffer.writeln('This does NOT replace clinical diagnosis.');
    buffer.writeln('═══════════════════════════════════════');
    return buffer.toString();
  }

  /// Share the referral note via the platform's share sheet.
  void _shareReferralNote(BuildContext context) {
    final note = _buildReferralNote();
    Share.share(
      note,
      subject: 'MedLingua Referral — ${encounter.patientName} (${encounter.severity.label})',
    );
  }
}
