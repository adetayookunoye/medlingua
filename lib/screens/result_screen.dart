import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/triage_encounter.dart';
import '../providers/app_provider.dart';
import '../services/dose_check_service.dart';
import '../utils/date_utils.dart' as app_dates;
import '../theme/app_theme.dart';

class ResultScreen extends StatelessWidget {
  final TriageEncounter encounter;
  final List<DoseResult> doseResults;
  final List<InteractionAlert> interactionAlerts;

  const ResultScreen({
    super.key,
    required this.encounter,
    this.doseResults = const [],
    this.interactionAlerts = const [],
  });

  @override
  Widget build(BuildContext context) {
    final severityColor = AppTheme.severityColor(encounter.severity);

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
                      _infoRow(
                        'Language',
                        encounter.inputLanguage.toUpperCase(),
                      ),
                      _infoRow(
                        'Time',
                        app_dates.formatDateTime(encounter.timestamp),
                      ),
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
                            style: TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 13,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _getConfidenceColor(
                                encounter.confidenceScore,
                              ).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${(encounter.confidenceScore * 100).toInt()}%',
                              style: TextStyle(
                                color: _getConfidenceColor(
                                  encounter.confidenceScore,
                                ),
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
                    style: const TextStyle(fontSize: 15, height: 1.6),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Referral Recommendation
            if (encounter.severity == TriageSeverity.emergency ||
                encounter.severity == TriageSeverity.urgent) ...[
              _buildSection(
                context,
                'Referral Recommendation',
                Icons.local_hospital,
                _buildReferralCard(),
              ),
              const SizedBox(height: 16),
            ],

            // Dose Calculations
            if (doseResults.isNotEmpty) ...[
              _buildSection(
                context,
                'Medication Dosing',
                Icons.medical_information,
                _buildDoseCards(),
              ),
              const SizedBox(height: 16),
            ],

            // Drug Interaction Alerts
            if (interactionAlerts.isNotEmpty) ...[
              _buildSection(
                context,
                'Drug Interaction Alerts',
                Icons.warning_amber,
                _buildInteractionCards(),
              ),
              const SizedBox(height: 16),
            ],

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
                  Icon(
                    Icons.warning_amber,
                    color: AppTheme.warningYellow,
                    size: 20,
                  ),
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
            const SizedBox(height: 12),

            // Read Aloud button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _readAloud(context),
                icon: const Icon(Icons.volume_up),
                label: const Text('Read Aloud'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildReferralCard() {
    final isEmergency = encounter.severity == TriageSeverity.emergency;
    final urgencyColor =
        isEmergency ? AppTheme.triageEmergency : AppTheme.triageUrgent;
    final urgencyLabel = isEmergency ? 'IMMEDIATE' : 'WITHIN HOURS';
    final instructions =
        isEmergency
            ? 'Transport patient to the nearest hospital or health facility immediately. '
                'Stabilise the patient during transport. Do not delay.'
            : 'Refer patient to a health facility within the next few hours. '
                'Monitor vital signs while awaiting transfer.';

    return Card(
      color: urgencyColor.withValues(alpha: 0.04),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: urgencyColor.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_hospital, color: urgencyColor, size: 20),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: urgencyColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'REFER — $urgencyLabel',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              instructions,
              style: const TextStyle(fontSize: 14, height: 1.6),
            ),
            const SizedBox(height: 12),
            const Text(
              'What this system did not check:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '• Blood tests, lab work, or imaging\n'
              '• Full physical examination\n'
              '• Patient medical history or allergies\n'
              '• Drug interactions or current medications',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textMuted,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDoseCards() {
    return Column(
      children:
          doseResults.map((dose) {
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryGreen.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            dose.drugName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: AppTheme.primaryGreen,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          dose.source,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      dose.doseSummary,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (dose.warnings.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ...dose.warnings.map(
                        (w) => Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.info_outline,
                                size: 14,
                                color: AppTheme.warningYellow,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  w,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
    );
  }

  Widget _buildInteractionCards() {
    return Column(
      children:
          interactionAlerts.map((alert) {
            final Color alertColor;
            final IconData alertIcon;
            switch (alert.severity) {
              case InteractionSeverity.severe:
                alertColor = AppTheme.triageEmergency;
                alertIcon = Icons.dangerous;
              case InteractionSeverity.moderate:
                alertColor = AppTheme.warningYellow;
                alertIcon = Icons.warning;
              case InteractionSeverity.low:
                alertColor = AppTheme.textMuted;
                alertIcon = Icons.info_outline;
            }

            return Card(
              color: alertColor.withValues(alpha: 0.04),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: alertColor.withValues(alpha: 0.3)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(alertIcon, color: alertColor, size: 18),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: alertColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            alert.severity.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${alert.drugA} + ${alert.drugB}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      alert.description,
                      style: const TextStyle(fontSize: 13, height: 1.5),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      alert.recommendation,
                      style: const TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
    );
  }

  Widget _buildSeverityBanner(Color color) {
    return Semantics(
      label:
          'Triage severity: ${encounter.severity.label}. ${encounter.severity.description}',
      child: Container(
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
              AppTheme.severityIcon(encounter.severity),
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
                  const Icon(
                    Icons.wifi_off,
                    size: 14,
                    color: AppTheme.textMuted,
                  ),
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
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    IconData icon,
    Widget content,
  ) {
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
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Color _getConfidenceColor(double score) {
    if (score >= 0.8) return AppTheme.safeGreen;
    if (score >= 0.6) return AppTheme.warningYellow;
    return AppTheme.dangerRed;
  }

  /// Read the assessment aloud via TTS.
  void _readAloud(BuildContext context) {
    final provider = context.read<AppProvider>();
    final text =
        'Severity: ${encounter.severity.label}. '
        'Diagnosis: ${encounter.diagnosis}. '
        'Recommendation: ${encounter.recommendation}';
    provider.speakResults(text);
  }

  /// Build a plain-text referral note from the encounter data.
  String _buildReferralNote() {
    final time = app_dates.formatDateTime(encounter.timestamp);
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
      subject:
          'MedLingua Referral — ${encounter.patientName} (${encounter.severity.label})',
    );
  }
}
