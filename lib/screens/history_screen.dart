import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import '../models/triage_encounter.dart';
import '../utils/date_utils.dart' as app_dates;
import 'result_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  TriageSeverity? _severityFilter;
  _DateRange _dateFilter = _DateRange.all;

  List<TriageEncounter> _applyFilters(List<TriageEncounter> encounters) {
    var filtered = encounters;

    if (_severityFilter != null) {
      filtered = filtered.where((e) => e.severity == _severityFilter).toList();
    }

    final now = DateTime.now();
    switch (_dateFilter) {
      case _DateRange.today:
        filtered =
            filtered
                .where(
                  (e) =>
                      e.timestamp.year == now.year &&
                      e.timestamp.month == now.month &&
                      e.timestamp.day == now.day,
                )
                .toList();
        break;
      case _DateRange.week:
        final weekAgo = now.subtract(const Duration(days: 7));
        filtered = filtered.where((e) => e.timestamp.isAfter(weekAgo)).toList();
        break;
      case _DateRange.month:
        final monthAgo = now.subtract(const Duration(days: 30));
        filtered =
            filtered.where((e) => e.timestamp.isAfter(monthAgo)).toList();
        break;
      case _DateRange.all:
        break;
    }

    return filtered;
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Filters',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setSheetState(() {
                            _severityFilter = null;
                            _dateFilter = _DateRange.all;
                          });
                          setState(() {});
                        },
                        child: const Text('Clear All'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Severity filter
                  const Text(
                    'Severity',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      _filterChip(
                        label: 'All',
                        selected: _severityFilter == null,
                        color: AppTheme.primaryGreen,
                        onSelected: () {
                          setSheetState(() => _severityFilter = null);
                          setState(() {});
                        },
                      ),
                      ...TriageSeverity.values.map(
                        (s) => _filterChip(
                          label: s.label,
                          selected: _severityFilter == s,
                          color: _getSeverityColor(s),
                          onSelected: () {
                            setSheetState(() => _severityFilter = s);
                            setState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Date filter
                  const Text(
                    'Time Range',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children:
                        _DateRange.values
                            .map(
                              (d) => _filterChip(
                                label: d.label,
                                selected: _dateFilter == d,
                                color: AppTheme.primaryGreen,
                                onSelected: () {
                                  setSheetState(() => _dateFilter = d);
                                  setState(() {});
                                },
                              ),
                            )
                            .toList(),
                  ),
                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Apply'),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onSelected,
  }) {
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : color,
        ),
      ),
      selected: selected,
      selectedColor: color,
      backgroundColor: color.withValues(alpha: 0.1),
      onSelected: (_) => onSelected(),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        final allEncounters = provider.encounters;
        final encounters = _applyFilters(allEncounters);
        final hasActiveFilter =
            _severityFilter != null || _dateFilter != _DateRange.all;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Encounter History'),
            actions: [
              if (allEncounters.isNotEmpty)
                Stack(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.filter_list),
                      onPressed: _showFilterSheet,
                    ),
                    if (hasActiveFilter)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppTheme.accentOrange,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
          body: Column(
            children: [
              // Active filter bar
              if (hasActiveFilter)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  color: AppTheme.primaryGreen.withValues(alpha: 0.05),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.filter_alt,
                        size: 16,
                        color: AppTheme.primaryGreen,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Showing ${encounters.length} of ${allEncounters.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (_severityFilter != null) ...[
                        const SizedBox(width: 8),
                        Chip(
                          label: Text(
                            _severityFilter!.label,
                            style: const TextStyle(fontSize: 10),
                          ),
                          deleteIcon: const Icon(Icons.close, size: 14),
                          onDeleted:
                              () => setState(() => _severityFilter = null),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          backgroundColor: _getSeverityColor(
                            _severityFilter!,
                          ).withValues(alpha: 0.1),
                        ),
                      ],
                      if (_dateFilter != _DateRange.all) ...[
                        const SizedBox(width: 8),
                        Chip(
                          label: Text(
                            _dateFilter.label,
                            style: const TextStyle(fontSize: 10),
                          ),
                          deleteIcon: const Icon(Icons.close, size: 14),
                          onDeleted:
                              () =>
                                  setState(() => _dateFilter = _DateRange.all),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ],
                  ),
                ),
              // List
              Expanded(
                child:
                    encounters.isEmpty
                        ? _buildEmptyState(hasActiveFilter)
                        : _buildEncounterList(context, encounters),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(bool hasFilter) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasFilter ? Icons.filter_alt_off : Icons.history,
            size: 64,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            hasFilter ? 'No matching encounters' : 'No encounters recorded yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasFilter
                ? 'Try adjusting your filters'
                : 'Completed triage assessments will appear here',
            style: TextStyle(fontSize: 14, color: Colors.grey[400]),
          ),
          if (hasFilter) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed:
                  () => setState(() {
                    _severityFilter = null;
                    _dateFilter = _DateRange.all;
                  }),
              icon: const Icon(Icons.clear_all),
              label: const Text('Clear Filters'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEncounterList(
    BuildContext context,
    List<TriageEncounter> encounters,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: encounters.length,
      itemBuilder: (context, index) {
        final e = encounters[index];
        final severityColor = AppTheme.severityColor(e.severity);

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              _showEncounterDetail(context, e);
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  // Severity indicator
                  Container(
                    width: 4,
                    height: 60,
                    decoration: BoxDecoration(
                      color: severityColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              e.patientName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: severityColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                e.severity.label,
                                style: TextStyle(
                                  color: severityColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          e.diagnosis,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 12,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              app_dates.formatDateTime(e.timestamp),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[400],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(
                              Icons.language,
                              size: 12,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              e.inputLanguage.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[400],
                              ),
                            ),
                            if (e.isOffline) ...[
                              const SizedBox(width: 12),
                              Icon(
                                Icons.wifi_off,
                                size: 12,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Offline',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[400],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right, color: AppTheme.textMuted),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showEncounterDetail(BuildContext context, TriageEncounter encounter) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ResultScreen(encounter: encounter)),
    );
  }

  Color _getSeverityColor(TriageSeverity severity) =>
      AppTheme.severityColor(severity);
}

enum _DateRange {
  all('All Time'),
  today('Today'),
  week('This Week'),
  month('This Month');

  final String label;
  const _DateRange(this.label);
}
