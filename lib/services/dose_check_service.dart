import 'package:flutter/foundation.dart';

/// On-device dose calculator and drug interaction checker.
///
/// Contains a built-in WHO Essential Medicines formulary subset covering
/// medications commonly used at community health posts. All data is
/// embedded — no internet required.
///
/// Two capabilities:
/// 1. **Dose calculation**: weight/age-based dosing per WHO IMCI guidelines.
/// 2. **Interaction check**: flags dangerous co-prescriptions from a curated
///    interaction matrix.
class DoseCheckService {
  /// Lookup a drug by name (case-insensitive, partial match).
  DrugInfo? findDrug(String query) {
    final q = query.toLowerCase().trim();
    for (final drug in _formulary) {
      if (drug.name.toLowerCase() == q ||
          drug.aliases.any((a) => a.toLowerCase() == q)) {
        return drug;
      }
    }
    // Partial match fallback
    for (final drug in _formulary) {
      if (drug.name.toLowerCase().contains(q) ||
          drug.aliases.any((a) => a.toLowerCase().contains(q))) {
        return drug;
      }
    }
    return null;
  }

  /// Compute the recommended dose for a drug given patient weight and age.
  ///
  /// Returns null if the drug is not in the formulary.
  DoseResult? calculateDose({
    required String drugName,
    required double weightKg,
    int? ageMonths,
  }) {
    try {
      final drug = findDrug(drugName);
      if (drug == null) return null;

      // Pick the appropriate rule (child vs adult)
      final rule =
          (ageMonths != null && ageMonths < 60)
              ? drug.childDosing
              : drug.adultDosing;
      if (rule == null) return null;

      final dosePerKg = rule.mgPerKg;
      final rawDose = dosePerKg * weightKg;
      final dose = rawDose.clamp(rule.minDoseMg, rule.maxDoseMg);

      return DoseResult(
        drugName: drug.name,
        dose: dose,
        unit: rule.unit,
        frequency: rule.frequency,
        route: rule.route,
        durationDays: rule.durationDays,
        warnings: _warningsForPatient(drug, weightKg, ageMonths),
        source: rule.source,
      );
    } catch (e, stackTrace) {
      debugPrint('DoseCheckService.calculateDose: $e\n$stackTrace');
      return null;
    }
  }

  /// Check for dangerous interactions between two or more drugs.
  ///
  /// Returns a list of interaction alerts (empty = no known interactions).
  List<InteractionAlert> checkInteractions(List<String> drugNames) {
    try {
      final alerts = <InteractionAlert>[];
      final resolved =
          drugNames
              .map((n) => findDrug(n))
              .where((d) => d != null)
              .map((d) => d!.name.toLowerCase())
              .toList();

      for (int i = 0; i < resolved.length; i++) {
        for (int j = i + 1; j < resolved.length; j++) {
          final key = _interactionKey(resolved[i], resolved[j]);
          final alert = _interactions[key];
          if (alert != null) {
            alerts.add(alert);
          }
        }
      }

      return alerts;
    } catch (e, stackTrace) {
      debugPrint('DoseCheckService.checkInteractions: $e\n$stackTrace');
      return [];
    }
  }

  /// Get all drug names in the formulary (for autocomplete).
  List<String> get drugNames => _formulary.map((d) => d.name).toList();

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  List<String> _warningsForPatient(
    DrugInfo drug,
    double weightKg,
    int? ageMonths,
  ) {
    final warnings = <String>[...drug.generalWarnings];

    if (ageMonths != null && ageMonths < 2) {
      warnings.add(
        'Neonate (<2 months): use with extreme caution. '
        'Refer to facility if possible.',
      );
    }
    if (ageMonths != null && ageMonths < 6 && drug.avoidUnder6Months) {
      warnings.add('Not recommended for infants under 6 months.');
    }
    if (weightKg < 5) {
      warnings.add(
        'Very low weight (<5 kg): dose may need adjustment by a clinician.',
      );
    }

    return warnings;
  }

  String _interactionKey(String a, String b) {
    final sorted = [a.toLowerCase(), b.toLowerCase()]..sort();
    return '${sorted[0]}|${sorted[1]}';
  }

  // ---------------------------------------------------------------------------
  // WHO Essential Medicines Formulary (community-level subset)
  // ---------------------------------------------------------------------------

