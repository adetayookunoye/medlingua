import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../providers/app_provider.dart';
import '../models/triage_encounter.dart';
import '../services/sync_service.dart';
import '../utils/date_utils.dart' as app_dates;
import '../theme/app_theme.dart';

/// Supervisor Dashboard — aggregated clinic-level analytics.
///
/// Shows encounter trends, severity distribution, alert signals,
/// and common diagnoses to give health supervisors visibility into
/// community health patterns across delayed-sync encounters.
class SupervisorScreen extends StatefulWidget {
  const SupervisorScreen({super.key});

  @override
  State<SupervisorScreen> createState() => _SupervisorScreenState();
}

class _SupervisorScreenState extends State<SupervisorScreen> {
  _TimeWindow _window = _TimeWindow.week;
  final SyncService _syncService = SyncService();
  int _pendingSync = 0;
  DateTime? _lastSync;
  bool _isExporting = false;

  List<TriageEncounter> _filterByWindow(List<TriageEncounter> all) {
    final now = DateTime.now();
    final cutoff = switch (_window) {
      _TimeWindow.today => DateTime(now.year, now.month, now.day),
      _TimeWindow.week => now.subtract(const Duration(days: 7)),
      _TimeWindow.month => now.subtract(const Duration(days: 30)),
      _TimeWindow.all => DateTime(2000),
    };
    return all.where((e) => e.timestamp.isAfter(cutoff)).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadSyncStatus();
  }

