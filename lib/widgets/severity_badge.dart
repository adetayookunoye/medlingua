import 'package:flutter/material.dart';
import '../models/triage_encounter.dart';
import '../theme/app_theme.dart';

/// Reusable severity badge displayed as a colored chip.
class SeverityBadge extends StatelessWidget {
  final TriageSeverity severity;
  final double fontSize;

  const SeverityBadge({
    super.key,
    required this.severity,
    this.fontSize = 10,
  });

  @override
  Widget build(BuildContext context) {
    final color = severityColor(severity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        severity.label,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// Map a [TriageSeverity] to its display color.
  static Color severityColor(TriageSeverity severity) {
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
}
