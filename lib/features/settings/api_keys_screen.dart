import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/credentials_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/motion.dart';

class ApiKeysScreen extends ConsumerStatefulWidget {
  const ApiKeysScreen({super.key});

  @override
  ConsumerState<ApiKeysScreen> createState() => _ApiKeysScreenState();
}

class _ApiKeysScreenState extends ConsumerState<ApiKeysScreen> {
  final _geminiController = TextEditingController();
  final _openRouterController = TextEditingController();

  bool _loading = false;
  bool _hasGeminiKey = false;
  bool _hasOpenRouterKey = false;

  bool _showGemini = false;
  bool _showOpenRouter = false;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  @override
  void dispose() {
    _geminiController.dispose();
    _openRouterController.dispose();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    setState(() => _loading = true);
    try {
      final creds = ref.read(credentialsServiceProvider);
      final gemini = await creds.getApiKey('gemini');
      final openrouter = await creds.getApiKey('openrouter');
      if (!mounted) return;
      setState(() {
        _hasGeminiKey = (gemini ?? '').trim().isNotEmpty;
        _hasOpenRouterKey = (openrouter ?? '').trim().isNotEmpty;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveKey(String service, String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;

    setState(() => _loading = true);
    try {
      final creds = ref.read(credentialsServiceProvider);
      await creds.storeApiKey(service: service, apiKey: trimmed);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${service.toUpperCase()} key saved locally'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save key: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
      await _refreshStatus();
    }
  }

  Future<void> _deleteKey(String service) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete API key?'),
        content: Text('Remove the saved key for "$service" from this device?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _loading = true);
    try {
      final creds = ref.read(credentialsServiceProvider);
      await creds.deleteApiKey(service);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${service.toUpperCase()} key deleted'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete key: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
      await _refreshStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('API Keys'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.premiumGradient),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshStatus,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _InfoCard(loading: _loading).animate().premiumFade().premiumSlide(),
            const SizedBox(height: 16),
            _KeyCard(
              title: 'Google Gemini',
              service: 'gemini',
              controller: _geminiController,
              hasKey: _hasGeminiKey,
              showValue: _showGemini,
              onToggleShow: () => setState(() => _showGemini = !_showGemini),
              onSave: _loading
                  ? null
                  : () => _saveKey('gemini', _geminiController.text),
              onDelete: _loading ? null : () => _deleteKey('gemini'),
            ).animate().premiumFade(delay: 120.ms).premiumSlide(delay: 120.ms),
            const SizedBox(height: 12),
            _KeyCard(
              title: 'OpenRouter',
              service: 'openrouter',
              controller: _openRouterController,
              hasKey: _hasOpenRouterKey,
              showValue: _showOpenRouter,
              onToggleShow: () =>
                  setState(() => _showOpenRouter = !_showOpenRouter),
              onSave: _loading
                  ? null
                  : () => _saveKey('openrouter', _openRouterController.text),
              onDelete: _loading ? null : () => _deleteKey('openrouter'),
            ).animate().premiumFade(delay: 200.ms).premiumSlide(delay: 200.ms),
            const SizedBox(height: 24),
            Text(
              'Tip: If you save a key here, the app will automatically use it for AI calls and your provider will bill you directly.',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurface.withValues(alpha: 0.6),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.loading});
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline,
              size: 20, color: scheme.onSurface.withValues(alpha: 0.7)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stored locally (encrypted)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurface.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Keys are encrypted and saved per signed-in user on this device. Other users on the same device cannot use your saved keys.',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.65),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.sync,
                        size: 16,
                        color: scheme.onSurface.withValues(alpha: 0.6)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        loading ? 'Checking saved keys...' : 'Pull to refresh',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyCard extends StatelessWidget {
  const _KeyCard({
    required this.title,
    required this.service,
    required this.controller,
    required this.hasKey,
    required this.showValue,
    required this.onToggleShow,
    required this.onSave,
    required this.onDelete,
  });

  final String title;
  final String service;
  final TextEditingController controller;
  final bool hasKey;
  final bool showValue;
  final VoidCallback onToggleShow;
  final VoidCallback? onSave;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurface.withValues(alpha: 0.9),
                  ),
                ),
              ),
              _StatusPill(hasKey: hasKey),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            obscureText: !showValue,
            decoration: InputDecoration(
              labelText: '$service API key',
              hintText: 'Paste your key',
              prefixIcon: const Icon(Icons.key),
              suffixIcon: IconButton(
                tooltip: showValue ? 'Hide' : 'Show',
                onPressed: onToggleShow,
                icon: Icon(showValue ? Icons.visibility_off : Icons.visibility),
              ),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onSave,
                  icon: const Icon(Icons.save),
                  label: const Text('Save'),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: hasKey ? onDelete : null,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: BorderSide(color: Colors.red.withValues(alpha: 0.5)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.hasKey});
  final bool hasKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = hasKey ? scheme.tertiaryContainer : scheme.surfaceContainerHighest;
    final fg =
        hasKey ? scheme.onTertiaryContainer : scheme.onSurface.withValues(alpha: 0.7);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.12)),
      ),
      child: Text(
        hasKey ? 'Saved' : 'Not set',
        style: TextStyle(fontSize: 12, color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}
