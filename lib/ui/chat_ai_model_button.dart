import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ai/ai_models_provider.dart';
import '../core/ai/ai_settings_service.dart';

AIModelOption? findAIModelOption(
  Map<String, List<AIModelOption>> models,
  String? modelId,
) {
  final normalizedId = (modelId ?? '').trim();
  if (normalizedId.isEmpty) return null;

  for (final providerModels in models.values) {
    for (final model in providerModels) {
      if (model.id == normalizedId) {
        return model;
      }
    }
  }

  return null;
}

String currentAIModelDisplayName(
  Map<String, List<AIModelOption>> models,
  String? modelId,
) {
  final model = findAIModelOption(models, modelId);
  if (model != null) {
    return model.name;
  }

  final normalizedId = (modelId ?? '').trim();
  if (normalizedId.isNotEmpty) {
    return normalizedId;
  }

  return 'Select AI model';
}

class ChatAIModelButton extends ConsumerWidget {
  const ChatAIModelButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final models = ref.watch(availableModelsProvider).valueOrNull ??
        const <String, List<AIModelOption>>{};
    final aiSettings = ref.watch(aiSettingsProvider).valueOrNull;
    final currentModelId = aiSettings?.model;
    final currentModelName = currentAIModelDisplayName(models, currentModelId);
    final hasSelection = (currentModelId ?? '').trim().isNotEmpty;
    final geminiModels = models['gemini'] ?? const <AIModelOption>[];
    final openRouterModels = models['openrouter'] ?? const <AIModelOption>[];

    return PopupMenuButton<String>(
      tooltip: hasSelection ? 'AI model: $currentModelName' : 'Select AI model',
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      enabled: geminiModels.isNotEmpty || openRouterModels.isNotEmpty,
      onSelected: (modelId) async {
        final selectedModel = findAIModelOption(models, modelId);
        if (selectedModel == null) return;

        var mappedProvider = selectedModel.provider;
        if (mappedProvider == 'openai' || mappedProvider == 'anthropic') {
          mappedProvider = 'openrouter';
        }

        await AISettingsService.setModel(selectedModel.id);
        await AISettingsService.setProvider(mappedProvider);

        ref.read(selectedAIModelProvider.notifier).state = selectedModel.id;
        ref.invalidate(currentAIModelIdProvider);
        ref.invalidate(aiSettingsProvider);

        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AI model switched to ${selectedModel.name}'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      itemBuilder: (context) {
        final items = <PopupMenuEntry<String>>[];

        void addSection(String title, List<AIModelOption> sectionModels) {
          if (sectionModels.isEmpty) return;
          if (items.isNotEmpty) {
            items.add(const PopupMenuDivider());
          }
          items.add(
            PopupMenuItem<String>(
              enabled: false,
              height: 32,
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: scheme.primary,
                ),
              ),
            ),
          );
          for (final model in sectionModels) {
            items.add(
              PopupMenuItem<String>(
                value: model.id,
                enabled: model.canAccess,
                child: _AIModelMenuItem(
                  model: model,
                  selected: model.id == currentModelId,
                ),
              ),
            );
          }
        }

        addSection('GEMINI', geminiModels);
        addSection('OPENROUTER', openRouterModels);
        return items;
      },
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: scheme.primary.withValues(alpha: 0.18),
              ),
            ),
            child: Icon(
              Icons.auto_awesome_rounded,
              color: scheme.primary,
              size: 20,
            ),
          ),
          if (hasSelection)
            Positioned(
              right: -1,
              top: -1,
              child: Container(
                height: 10,
                width: 10,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: scheme.surface,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AIModelMenuItem extends StatelessWidget {
  const _AIModelMenuItem({
    required this.model,
    required this.selected,
  });

  final AIModelOption model;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final leadingColor = model.canAccess
        ? (model.isPremium ? Colors.amber.shade700 : scheme.primary)
        : scheme.outline;

    return Row(
      children: [
        Icon(
          model.canAccess ? Icons.auto_awesome_rounded : Icons.lock_outline,
          size: 18,
          color: leadingColor,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            model.name,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: model.canAccess
                  ? scheme.onSurface
                  : scheme.onSurface.withValues(alpha: 0.45),
            ),
          ),
        ),
        if (model.isPremium)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Icon(
              Icons.workspace_premium_rounded,
              size: 16,
              color: Colors.amber.shade700,
            ),
          ),
        if (selected)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Icon(
              Icons.check_rounded,
              size: 18,
              color: scheme.primary,
            ),
          ),
      ],
    );
  }
}
