import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlingua/models/triage_encounter.dart';
import 'package:medlingua/screens/result_screen.dart';

void main() {
  group('ResultScreen', () {
    final testEncounter = TriageEncounter(
      id: 'test-1',
      timestamp: DateTime(2026, 4, 7, 10, 30),
      patientName: 'Amina Bello',
      patientAge: 4,
      patientGender: 'Female',
      symptoms: 'fever, rash for 3 days',
      inputLanguage: 'en',
      severity: TriageSeverity.urgent,
      diagnosis: 'Possible measles or viral exanthem',
      recommendation: '1. Monitor temperature\n2. Ensure hydration\n3. Refer to clinic',
      confidenceScore: 0.82,
      isOffline: true,
    );

    Widget buildTestWidget(TriageEncounter encounter) {
      return MaterialApp(
        home: ResultScreen(encounter: encounter),
      );
    }

    testWidgets('shows severity banner', (tester) async {
      await tester.pumpWidget(buildTestWidget(testEncounter));
      await tester.pump();

      expect(find.text('URGENT'), findsOneWidget);
    });

    testWidgets('shows patient name', (tester) async {
      await tester.pumpWidget(buildTestWidget(testEncounter));
      await tester.pump();

      expect(find.text('Amina Bello'), findsOneWidget);
    });

    testWidgets('shows diagnosis', (tester) async {
      await tester.pumpWidget(buildTestWidget(testEncounter));
      await tester.pump();

      expect(find.text('Possible measles or viral exanthem'), findsOneWidget);
    });

    testWidgets('shows confidence score', (tester) async {
      await tester.pumpWidget(buildTestWidget(testEncounter));
      await tester.pump();

      expect(find.text('82%'), findsOneWidget);
    });

    testWidgets('shows disclaimer', (tester) async {
      await tester.pumpWidget(buildTestWidget(testEncounter));
      await tester.pump();

      expect(find.textContaining('DISCLAIMER'), findsOneWidget);
    });

    testWidgets('shows Share Referral button', (tester) async {
      await tester.pumpWidget(buildTestWidget(testEncounter));
      await tester.pump();

      expect(find.text('Share Referral'), findsOneWidget);
    });

    testWidgets('shows Dashboard button', (tester) async {
      await tester.pumpWidget(buildTestWidget(testEncounter));
      await tester.pump();

      expect(find.text('Dashboard'), findsOneWidget);
    });

    testWidgets('shows all severity levels correctly', (tester) async {
      for (final severity in TriageSeverity.values) {
        final encounter = TriageEncounter(
          id: 'test-${severity.name}',
          timestamp: DateTime.now(),
          patientName: 'Test Patient',
          symptoms: 'test',
          inputLanguage: 'en',
          severity: severity,
          diagnosis: 'Test diagnosis',
          recommendation: 'Test recommendation',
          confidenceScore: 0.5,
          isOffline: true,
        );

        await tester.pumpWidget(buildTestWidget(encounter));
        await tester.pump();

        expect(find.text(severity.label), findsOneWidget);
      }
    });
  });
}
