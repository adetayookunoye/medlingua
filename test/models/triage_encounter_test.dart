import 'package:flutter_test/flutter_test.dart';
import 'package:medlingua/models/triage_encounter.dart';

void main() {
  group('TriageEncounter', () {
    final sampleMap = {
      'id': 'test-123',
      'timestamp': '2026-04-07T10:30:00.000',
      'patientName': 'Amina Bello',
      'patientAge': 4,
      'patientGender': 'Female',
      'symptoms': 'fever, rash',
      'imagePath': '/data/images/rash.jpg',
      'inputLanguage': 'en',
      'severity': 'urgent',
      'diagnosis': 'Possible measles',
      'recommendation': 'Refer to clinic',
      'referralNote': 'Urgent referral needed',
      'confidenceScore': 0.85,
      'isOffline': 1,
    };

    test('fromMap creates valid encounter', () {
      final encounter = TriageEncounter.fromMap(sampleMap);

      expect(encounter.id, 'test-123');
      expect(encounter.patientName, 'Amina Bello');
      expect(encounter.patientAge, 4);
      expect(encounter.patientGender, 'Female');
      expect(encounter.symptoms, 'fever, rash');
      expect(encounter.imagePath, '/data/images/rash.jpg');
      expect(encounter.inputLanguage, 'en');
      expect(encounter.severity, TriageSeverity.urgent);
      expect(encounter.diagnosis, 'Possible measles');
      expect(encounter.recommendation, 'Refer to clinic');
      expect(encounter.referralNote, 'Urgent referral needed');
      expect(encounter.confidenceScore, 0.85);
      expect(encounter.isOffline, true);
    });

    test('toMap serializes correctly', () {
      final encounter = TriageEncounter.fromMap(sampleMap);
      final map = encounter.toMap();

      expect(map['id'], 'test-123');
      expect(map['patientName'], 'Amina Bello');
      expect(map['severity'], 'urgent');
      expect(map['isOffline'], 1);
      expect(map['confidenceScore'], 0.85);
    });

    test('toMap/fromMap round-trip preserves data', () {
      final original = TriageEncounter.fromMap(sampleMap);
      final roundTripped = TriageEncounter.fromMap(original.toMap());

      expect(roundTripped.id, original.id);
      expect(roundTripped.patientName, original.patientName);
      expect(roundTripped.patientAge, original.patientAge);
      expect(roundTripped.severity, original.severity);
      expect(roundTripped.confidenceScore, original.confidenceScore);
      expect(roundTripped.isOffline, original.isOffline);
      expect(roundTripped.timestamp.toIso8601String(),
          original.timestamp.toIso8601String());
    });

    test('fromMap handles null optional fields', () {
      final minimalMap = {
        'id': 'min-1',
        'timestamp': '2026-04-07T12:00:00.000',
        'patientName': 'John',
        'symptoms': 'headache',
        'inputLanguage': 'en',
        'severity': 'routine',
        'diagnosis': 'Tension headache',
        'recommendation': 'Rest',
        'confidenceScore': 0.5,
        'isOffline': 0,
      };

      final encounter = TriageEncounter.fromMap(minimalMap);
      expect(encounter.patientAge, isNull);
      expect(encounter.patientGender, isNull);
      expect(encounter.imagePath, isNull);
      expect(encounter.referralNote, isNull);
      expect(encounter.isOffline, false);
    });

    test('fromMap defaults to routine for unknown severity', () {
      final map = Map<String, dynamic>.from(sampleMap);
      map['severity'] = 'unknown_severity';
      final encounter = TriageEncounter.fromMap(map);
      expect(encounter.severity, TriageSeverity.routine);
    });

    test('fromMap handles missing confidenceScore gracefully', () {
      final map = Map<String, dynamic>.from(sampleMap);
      map['confidenceScore'] = null;
      final encounter = TriageEncounter.fromMap(map);
      expect(encounter.confidenceScore, 0.0);
    });
  });

  group('TriageSeverity', () {
    test('all values have labels', () {
      for (final severity in TriageSeverity.values) {
        expect(severity.label, isNotEmpty);
      }
    });

    test('all values have descriptions', () {
      for (final severity in TriageSeverity.values) {
        expect(severity.description, isNotEmpty);
      }
    });

    test('labels are uppercase', () {
      expect(TriageSeverity.emergency.label, 'EMERGENCY');
      expect(TriageSeverity.urgent.label, 'URGENT');
      expect(TriageSeverity.standard.label, 'STANDARD');
      expect(TriageSeverity.routine.label, 'ROUTINE');
    });

    test('enum names match expected strings', () {
      expect(TriageSeverity.emergency.name, 'emergency');
      expect(TriageSeverity.urgent.name, 'urgent');
      expect(TriageSeverity.standard.name, 'standard');
      expect(TriageSeverity.routine.name, 'routine');
    });
  });
}
