import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/language.dart';
import '../services/model_manager.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _tokenController = TextEditingController();

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        final mm = provider.modelManager;
        final modelReady = provider.modelFileAvailable && !provider.isUsingDemoMode;

        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Language Settings
              _sectionHeader(context, 'Language'),
              Card(
                child: Column(
                  children: SupportedLanguages.all.map((lang) {
                    final isSelected =
                        provider.currentLanguage.code == lang.code;
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: isSelected
                            ? AppTheme.primaryGreen
                            : Colors.grey[100],
                        child: Text(
                          lang.code.toUpperCase(),
                          style: TextStyle(
                            color:
                                isSelected ? Colors.white : Colors.grey[600],
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      title: Text(lang.nativeName),
                      subtitle: Text(lang.name,
                          style: const TextStyle(fontSize: 12)),
                      trailing: isSelected
                          ? const Icon(Icons.check,
                              color: AppTheme.primaryGreen)
                          : null,
                      onTap: () => provider.setLanguage(lang),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 20),

              // Model Settings
              _sectionHeader(context, 'AI Model'),
              Card(
                child: Column(
                  children: [
                    // Model status tile
                    ListTile(
                      leading: const Icon(Icons.memory,
                          color: AppTheme.primaryGreen),
                      title: Text(mm.activeModel.displayName),
                      subtitle: Text(
                        modelReady
                            ? 'Loaded • On-device inference active'
                            : provider.isUsingDemoMode
                                ? 'Demo mode • Download model for real inference'
                                : 'Not loaded',
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: modelReady
                              ? AppTheme.safeGreen.withValues(alpha: 0.1)
                              : provider.isUsingDemoMode
                                  ? Colors.orange.withValues(alpha: 0.1)
                                  : AppTheme.dangerRed.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          modelReady
                              ? 'ACTIVE'
                              : provider.isUsingDemoMode
                                  ? 'DEMO'
                                  : 'OFFLINE',
                          style: TextStyle(
                            color: modelReady
                                ? AppTheme.safeGreen
                                : provider.isUsingDemoMode
                                    ? Colors.orange
                                    : AppTheme.dangerRed,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                    // Download progress or download button
                    if (provider.isDownloadingModel)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LinearProgressIndicator(
                              value: provider.downloadProgress,
                              backgroundColor: Colors.grey[200],
                              color: AppTheme.primaryGreen,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Downloading... ${(provider.downloadProgress * 100).toStringAsFixed(1)}%',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      )
                    else if (!provider.modelFileAvailable) ...[
                      if (provider.downloadError != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          child: Text(
                            provider.downloadError!,
                            style: TextStyle(
                              color: AppTheme.dangerRed,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ListTile(
                        leading: const Icon(Icons.download,
                            color: AppTheme.primaryGreen),
                        title: const Text('Download Model'),
                        subtitle: Text(
                          '${mm.activeModelSizeLabel} • Requires Wi-Fi',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () => _showDownloadDialog(context, provider),
                      ),
                    ],

                    // Model variant selector
                    ListTile(
                      leading: const Icon(Icons.swap_horiz,
                          color: AppTheme.primaryGreen),
                      title: const Text('Model Variant'),
                      subtitle: Text(mm.activeModel.displayName),
                      trailing: DropdownButton<String>(
                        value: mm.activeVariant,
                        underline: const SizedBox.shrink(),
                        items: ModelManager.models.entries
                            .map((e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(e.value.displayName,
                                      style: const TextStyle(fontSize: 13)),
                                ))
                            .toList(),
                        onChanged: provider.isDownloadingModel
                            ? null
                            : (variant) {
                                if (variant != null) {
                                  provider.switchModelVariant(variant);
                                }
                              },
                      ),
                    ),

                    const ListTile(
                      leading:
                          Icon(Icons.tune, color: AppTheme.primaryGreen),
                      title: Text('Fine-tuning'),
                      subtitle: Text(
                          'Medical QA + WHO IMCI protocols (via Unsloth)'),
                    ),
                    const ListTile(
                      leading: Icon(Icons.route,
                          color: AppTheme.primaryGreen),
                      title: Text('Task Routing'),
                      subtitle: Text(
                          'Cactus: E2B for simple queries, E4B for complex'),
                    ),

                    // ADB push instructions
                    if (!provider.modelFileAvailable)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.blue.withValues(alpha: 0.2),
                            ),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Developer: Push model via ADB',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                './scripts/download_model.sh',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // About
              _sectionHeader(context, 'About'),
              Card(
                child: Column(
                  children: [
                    const ListTile(
                      leading: Icon(Icons.info_outline,
                          color: AppTheme.primaryGreen),
                      title: Text('MedLingua v1.0.0'),
                      subtitle: Text(
                          'Offline Medical Triage for Community Health Workers'),
                    ),
                    const ListTile(
                      leading: Icon(Icons.shield_outlined,
                          color: AppTheme.primaryGreen),
                      title: Text('Privacy'),
                      subtitle: Text(
                          'All data stays on-device. No cloud processing.'),
                    ),
                    const ListTile(
                      leading: Icon(Icons.school_outlined,
                          color: AppTheme.primaryGreen),
                      title: Text('Built for'),
                      subtitle: Text('Gemma 4 Good Hackathon 2026'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.code,
                          color: AppTheme.primaryGreen),
                      title: const Text('Tech Stack'),
                      subtitle: const Text(
                          'Flutter + Gemma 4 + MediaPipe + Cactus + Unsloth'),
                      onTap: () {},
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  void _showDownloadDialog(BuildContext context, AppProvider provider) {
    final needsToken = provider.modelManager.activeModel.requiresLicense;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Download AI Model'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Download ${provider.modelManager.activeModel.displayName} '
              '(${provider.modelManager.activeModelSizeLabel})?',
            ),
            const SizedBox(height: 8),
            const Text(
              'This requires a stable internet connection and may take several minutes.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            if (needsToken) ...[
              const SizedBox(height: 16),
              const Text(
                'This model requires a HuggingFace token:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _tokenController,
                decoration: const InputDecoration(
                  hintText: 'hf_...',
                  labelText: 'HuggingFace Token',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                obscureText: true,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              provider.downloadModel(
                hfToken: needsToken ? _tokenController.text : null,
              );
            },
            child: const Text('Download'),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge,
      ),
    );
  }
}