  static final List<DrugInfo> _formulary = [
    DrugInfo(
      name: 'Amoxicillin',
      aliases: ['amoxycillin', 'amoxil'],
      category: 'Antibiotic',
      childDosing: DosingRule(
        mgPerKg: 25,
        minDoseMg: 62.5,
        maxDoseMg: 500,
        unit: 'mg',
        frequency: 'twice daily',
        route: 'oral',
        durationDays: 5,
        source: 'WHO IMCI — Pneumonia, OMA',
      ),
      adultDosing: DosingRule(
        mgPerKg: 0,
        minDoseMg: 500,
        maxDoseMg: 1000,
        unit: 'mg',
        frequency: 'three times daily',
        route: 'oral',
        durationDays: 5,
        source: 'WHO EML',
      ),
      generalWarnings: ['Check for penicillin allergy before administering.'],
      avoidUnder6Months: false,
    ),
    DrugInfo(
      name: 'Paracetamol',
      aliases: ['acetaminophen', 'tylenol', 'panadol'],
      category: 'Analgesic / Antipyretic',
      childDosing: DosingRule(
        mgPerKg: 15,
        minDoseMg: 60,
        maxDoseMg: 500,
        unit: 'mg',
        frequency: 'every 4-6 hours (max 4 doses/day)',
        route: 'oral',
        durationDays: 3,
        source: 'WHO IMCI — Fever management',
      ),
      adultDosing: DosingRule(
        mgPerKg: 0,
        minDoseMg: 500,
        maxDoseMg: 1000,
        unit: 'mg',
        frequency: 'every 4-6 hours (max 4 g/day)',
        route: 'oral',
        durationDays: 3,
        source: 'WHO EML',
      ),
      generalWarnings: [
        'Do not exceed 4 doses per day.',
        'Avoid in severe liver disease.',
      ],
      avoidUnder6Months: false,
    ),
    DrugInfo(
      name: 'ORS',
      aliases: ['oral rehydration salts', 'oral rehydration solution'],
      category: 'Rehydration',
      childDosing: DosingRule(
        mgPerKg: 75,
        minDoseMg: 200,
        maxDoseMg: 1000,
        unit: 'mL',
        frequency: 'over 4 hours (reassess)',
        route: 'oral',
        durationDays: 1,
        source: 'WHO IMCI — Diarrhoea Plan B',
      ),
      adultDosing: DosingRule(
        mgPerKg: 75,
        minDoseMg: 500,
        maxDoseMg: 4000,
        unit: 'mL',
        frequency: 'over 4 hours (reassess)',
        route: 'oral',
        durationDays: 1,
        source: 'WHO IMCI',
      ),
      generalWarnings: [
        'If patient cannot drink, refer for IV fluids immediately.',
      ],
      avoidUnder6Months: false,
    ),
    DrugInfo(
      name: 'Zinc',
      aliases: ['zinc sulfate', 'zinc supplement'],
      category: 'Supplement',
      childDosing: DosingRule(
        mgPerKg: 0,
        minDoseMg: 10,
        maxDoseMg: 20,
        unit: 'mg',
        frequency: 'once daily',
        route: 'oral',
        durationDays: 14,
        source: 'WHO IMCI — Diarrhoea (10 mg <6 months, 20 mg ≥6 months)',
      ),
      adultDosing: null,
      generalWarnings: [
        'Give 10 mg/day for infants <6 months, 20 mg/day for older children.',
        'Continue for full 14 days even if diarrhoea stops.',
      ],
      avoidUnder6Months: false,
    ),
    DrugInfo(
      name: 'Artemether-Lumefantrine',
      aliases: ['coartem', 'al', 'act'],
      category: 'Antimalarial (ACT)',
      childDosing: DosingRule(
        mgPerKg: 2,
        minDoseMg: 20,
        maxDoseMg: 80,
        unit: 'mg artemether',
        frequency: 'twice daily (with food)',
        route: 'oral',
        durationDays: 3,
        source: 'WHO — Uncomplicated P. falciparum malaria',
      ),
      adultDosing: DosingRule(
        mgPerKg: 0,
        minDoseMg: 80,
        maxDoseMg: 80,
        unit: 'mg artemether',
        frequency: 'twice daily (with food)',
        route: 'oral',
        durationDays: 3,
        source: 'WHO EML',
      ),
      generalWarnings: [
        'Not for severe malaria — refer for parenteral artesunate.',
        'Give with fatty food for better absorption.',
        'Do not use in first trimester of pregnancy.',
      ],
      avoidUnder6Months: true,
    ),
    DrugInfo(
      name: 'Cotrimoxazole',
      aliases: [
        'septrin',
        'bactrim',
        'tmp-smx',
        'trimethoprim-sulfamethoxazole',
      ],
      category: 'Antibiotic',
      childDosing: DosingRule(
        mgPerKg: 4,
        minDoseMg: 20,
        maxDoseMg: 160,
        unit: 'mg TMP component',
        frequency: 'twice daily',
        route: 'oral',
        durationDays: 5,
        source: 'WHO IMCI — Dysentery, cholera prophylaxis',
      ),
      adultDosing: DosingRule(
        mgPerKg: 0,
        minDoseMg: 160,
        maxDoseMg: 320,
        unit: 'mg TMP component',
        frequency: 'twice daily',
        route: 'oral',
        durationDays: 5,
        source: 'WHO EML',
      ),
      generalWarnings: [
        'Contraindicated in severe sulfa allergy.',
        'Monitor for skin rash — stop immediately if Stevens-Johnson suspected.',
      ],
      avoidUnder6Months: true,
    ),
    DrugInfo(
      name: 'Ibuprofen',
      aliases: ['brufen', 'advil'],
      category: 'NSAID / Antipyretic',
      childDosing: DosingRule(
        mgPerKg: 10,
        minDoseMg: 50,
        maxDoseMg: 400,
        unit: 'mg',
        frequency: 'every 6-8 hours (max 3 doses/day)',
        route: 'oral',
        durationDays: 3,
        source: 'WHO IMCI — Fever, pain (>3 months old)',
      ),
      adultDosing: DosingRule(
        mgPerKg: 0,
        minDoseMg: 200,
        maxDoseMg: 400,
        unit: 'mg',
        frequency: 'every 6-8 hours (max 1200 mg/day)',
        route: 'oral',
        durationDays: 3,
        source: 'WHO EML',
      ),
      generalWarnings: [
        'Avoid if dehydrated — risk of renal injury.',
        'Do not give to children under 3 months.',
        'Avoid in dengue — risk of bleeding.',
      ],
      avoidUnder6Months: true,
    ),
    DrugInfo(
      name: 'Metronidazole',
      aliases: ['flagyl'],
      category: 'Antibiotic / Antiprotozoal',
      childDosing: DosingRule(
        mgPerKg: 7.5,
        minDoseMg: 37.5,
        maxDoseMg: 400,
        unit: 'mg',
        frequency: 'three times daily',
        route: 'oral',
        durationDays: 7,
        source: 'WHO — Amoebiasis, giardiasis',
      ),
      adultDosing: DosingRule(
        mgPerKg: 0,
        minDoseMg: 400,
        maxDoseMg: 800,
        unit: 'mg',
        frequency: 'three times daily',
        route: 'oral',
        durationDays: 7,
        source: 'WHO EML',
      ),
      generalWarnings: [
        'Avoid alcohol during and 48 hours after treatment.',
        'Metallic taste is expected — not dangerous.',
      ],
      avoidUnder6Months: false,
    ),
    DrugInfo(
      name: 'Gentamicin',
      aliases: [],
      category: 'Antibiotic (Injectable)',
      childDosing: DosingRule(
        mgPerKg: 5,
        minDoseMg: 10,
        maxDoseMg: 80,
        unit: 'mg',
        frequency: 'once daily (IM injection)',
        route: 'intramuscular',
        durationDays: 7,
        source: 'WHO IMCI — Pre-referral for serious bacterial infection',
      ),
      adultDosing: DosingRule(
        mgPerKg: 5,
        minDoseMg: 80,
        maxDoseMg: 320,
        unit: 'mg',
        frequency: 'once daily',
        route: 'intramuscular',
        durationDays: 7,
        source: 'WHO EML',
      ),
      generalWarnings: [
        'Nephrotoxic — monitor renal function if possible.',
        'Ototoxic — watch for hearing changes.',
        'Pre-referral use: give FIRST DOSE and refer immediately.',
      ],
      avoidUnder6Months: false,
    ),
    DrugInfo(
      name: 'Vitamin A',
      aliases: ['retinol'],
      category: 'Supplement',
      childDosing: DosingRule(
        mgPerKg: 0,
        minDoseMg: 50000, // IU not mg — label specifies
        maxDoseMg: 200000,
        unit: 'IU',
        frequency: 'single dose (repeat at day 2 and day 14 for measles)',
        route: 'oral',
        durationDays: 1,
        source: 'WHO IMCI — Measles, severe malnutrition',
      ),
      adultDosing: null,
      generalWarnings: [
        'Dose by age: <6 mo = 50,000 IU; 6-11 mo = 100,000 IU; ≥12 mo = 200,000 IU.',
        'Do not give to pregnant women (teratogenic).',
      ],
      avoidUnder6Months: false,
    ),
  ];

