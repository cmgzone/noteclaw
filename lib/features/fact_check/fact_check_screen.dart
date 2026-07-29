import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../ui/digital_librarian.dart';
import 'fact_check_service.dart';

class FactCheckScreen extends ConsumerStatefulWidget {
  const FactCheckScreen({super.key});

  @override
  ConsumerState<FactCheckScreen> createState() => _FactCheckScreenState();
}

class _FactCheckScreenState extends ConsumerState<FactCheckScreen> {
  final _controller = TextEditingController();
  List<FactCheckResult> _results = const [];
  bool _isChecking = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final content = _controller.text.trim();
    if (content.isEmpty || _isChecking) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isChecking = true;
      _error = null;
      _results = const [];
    });

    try {
      final results =
          await ref.read(factCheckServiceProvider).verifyContent(content);
      if (!mounted) return;
      setState(() => _results = results);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 16,
        title: const NoteClawHeader(
          compact: true,
          eyebrow: 'Fact verification',
        ),
      ),
      bottomNavigationBar: const MemoryToolNavigationBar(
        selected: MemoryToolDestination.factCheck,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Verification Report',
                    style: text.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Verify claims with evidence, confidence, and source-aware explanations.',
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Card(
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _controller,
                            minLines: 7,
                            maxLines: 14,
                            maxLength: 20000,
                            enabled: !_isChecking,
                            decoration: const InputDecoration(
                              hintText:
                                  'Paste an article, statement, or set of claims…',
                              alignLabelWithHint: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              onPressed: _isChecking ? null : _check,
                              icon: _isChecking
                                  ? const SizedBox(
                                      width: 17,
                                      height: 17,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      LucideIcons.badgeCheck,
                                      size: 18,
                                    ),
                              label: Text(
                                _isChecking ? 'Checking…' : 'Check claims',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    _MessageCard(
                      icon: LucideIcons.alertCircle,
                      title: 'Fact check failed',
                      message: _error!,
                      color: scheme.error,
                    ),
                  ],
                  if (!_isChecking &&
                      _error == null &&
                      _results.isEmpty &&
                      _controller.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const _MessageCard(
                      icon: LucideIcons.checkCircle2,
                      title: 'No verifiable claims found',
                      message:
                          'Try a longer passage with specific names, dates, numbers, or events.',
                    ),
                  ],
                  if (_results.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      '${_results.length} claim${_results.length == 1 ? '' : 's'} reviewed',
                      style: text.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._results.map(
                      (result) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _FactResultCard(result: result),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FactResultCard extends StatelessWidget {
  const _FactResultCard({required this.result});

  final FactCheckResult result;

  Color _verdictColor(ColorScheme scheme) {
    switch (result.verdict.toLowerCase()) {
      case 'true':
        return const Color(0xFF15803D);
      case 'false':
        return scheme.error;
      case 'misleading':
        return const Color(0xFFB45309);
      default:
        return scheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final color = _verdictColor(scheme);
    final confidence = (result.confidence.clamp(0, 1) * 100).round();

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    result.verdict.toUpperCase(),
                    style: text.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                Text(
                  '$confidence% confidence',
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              result.claim,
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              result.explanation,
              style: text.bodyMedium?.copyWith(height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.message,
    this.color,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = color ?? scheme.primary;
    return Card(
      elevation: 0,
      child: ListTile(
        leading: Icon(icon, color: accent),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(message),
      ),
    );
  }
}

String _friendlyError(Object error) {
  return error
      .toString()
      .replaceFirst(RegExp(r'^(Exception|Error):\s*'), '')
      .trim();
}