  Future<void> _loadSyncStatus() async {
    final pending = await _syncService.pendingCount;
    final lastSync = await _syncService.lastSyncTime;
    if (mounted) {
      setState(() {
        _pendingSync = pending;
        _lastSync = lastSync;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        final filtered = _filterByWindow(provider.encounters);
        final alerts = _buildAlerts(filtered);

        return Scaffold(
          appBar: AppBar(title: const Text('Supervisor Dashboard')),
          body: RefreshIndicator(
            onRefresh: () async {
              await provider.refreshEncounters();
              await provider.refreshStats();
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Time window picker
                  _buildWindowPicker(),
                  const SizedBox(height: 16),

                  // Alert banner (if any)
                  if (alerts.isNotEmpty) ...[
                    _buildAlertBanner(alerts),
                    const SizedBox(height: 16),
                  ],

                  // Summary cards
                  _buildSummaryRow(filtered),
                  const SizedBox(height: 20),

                  // Severity distribution bar
                  Text(
                    'Severity Distribution',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  _buildSeverityBar(filtered),
                  const SizedBox(height: 20),

                  // Daily encounter trend
                  Text(
                    'Daily Encounters',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  _buildDailyTrend(filtered),
                  const SizedBox(height: 20),

                  // Top diagnoses
                  Text(
                    'Common Conditions',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  _buildTopDiagnoses(filtered),
                  const SizedBox(height: 20),

                  // Language breakdown
                  Text(
                    'Languages Served',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  _buildLanguageBreakdown(filtered),
                  const SizedBox(height: 20),

                  // Sync & Export panel
                  Text(
                    'Data Sync & Export',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  _buildSyncPanel(context),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Time window selector ──────────────────────────────────────────

  Widget _buildWindowPicker() {
    return Row(
      children:
          _TimeWindow.values.map((w) {
            final selected = w == _window;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(
                  w.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : AppTheme.primaryGreen,
                  ),
                ),
                selected: selected,
                selectedColor: AppTheme.primaryGreen,
                backgroundColor: AppTheme.primaryGreen.withValues(alpha: 0.1),
                onSelected: (_) => setState(() => _window = w),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                side: BorderSide.none,
              ),
            );
          }).toList(),
    );
  }

  // ── Alert detection ───────────────────────────────────────────────

  List<_Alert> _buildAlerts(List<TriageEncounter> encounters) {
    final alerts = <_Alert>[];
    final now = DateTime.now();
    final last24h =
        encounters
            .where(
              (e) =>
                  e.timestamp.isAfter(now.subtract(const Duration(hours: 24))),
            )
            .toList();

    // Cluster: ≥3 emergencies in 24h
    final emergencies24h =
        last24h.where((e) => e.severity == TriageSeverity.emergency).length;
    if (emergencies24h >= 3) {
      alerts.add(
        _Alert(
          icon: Icons.warning_amber,
          color: AppTheme.triageEmergency,
          title: 'Emergency Cluster',
          message:
              '$emergencies24h emergency cases in the last 24 hours — investigate potential outbreak.',
        ),
      );
    }

    // Surge: ≥2x encounters vs. prior period
    if (_window == _TimeWindow.week && encounters.length >= 10) {
      final priorWeek = now.subtract(const Duration(days: 14));
      // We don't have access to the full list here, so compare halves
      final firstHalf =
          encounters
              .where(
                (e) =>
                    e.timestamp.isAfter(priorWeek) &&
                    e.timestamp.isBefore(now.subtract(const Duration(days: 7))),
              )
              .length;
      final secondHalf = last24h.length * 7; // project from 24h
      if (firstHalf > 0 && secondHalf > firstHalf * 2) {
        alerts.add(
          _Alert(
            icon: Icons.trending_up,
            color: AppTheme.triageUrgent,
            title: 'Volume Surge',
            message:
                'Encounter volume is trending significantly higher than the previous period.',
          ),
        );
      }
    }

    // Repeated diagnosis: same diagnosis ≥4 times in window
    final diagCounts = <String, int>{};
    for (final e in encounters) {
      final key = e.diagnosis.toLowerCase().trim();
      diagCounts[key] = (diagCounts[key] ?? 0) + 1;
    }
    for (final entry in diagCounts.entries) {
      if (entry.value >= 4) {
        alerts.add(
          _Alert(
            icon: Icons.repeat,
            color: AppTheme.warningYellow,
            title: 'Recurring: ${_capitalise(entry.key)}',
            message:
                '${entry.value} cases with similar diagnosis — may indicate a community-level pattern.',
          ),
        );
      }
    }

    return alerts;
  }

  Widget _buildAlertBanner(List<_Alert> alerts) {
    return Column(
      children:
          alerts.map((a) {
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: a.color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: a.color.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(a.icon, color: a.color, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: a.color,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          a.message,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
    );
  }

  // ── Summary row ───────────────────────────────────────────────────

  Widget _buildSummaryRow(List<TriageEncounter> encounters) {
    final total = encounters.length;
    final emergencies =
        encounters.where((e) => e.severity == TriageSeverity.emergency).length;
    final avgConfidence =
        total == 0
            ? 0.0
            : encounters.fold<double>(0, (sum, e) => sum + e.confidenceScore) /
                total;

    return Row(
      children: [
        _summaryCard('Total', '$total', Icons.people, AppTheme.primaryGreen),
        const SizedBox(width: 10),
        _summaryCard(
          'Emergencies',
          '$emergencies',
          Icons.warning,
          AppTheme.triageEmergency,
        ),
        const SizedBox(width: 10),
        _summaryCard(
          'Avg Confidence',
          '${(avgConfidence * 100).toInt()}%',
          Icons.verified,
          AppTheme.safeGreen,
        ),
      ],
    );
  }

  Widget _summaryCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 6),
              Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Severity distribution ─────────────────────────────────────────

  Widget _buildSeverityBar(List<TriageEncounter> encounters) {
    final total = encounters.length;
    if (total == 0) {
      return _emptyCard('No encounters in this period');
    }

    final counts = {
      TriageSeverity.emergency: 0,
      TriageSeverity.urgent: 0,
      TriageSeverity.standard: 0,
      TriageSeverity.routine: 0,
    };
    for (final e in encounters) {
      counts[e.severity] = (counts[e.severity] ?? 0) + 1;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Stacked horizontal bar
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 28,
                child: Row(
                  children:
                      counts.entries.map((entry) {
                        final fraction = entry.value / total;
                        if (fraction == 0) return const SizedBox.shrink();
                        return Expanded(
                          flex: (fraction * 1000).round(),
                          child: Container(
                            color: AppTheme.severityColor(entry.key),
                            alignment: Alignment.center,
                            child:
                                fraction > 0.08
                                    ? Text(
                                      '${entry.value}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                    : null,
                          ),
                        );
                      }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Legend
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children:
                  counts.entries.map((entry) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: AppTheme.severityColor(entry.key),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${entry.key.label} (${entry.value})',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    );
                  }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Daily encounter trend (sparkline-style bars) ──────────────────

  Widget _buildDailyTrend(List<TriageEncounter> encounters) {
    if (encounters.isEmpty) {
      return _emptyCard('No encounters in this period');
    }

    // Bucket encounters by date
    final buckets = <String, _DayBucket>{};
    for (final e in encounters) {
      final key =
          '${e.timestamp.year}-${e.timestamp.month.toString().padLeft(2, '0')}-${e.timestamp.day.toString().padLeft(2, '0')}';
      buckets.putIfAbsent(key, () => _DayBucket(key));
      buckets[key]!.total++;
      if (e.severity == TriageSeverity.emergency ||
          e.severity == TriageSeverity.urgent) {
        buckets[key]!.critical++;
      }
    }

    final days =
        buckets.values.toList()..sort((a, b) => a.date.compareTo(b.date));
    final maxCount = days.fold<int>(0, (m, d) => d.total > m ? d.total : m);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children:
                days.map((day) {
                  final barHeight =
                      maxCount == 0 ? 0.0 : (day.total / maxCount) * 80;
                  final critHeight =
                      maxCount == 0 ? 0.0 : (day.critical / maxCount) * 80;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            '${day.total}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppTheme.textMuted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Stack(
                            alignment: Alignment.bottomCenter,
                            children: [
                              Container(
                                height: barHeight.clamp(4.0, 80.0),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryGreen.withValues(
                                    alpha: 0.3,
                                  ),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              if (critHeight > 0)
                                Container(
                                  height: critHeight.clamp(2.0, 80.0),
                                  decoration: BoxDecoration(
                                    color: AppTheme.triageEmergency.withValues(
                                      alpha: 0.7,
                                    ),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            day.date.substring(5), // MM-DD
                            style: const TextStyle(
                              fontSize: 9,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
          ),
        ),
      ),
    );
  }

  // ── Top diagnoses ─────────────────────────────────────────────────

  Widget _buildTopDiagnoses(List<TriageEncounter> encounters) {
    if (encounters.isEmpty) {
      return _emptyCard('No encounters in this period');
    }

    final diagCounts = <String, int>{};
    for (final e in encounters) {
      final key = e.diagnosis.trim();
      diagCounts[key] = (diagCounts[key] ?? 0) + 1;
    }

    final sorted =
        diagCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(5);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children:
              top.map((entry) {
                final fraction =
                    encounters.isEmpty ? 0.0 : entry.value / encounters.length;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              entry.key,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Text(
                            '${entry.value}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryGreen,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: fraction,
                        backgroundColor: AppTheme.primaryGreen.withValues(
                          alpha: 0.1,
                        ),
                        color: AppTheme.primaryGreen,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ],
                  ),
                );
              }).toList(),
        ),
      ),
    );
  }

  // ── Language breakdown ────────────────────────────────────────────

  Widget _buildLanguageBreakdown(List<TriageEncounter> encounters) {
    if (encounters.isEmpty) {
      return _emptyCard('No encounters in this period');
    }

    final langCounts = <String, int>{};
    for (final e in encounters) {
      final key = e.inputLanguage.toUpperCase();
      langCounts[key] = (langCounts[key] ?? 0) + 1;
    }

    final sorted =
        langCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          children:
              sorted.map((entry) {
                return Chip(
                  avatar: CircleAvatar(
                    backgroundColor: AppTheme.primaryGreen,
                    radius: 12,
                    child: Text(
                      entry.key,
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  label: Text(
                    '${entry.value} encounters',
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: AppTheme.primaryGreen.withValues(
                    alpha: 0.05,
                  ),
                  side: BorderSide.none,
                );
              }).toList(),
        ),
      ),
    );
  }

  // ── Sync & Export panel ─────────────────────────────────────────

  Widget _buildSyncPanel(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status row
            Row(
              children: [
                Icon(
                  _pendingSync > 0
                      ? Icons.cloud_upload_outlined
                      : Icons.cloud_done,
                  color:
                      _pendingSync > 0
                          ? AppTheme.warningYellow
                          : AppTheme.safeGreen,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _pendingSync > 0
                            ? '$_pendingSync encounters pending sync'
                            : 'All encounters synced',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      if (_lastSync != null)
                        Text(
                          'Last sync: ${app_dates.formatDateTime(_lastSync!)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Privacy notice
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.primaryGreen.withValues(alpha: 0.15),
                ),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shield, size: 16, color: AppTheme.primaryGreen),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Patient names and identifying details are stripped '
                      'before export. Only anonymised aggregates leave this device.',
                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        _isExporting ? null : () => _exportSyncPackage(context),
                    icon:
                        _isExporting
                            ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.download, size: 18),
                    label: Text(_isExporting ? 'Exporting...' : 'Export JSON'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        _pendingSync == 0 ? null : () => _markSynced(context),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Mark Synced'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportSyncPackage(BuildContext context) async {
    setState(() => _isExporting = true);
    try {
      final package = await _syncService.generateSyncPackage();
      final jsonStr = const JsonEncoder.withIndent('  ').convert(package);

      if (!context.mounted) return;

      // Show the export data in a dialog (in production, write to file or share)
      showDialog(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text('Sync Package'),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: SingleChildScrollView(
                  child: SelectableText(
                    jsonStr,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _markSynced(BuildContext context) async {
    try {
      await _syncService.markSynced();
      await _loadSyncStatus();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All encounters marked as synced'),
            backgroundColor: AppTheme.safeGreen,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Sync failed: $e')));
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────

  Widget _emptyCard(String message) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            message,
            style: TextStyle(color: Colors.grey[400], fontSize: 13),
          ),
        ),
      ),
    );
  }

  String _capitalise(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

// ── Private types ─────────────────────────────────────────────────

enum _TimeWindow {
  today('Today'),
  week('7 Days'),
  month('30 Days'),
  all('All Time');

  final String label;
  const _TimeWindow(this.label);
}

class _Alert {
  final IconData icon;
  final Color color;
  final String title;
  final String message;
  const _Alert({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });
}

class _DayBucket {
  final String date;
  int total = 0;
  int critical = 0;
  _DayBucket(this.date);
}
