/// Data model for a patient encounter / triage session
class TriageEncounter {
  final String id;
  final DateTime timestamp;
  final String patientName;
  final int? patientAge;
  final double? patientWeight; // kg
  final String? patientGender;
  final String symptoms;
  final String? imagePath; // Path to wound/skin photo
  final String inputLanguage;
  final TriageSeverity severity;
  final String diagnosis;
  final String recommendation;
  final String? referralNote;
  final double confidenceScore;
  final bool isOffline;

  TriageEncounter({
    required this.id,
    required this.timestamp,
    required this.patientName,
    this.patientAge,
    this.patientWeight,
    this.patientGender,
    required this.symptoms,
    this.imagePath,
    required this.inputLanguage,
    required this.severity,
    required this.diagnosis,
    required this.recommendation,
    this.referralNote,
    required this.confidenceScore,
    required this.isOffline,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'patientName': patientName,
      'patientAge': patientAge,
      'patientWeight': patientWeight,
      'patientGender': patientGender,
      'symptoms': symptoms,
      'imagePath': imagePath,
      'inputLanguage': inputLanguage,
      'severity': severity.name,
      'diagnosis': diagnosis,
      'recommendation': recommendation,
      'referralNote': referralNote,
      'confidenceScore': confidenceScore,
      'isOffline': isOffline ? 1 : 0,
    };
  }

  factory TriageEncounter.fromMap(Map<String, dynamic> map) {
    return TriageEncounter(
      id: map['id'],
      timestamp: DateTime.parse(map['timestamp']),
      patientName: map['patientName'],
      patientAge: map['patientAge'],
      patientWeight: map['patientWeight']?.toDouble(),
      patientGender: map['patientGender'],
      symptoms: map['symptoms'],
      imagePath: map['imagePath'],
      inputLanguage: map['inputLanguage'],
      severity: TriageSeverity.values.firstWhere(
        (e) => e.name == map['severity'],
        orElse: () => TriageSeverity.routine,
      ),
      diagnosis: map['diagnosis'],
      recommendation: map['recommendation'],
      referralNote: map['referralNote'],
      confidenceScore: map['confidenceScore']?.toDouble() ?? 0.0,
      isOffline: map['isOffline'] == 1,
    );
  }
}

enum TriageSeverity {
  emergency, // Red - Immediate life threat
  urgent, // Orange - Serious, needs attention within hours
  standard, // Yellow - Moderate, within 24 hours
  routine, // Green - Minor, can wait
}

extension TriageSeverityExt on TriageSeverity {
  String get label {
    switch (this) {
      case TriageSeverity.emergency:
        return 'EMERGENCY';
      case TriageSeverity.urgent:
        return 'URGENT';
      case TriageSeverity.standard:
        return 'STANDARD';
      case TriageSeverity.routine:
        return 'ROUTINE';
    }
  }

  String get description {
    switch (this) {
      case TriageSeverity.emergency:
        return 'Immediate medical attention required. Life-threatening condition.';
      case TriageSeverity.urgent:
        return 'Needs medical attention within a few hours.';
      case TriageSeverity.standard:
        return 'Should be seen within 24 hours.';
      case TriageSeverity.routine:
        return 'Can be managed with basic care. Follow up if symptoms worsen.';
    }
  }
}