  // ---------------------------------------------------------------------------
  // Drug interactions (curated danger pairs)
  // ---------------------------------------------------------------------------

  static final Map<String, InteractionAlert> _interactions = {
    'ibuprofen|metronidazole': const InteractionAlert(
      drugA: 'Ibuprofen',
      drugB: 'Metronidazole',
      severity: InteractionSeverity.moderate,
      description:
          'Ibuprofen may increase the blood-thinning effect of metronidazole. '
          'Risk of GI bleeding is elevated.',
      recommendation: 'Prefer paracetamol for pain/fever management instead.',
    ),
    'gentamicin|ibuprofen': const InteractionAlert(
      drugA: 'Gentamicin',
      drugB: 'Ibuprofen',
      severity: InteractionSeverity.severe,
      description:
          'Both are nephrotoxic. Combined use significantly increases '
          'risk of acute kidney injury, especially in dehydrated patients.',
      recommendation:
          'Avoid combination. Use paracetamol for fever/pain instead.',
    ),
    'cotrimoxazole|metronidazole': const InteractionAlert(
      drugA: 'Cotrimoxazole',
      drugB: 'Metronidazole',
      severity: InteractionSeverity.moderate,
      description:
          'Both can cause blood dyscrasias. Concurrent use may increase '
          'risk of bone marrow suppression.',
      recommendation:
          'Monitor for signs of anemia or unusual bleeding. '
          'Use only if both are clinically indicated.',
    ),
    'artemether-lumefantrine|metronidazole': const InteractionAlert(
      drugA: 'Artemether-Lumefantrine',
      drugB: 'Metronidazole',
      severity: InteractionSeverity.moderate,
      description:
          'Metronidazole may inhibit the metabolism of lumefantrine, '
          'potentially increasing the risk of QT prolongation.',
      recommendation:
          'Use with caution. Monitor for palpitations or dizziness.',
    ),
    'amoxicillin|metronidazole': const InteractionAlert(
      drugA: 'Amoxicillin',
      drugB: 'Metronidazole',
      severity: InteractionSeverity.low,
      description:
          'Generally safe combination, often used together intentionally '
          '(e.g., dental infections). Increased GI side effects possible.',
      recommendation:
          'Acceptable combination. Advise patient about '
          'possible nausea or diarrhoea.',
    ),
  };
}

