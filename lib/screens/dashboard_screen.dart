import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/language.dart';
import '../widgets/severity_badge.dart';
import '../theme/app_theme.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        final stats = provider.stats;
        final total = stats['total'] ?? 0;
        final emergency = stats['emergency'] ?? 0;
        final urgent = stats['urgent'] ?? 0;
        final standard = stats['standard'] ?? 0;
        final routine = stats['routine'] ?? 0;

        return Scaffold(
          appBar: AppBar(
            title: const Text('MedLingua'),
            actions: [
              // Language selector
              TextButton.icon(
                onPressed: () => _showLanguagePicker(context, provider),
                icon: const Icon(Icons.language, color: Colors.white),
                label: Text(
                  provider.currentLanguage.code.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // Offline indicator
              Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.wifi_off, size: 14, color: Colors.white70),
                    SizedBox(width: 4),
                    Text(
                      'OFFLINE',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
                  // Welcome card
                  _buildWelcomeCard(context, provider),
                  const SizedBox(height: 20),

                  // Model status
                  _buildModelStatusCard(provider),
                  const SizedBox(height: 20),

                  // Stats overview
                  Text(
                    'Triage Overview',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  _buildStatsGrid(total, emergency, urgent, standard, routine),
                  const SizedBox(height: 20),

                  // Recent encounters
                  Text(
                    'Recent Encounters',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  _buildRecentEncounters(context, provider),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWelcomeCard(BuildContext context, AppProvider provider) {
    return Card(
      color: AppTheme.primaryGreen,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.health_and_safety,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MedLingua',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'AI-Powered Medical Triage',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Powered by Gemma 4 — Running entirely on-device.\nNo internet required. Your data stays private.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelStatusCard(AppProvider provider) {
    final isLoaded = provider.isModelLoaded;
    final isLoading = provider.isModelLoading;

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              isLoaded
                  ? AppTheme.safeGreen.withValues(alpha: 0.1)
                  : AppTheme.warningYellow.withValues(alpha: 0.1),
          child: Icon(
            isLoaded ? Icons.check_circle : Icons.hourglass_top,
            color: isLoaded ? AppTheme.safeGreen : AppTheme.warningYellow,
          ),
        ),
        title: Text(
          isLoaded ? 'Gemma 4 E4B Ready' : 'Loading Model...',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          isLoaded
              ? 'On-device inference active • Medical fine-tune loaded'
              : isLoading
              ? 'Initializing Gemma 4 on-device...'
              : 'Model not loaded',
        ),
        trailing:
            isLoading
                ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                : Icon(
                  isLoaded ? Icons.wifi_off : Icons.error_outline,
                  color: isLoaded ? AppTheme.textMuted : AppTheme.dangerRed,
                  size: 20,
                ),
      ),
    );
  }

  Widget _buildStatsGrid(
    int total,
    int emergency,
    int urgent,
    int standard,
    int routine,
  ) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: [
        _statCard(
          'Total',
          total.toString(),
          Icons.people,
          AppTheme.primaryGreen,
        ),
        _statCard(
          'Emergency',
          emergency.toString(),
          Icons.warning,
          AppTheme.triageEmergency,
        ),
        _statCard(
          'Urgent',
          urgent.toString(),
          Icons.schedule,
          AppTheme.triageUrgent,
        ),
        _statCard(
          'Routine',
          (standard + routine).toString(),
          Icons.check_circle_outline,
          AppTheme.triageRoutine,
        ),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(color: color, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentEncounters(BuildContext context, AppProvider provider) {
    final encounters = provider.encounters.take(5).toList();

    if (encounters.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              children: [
                Icon(
                  Icons.medical_information_outlined,
                  size: 48,
                  color: Colors.grey[300],
                ),
                const SizedBox(height: 12),
                Text(
                  'No triage encounters yet',
                  style: TextStyle(color: Colors.grey[500]),
                ),
                const SizedBox(height: 4),
                Text(
                  'Start a new triage to see results here',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children:
          encounters.map((e) {
            final color = AppTheme.severityColor(e.severity);
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.1),
                  child: Icon(
                    AppTheme.severityIcon(e.severity),
                    color: color,
                    size: 20,
                  ),
                ),
                title: Text(
                  e.patientName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  e.diagnosis,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: SeverityBadge(severity: e.severity),
              ),
            );
          }).toList(),
    );
  }

  void _showLanguagePicker(BuildContext context, AppProvider provider) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select Language',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'MedLingua will respond in your chosen language',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  children:
                      SupportedLanguages.all.map((lang) {
                        final isSelected =
                            provider.currentLanguage.code == lang.code;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                isSelected
                                    ? AppTheme.primaryGreen
                                    : Colors.grey[100],
                            child: Text(
                              lang.code.toUpperCase(),
                              style: TextStyle(
                                color:
                                    isSelected
                                        ? Colors.white
                                        : Colors.grey[600],
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          title: Text(lang.nativeName),
                          subtitle: Text(lang.name),
                          trailing:
                              isSelected
                                  ? const Icon(
                                    Icons.check,
                                    color: AppTheme.primaryGreen,
                                  )
                                  : null,
                          onTap: () {
                            provider.setLanguage(lang);
                            Navigator.pop(context);
                          },
                        );
                      }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
