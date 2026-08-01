import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/ai/ai_models_provider.dart';
import '../core/ai/ai_settings_service.dart';

/// Compact AI model selector that appears on every page
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
      data: (models) {
        // Combine all models
        final allModels = [
          ...models['gemini'] ?? [],
          ...models['openrouter'] ?? [],
          ...models['alibaba_token_plan'] ?? [],
        ];

        if (allModels.isEmpty) {
          return const SizedBox.shrink();
        }

        // Find the selected model to display its name
        AIModelOption? currentModel;
        for (final m in allModels) {
          if (m.id == selectedModel) {
            currentModel = m;
            break;
          }
        }
        final displayName = currentModel?.name ?? 'Select Model';

        return Container(
          width: compact ? 60 : 200, // Give it a base width
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
              width: 1,
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
                          Flexible(
                            child: Text(
                              displayName,
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurface,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      )
                    : DropdownButton<String>(
                        isExpanded: true,
                        value: allModels.any((m) => m.id == selectedModel)
                            ? selectedModel
                            : null,
                        hint: compact
                            ? Icon(Icons.auto_awesome,
                                size: 20, color: scheme.primary)
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.auto_awesome,
                                      size: 16, color: scheme.primary),
                                  const SizedBox(width: 6),
                                  Text(
                                    displayName,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onSurface,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
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
                          // Gemini models
                          if (models['gemini']?.isNotEmpty == true) ...[
                            DropdownMenuItem<String>(
                              enabled: false,
                              value: '__gemini_header__',
                              child: Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Text(
                                  'GEMINI',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: scheme.primary,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                            ),
                            ...models['gemini']!.map((m) {
                              return DropdownMenuItem<String>(
                                value: m.id,
                                child: Row(
                                  children: [
                                    const Icon(Icons.auto_awesome,
                                        size: 14, color: Colors.blue),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        m.name,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: scheme.onSurface),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                          // OpenRouter models
                          if (models['openrouter']?.isNotEmpty == true) ...[
                            DropdownMenuItem<String>(
                              enabled: false,
                              value: '__openrouter_header__',
                              child: Padding(
                                padding: const EdgeInsets.only(left: 8, top: 8),
                                child: Text(
                                  'OPENROUTER',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: scheme.primary,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                            ),
                            ...models['openrouter']!.map((m) {
                              return DropdownMenuItem<String>(
                                value: m.id,
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.model_training,
                                      size: 14,
                                      color: m.isPremium
                                          ? Colors.amber[700]
                                          : Colors.green,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        m.name + (m.isPremium ? ' 💎' : ''),
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: scheme.onSurface),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                          // Alibaba Model Studio Token Plan models
                          if (models['alibaba_token_plan']?.isNotEmpty ==
                              true) ...[
                            DropdownMenuItem<String>(
                              enabled: false,
                              value: '__alibaba_token_plan_header__',
                              child: Padding(
                                padding: const EdgeInsets.only(left: 8, top: 8),
                                child: Text(
                                  'ALIBABA TOKEN PLAN',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: scheme.primary,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                            ),
                            ...models['alibaba_token_plan']!.map((m) {
                              return DropdownMenuItem<String>(
                                value: m.id,
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.cloud_outlined,
                                      size: 14,
                                      color: Colors.orange,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        m.name,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: scheme.onSurface),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ],
                        onChanged: (val) async {
                          if (val != null && !val.startsWith('__')) {
                            AIModelOption? model;
                            for (final m in allModels) {
                              if (m.id == val) {
                                model = m;
                                break;
                              }
                            }
                            if (model != null) {
                              ref.read(selectedAIModelProvider.notifier).state =
                                  val;
                              await AISettingsService.setModel(val);

                              final provider = model.provider;
                              String mappedProvider = provider;
                              if (provider == 'openai' ||
                                  provider == 'anthropic') {
                                mappedProvider = 'openrouter';
                              }
                              await AISettingsService.setProvider(
                                  mappedProvider);

                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content:
                                        Text('✓ Switched to ${model.name}'),
                                    duration: const Duration(seconds: 2),
                                    behavior: SnackBarBehavior.floating,
                                    backgroundColor: scheme.primary,
                                  ),
                                );
                              }
                            }
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
                    collapsed ? Icons.expand_more : Icons.expand_less,
                    size: 18,
                    color: scheme.primary,
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const SizedBox(
          width: 100,
          height: 24,
          child: Center(
            child: SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