// =============================================================================
// Data models
// =============================================================================

class DrugInfo {
  final String name;
  final List<String> aliases;
  final String category;
  final DosingRule? childDosing;
  final DosingRule? adultDosing;
  final List<String> generalWarnings;
  final bool avoidUnder6Months;

  const DrugInfo({
    required this.name,
    required this.aliases,
    required this.category,
    this.childDosing,
    this.adultDosing,
    this.generalWarnings = const [],
    this.avoidUnder6Months = false,
  });
}

class DosingRule {
  /// mg per kg body weight. 0 means use fixed dose (minDoseMg).
  final double mgPerKg;
  final double minDoseMg;
  final double maxDoseMg;
  final String unit;
  final String frequency;
  final String route;
  final int durationDays;
  final String source;

  const DosingRule({
    required this.mgPerKg,
    required this.minDoseMg,
    required this.maxDoseMg,
    required this.unit,
    required this.frequency,
    required this.route,
    required this.durationDays,
    required this.source,
  });
}

class DoseResult {
  final String drugName;
  final double dose;
  final String unit;
  final String frequency;
  final String route;
  final int durationDays;
  final List<String> warnings;
  final String source;

  const DoseResult({
    required this.drugName,
    required this.dose,
    required this.unit,
    required this.frequency,
    required this.route,
    required this.durationDays,
    required this.warnings,
    required this.source,
  });

  String get doseSummary =>
      '${dose.toStringAsFixed(1)} $unit $frequency ($route) for $durationDays day(s)';
}

enum InteractionSeverity { low, moderate, severe }

extension InteractionSeverityExt on InteractionSeverity {
  String get label {
    switch (this) {
      case InteractionSeverity.low:
        return 'LOW';
      case InteractionSeverity.moderate:
        return 'MODERATE';
      case InteractionSeverity.severe:
        return 'SEVERE';
    }
  }
}

class InteractionAlert {
  final String drugA;
  final String drugB;
  final InteractionSeverity severity;
  final String description;
  final String recommendation;

  const InteractionAlert({
    required this.drugA,
    required this.drugB,
    required this.severity,
    required this.description,
    required this.recommendation,
  });
}
