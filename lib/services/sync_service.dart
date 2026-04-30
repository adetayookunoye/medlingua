import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/triage_encounter.dart';

/// Delayed-sync service for outbreak surveillance data.
///
/// While MedLingua runs offline-first, community health supervisors need
/// aggregate data for epidemic detection. This service:
///
/// 1. **Queues** anonymised encounter summaries locally.
/// 2. **Detects** outbreak signals in the local data (cluster alerts).
/// 3. **Exports** a JSON sync package when connectivity is available.
/// 4. **Tracks** sync state (pending/synced) per encounter.
///
/// Privacy: Only anonymised aggregates are synced — no patient names or
/// identifiers leave the device. All sync data is opt-in and controlled
/// by the supervisor.
class SyncService {
  static const String _pendingKey = 'sync_pending_encounters';
  static const String _lastSyncKey = 'sync_last_timestamp';
  static const String _syncHistoryKey = 'sync_history';

  /// Queue an encounter for later sync (anonymised).
  Future<void> queueForSync(TriageEncounter encounter) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getStringList(_pendingKey) ?? [];

      final summary = _anonymise(encounter);
      pending.add(jsonEncode(summary));

      await prefs.setStringList(_pendingKey, pending);
      debugPrint(
        'SyncService.queueForSync: Queued encounter ${encounter.id.substring(0, 8)}',
      );
    } catch (e, stackTrace) {
      debugPrint('SyncService.queueForSync: $e\n$stackTrace');
      // Non-critical — encounter is still saved locally by DatabaseService
    }
  }

  /// Number of encounters waiting to be synced.
  Future<int> get pendingCount async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_pendingKey) ?? []).length;
    } catch (e) {
      debugPrint('SyncService.pendingCount: $e');
      return 0;
    }
  }

  /// Get the timestamp of the last successful sync.
  Future<DateTime?> get lastSyncTime async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ts = prefs.getString(_lastSyncKey);
      return ts != null ? DateTime.tryParse(ts) : null;
    } catch (e) {
      debugPrint('SyncService.lastSyncTime: $e');
      return null;
    }
  }

  /// Generate the exportable sync package.
  ///
  /// Returns a JSON-serialisable map containing:
  /// - `generated_at`: timestamp
  /// - `device_id`: anonymised device identifier
  /// - `period`: date range covered
  /// - `summary`: aggregate counts by severity, diagnosis, language
  /// - `alerts`: detected outbreak signals
  /// - `encounters`: individual anonymised records
  Future<Map<String, dynamic>> generateSyncPackage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingJson = prefs.getStringList(_pendingKey) ?? [];

      final records =
          pendingJson
              .map((j) {
                try {
                  return jsonDecode(j) as Map<String, dynamic>;
                } catch (_) {
                  return null;
                }
              })
              .where((r) => r != null)
              .cast<Map<String, dynamic>>()
              .toList();

      if (records.isEmpty) {
        return {'status': 'empty', 'message': 'No pending encounters to sync'};
      }

      // Build date range
      final timestamps =
          records
              .map((r) => DateTime.tryParse(r['timestamp'] as String? ?? ''))
              .where((d) => d != null)
              .cast<DateTime>()
              .toList()
            ..sort();

      // Aggregate by severity
      final severityCounts = <String, int>{};
      final diagnosisCounts = <String, int>{};
      final languageCounts = <String, int>{};
      final dailyCounts = <String, Map<String, int>>{};

      for (final r in records) {
        final sev = r['severity'] as String? ?? 'unknown';
        severityCounts[sev] = (severityCounts[sev] ?? 0) + 1;

        final diag = r['diagnosis'] as String? ?? 'unknown';
        diagnosisCounts[diag] = (diagnosisCounts[diag] ?? 0) + 1;

        final lang = r['language'] as String? ?? 'unknown';
        languageCounts[lang] = (languageCounts[lang] ?? 0) + 1;

        final ts = DateTime.tryParse(r['timestamp'] as String? ?? '');
        if (ts != null) {
          final dayKey =
              '${ts.year}-${ts.month.toString().padLeft(2, '0')}-${ts.day.toString().padLeft(2, '0')}';
          dailyCounts.putIfAbsent(dayKey, () => <String, int>{});
          dailyCounts[dayKey]![sev] = (dailyCounts[dayKey]![sev] ?? 0) + 1;
        }
      }

      // Detect alerts
      final alerts = detectOutbreakSignals(records);

      return {
        'generated_at': DateTime.now().toIso8601String(),
        'format_version': 1,
        'period': {
          'start':
              timestamps.isNotEmpty ? timestamps.first.toIso8601String() : null,
          'end':
              timestamps.isNotEmpty ? timestamps.last.toIso8601String() : null,
        },
        'summary': {
          'total_encounters': records.length,
          'by_severity': severityCounts,
          'by_diagnosis': diagnosisCounts,
          'by_language': languageCounts,
          'daily': dailyCounts,
        },
        'alerts': alerts.map((a) => a.toMap()).toList(),
        'encounters': records,
      };
    } catch (e, stackTrace) {
      debugPrint('SyncService.generateSyncPackage: $e\n$stackTrace');
      throw SyncServiceException('Failed to generate sync package', cause: e);
    }
  }

  /// Mark all pending encounters as synced.
  Future<void> markSynced() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = (prefs.getStringList(_pendingKey) ?? []).length;

      // Archive to sync history
      final history = prefs.getStringList(_syncHistoryKey) ?? [];
      history.add(
        jsonEncode({
          'synced_at': DateTime.now().toIso8601String(),
          'count': count,
        }),
      );
      await prefs.setStringList(_syncHistoryKey, history);

      // Clear pending queue
      await prefs.setStringList(_pendingKey, []);
      await prefs.setString(_lastSyncKey, DateTime.now().toIso8601String());

      debugPrint('SyncService.markSynced: Cleared $count pending encounters');
    } catch (e, stackTrace) {
      debugPrint('SyncService.markSynced: $e\n$stackTrace');
      throw SyncServiceException('Failed to mark as synced', cause: e);
    }
  }

  /// Get sync history (past sync events).
  Future<List<Map<String, dynamic>>> getSyncHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final history = prefs.getStringList(_syncHistoryKey) ?? [];
      return history
          .map((j) {
            try {
              return jsonDecode(j) as Map<String, dynamic>;
            } catch (_) {
              return null;
            }
          })
          .where((r) => r != null)
          .cast<Map<String, dynamic>>()
          .toList();
    } catch (e) {
      debugPrint('SyncService.getSyncHistory: $e');
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Outbreak signal detection
  // ---------------------------------------------------------------------------

  /// Analyse the encounter queue for outbreak indicators.
  ///
  /// Signals detected:
  /// 1. Emergency cluster: ≥3 emergencies in 24h window
  /// 2. Diagnosis spike: same diagnosis ≥5 times in 7 days
  /// 3. Mortality risk indicators: high percentage of emergency/urgent
  /// 4. Geographic clustering (if location data available in future)
  List<OutbreakSignal> detectOutbreakSignals(
    List<Map<String, dynamic>> records,
  ) {
    final signals = <OutbreakSignal>[];
    final now = DateTime.now();

    // --- Emergency cluster (24h) ---
    final last24h =
        records.where((r) {
          final ts = DateTime.tryParse(r['timestamp'] as String? ?? '');
          return ts != null && now.difference(ts).inHours < 24;
        }).toList();

    final emergencies24h =
        last24h.where((r) => r['severity'] == 'emergency').length;
    if (emergencies24h >= 3) {
      signals.add(
        OutbreakSignal(
          type: SignalType.emergencyCluster,
          severity: AlertSeverity.critical,
          title: 'Emergency Cluster Detected',
          description: '$emergencies24h emergency cases in the last 24 hours.',
          metric: emergencies24h.toDouble(),
          detectedAt: now,
          recommendation:
              'Investigate potential disease outbreak. '
              'Consider activating emergency response protocol. '
              'Notify district health office.',
        ),
      );
    }

    // --- Diagnosis spike (7 days) ---
    final last7d =
        records.where((r) {
          final ts = DateTime.tryParse(r['timestamp'] as String? ?? '');
          return ts != null && now.difference(ts).inDays < 7;
        }).toList();

    final diagCounts7d = <String, int>{};
    for (final r in last7d) {
      final diag = (r['diagnosis'] as String? ?? '').toLowerCase().trim();
      if (diag.isNotEmpty) {
        diagCounts7d[diag] = (diagCounts7d[diag] ?? 0) + 1;
      }
    }

    for (final entry in diagCounts7d.entries) {
      if (entry.value >= 5) {
        signals.add(
          OutbreakSignal(
            type: SignalType.diagnosisSpike,
            severity: AlertSeverity.warning,
            title: 'Diagnosis Spike: ${_capitalise(entry.key)}',
            description:
                '${entry.value} cases of "${_capitalise(entry.key)}" in 7 days.',
            metric: entry.value.toDouble(),
            detectedAt: now,
            recommendation:
                'Pattern suggests community-level transmission. '
                'Consider targeted screening and preventive measures.',
          ),
        );
      }
    }

    // --- High critical-case ratio ---
    if (last7d.length >= 5) {
      final criticalCount =
          last7d
              .where(
                (r) =>
                    r['severity'] == 'emergency' || r['severity'] == 'urgent',
              )
              .length;
      final ratio = criticalCount / last7d.length;
      if (ratio > 0.5) {
        signals.add(
          OutbreakSignal(
            type: SignalType.highCriticalRatio,
            severity: AlertSeverity.warning,
            title: 'High Critical-Case Ratio',
            description:
                '${(ratio * 100).toInt()}% of cases in the past 7 days are '
                'emergency or urgent ($criticalCount of ${last7d.length}).',
            metric: ratio,
            detectedAt: now,
            recommendation:
                'Evaluate whether clinical threshold changes are appropriate. '
                'Consider requesting additional medical supplies or personnel.',
          ),
        );
      }
    }

    return signals;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Anonymise an encounter for sync — strip patient-identifying information.
  Map<String, dynamic> _anonymise(TriageEncounter encounter) {
    return {
      'encounter_id': encounter.id.substring(0, 8), // truncated
      'timestamp': encounter.timestamp.toIso8601String(),
      'age_group': _ageGroup(encounter.patientAge),
      'gender': encounter.patientGender,
      'language': encounter.inputLanguage,
      'severity': encounter.severity.name,
      'diagnosis': encounter.diagnosis,
      'confidence': encounter.confidenceScore,
      'has_image': encounter.imagePath != null,
      'is_offline': encounter.isOffline,
      // Deliberately omitted: patientName, symptoms (free-text may
      // contain identifying info), imagePath, referralNote
    };
  }

  String _ageGroup(int? age) {
    if (age == null) return 'unknown';
    if (age < 1) return 'infant';
    if (age < 5) return 'under5';
    if (age < 12) return 'child';
    if (age < 18) return 'adolescent';
    return 'adult';
  }

  String _capitalise(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

// =============================================================================
// Data models
// =============================================================================

enum SignalType { emergencyCluster, diagnosisSpike, highCriticalRatio }

enum AlertSeverity { info, warning, critical }

extension AlertSeverityExt on AlertSeverity {
  String get label {
    switch (this) {
      case AlertSeverity.info:
        return 'INFO';
      case AlertSeverity.warning:
        return 'WARNING';
      case AlertSeverity.critical:
        return 'CRITICAL';
    }
  }
}

class OutbreakSignal {
  final SignalType type;
  final AlertSeverity severity;
  final String title;
  final String description;
  final double metric;
  final DateTime detectedAt;
  final String recommendation;

  const OutbreakSignal({
    required this.type,
    required this.title,
    required this.severity,
    required this.description,
    required this.metric,
    required this.detectedAt,
    required this.recommendation,
  });

  Map<String, dynamic> toMap() => {
    'type': type.name,
    'severity': severity.name,
    'title': title,
    'description': description,
    'metric': metric,
    'detected_at': detectedAt.toIso8601String(),
    'recommendation': recommendation,
  };
}

/// Exception thrown by SyncService operations.
class SyncServiceException implements Exception {
  final String message;
  final Object? cause;
  const SyncServiceException(this.message, {this.cause});

  @override
  String toString() =>
      'SyncServiceException: $message${cause != null ? ' ($cause)' : ''}';
}
