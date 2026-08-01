import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ai/ai_models_provider.dart';
import '../core/ai/ai_settings_service.dart';

/// Compact AI model selector that appears on every page.
final modelSelectorCollapsedProvider = StateProvider<bool>((ref) => false);

class QuickAIModelSelector extends ConsumerWidget {
  final bool compact;

  const QuickAIModelSelector({super.key, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final selectedModel = ref.watch(selectedAIModelProvider);
    final modelsAsync = ref.watch(availableModelsProvider);
    final collapsed = ref.watch(modelSelectorCollapsedProvider);

    return modelsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (models) {
        final allModels = models.values.expand((items) => items).toList();
        if (allModels.isEmpty) return const SizedBox.shrink();

        final currentModel =
            allModels.where((model) => model.id == selectedModel).firstOrNull;
        final displayName = currentModel?.name ?? 'Select Model';

        return Container(
          width: compact ? 60 : 200,
          constraints: const BoxConstraints(maxWidth: 300),
          margin: compact
              ? const EdgeInsets.symmetric(vertical: 4)
              : const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          padding: compact
              ? const EdgeInsets.all(8)
              : const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: scheme.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: collapsed
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome,
                              size: compact ? 20 : 16, color: scheme.primary),
                          if (!compact) const SizedBox(width: 6),
                          if (!compact)
                            Flexible(
                              child: Text(
                                displayName,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      )
                    : DropdownButton<String>(
                        isExpanded: true,
                        value:
                            allModels.any((model) => model.id == selectedModel)
                                ? selectedModel
                                : null,
                        hint: Text(
                          displayName,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        underline: const SizedBox.shrink(),
                        isDense: true,
                        icon: compact
                            ? const SizedBox.shrink()
                            : Icon(Icons.arrow_drop_down,
                                size: 18, color: scheme.primary),
                        dropdownColor: scheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(12),
                        items: [
                          for (final entry in models.entries)
                            if (entry.value.isNotEmpty) ...[
                              DropdownMenuItem<String>(
                                enabled: false,
                                value: '__${entry.key}_header__',
                                child: Text(
                                  formatAIProviderName(entry.key).toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: scheme.primary,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                              ...entry.value.map(
                                (model) => DropdownMenuItem<String>(
                                  value: model.id,
                                  enabled: model.canAccess,
                                  child: Row(
                                    children: [
                                      Icon(
                                        entry.key == 'gemini'
                                            ? Icons.auto_awesome
                                            : Icons.model_training,
                                        size: 14,
                                        color: model.isPremium
                                            ? Colors.amber
                                            : scheme.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          model.name,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: model.canAccess
                                                ? scheme.onSurface
                                                : scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                      if (model.isPremium)
                                        const Icon(Icons.workspace_premium,
                                            size: 13, color: Colors.amber),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                        ],
                        onChanged: (modelId) async {
                          if (modelId == null || modelId.startsWith('__')) {
                            return;
                          }
                          final model = allModels
                              .where((item) => item.id == modelId)
                              .firstOrNull;
                          if (model == null) return;

                          ref.read(selectedAIModelProvider.notifier).state =
                              model.id;
                          await AISettingsService.setModel(model.id);
                          final provider = model.provider == 'openai' ||
                                  model.provider == 'anthropic'
                              ? 'openrouter'
                              : model.provider;
                          await AISettingsService.setProvider(provider);

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Switched to ${model.name}'),
                                duration: const Duration(seconds: 2),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                      ),
              ),
              const SizedBox(width: 4),
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  final notifier =
                      ref.read(modelSelectorCollapsedProvider.notifier);
                  notifier.state = !collapsed;
                },
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    collapsed ? Icons.chevron_right : Icons.chevron_left,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
