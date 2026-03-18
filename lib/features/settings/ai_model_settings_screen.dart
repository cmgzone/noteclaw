// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import '../../core/audio/elevenlabs_service.dart';
import '../../core/audio/google_tts_service.dart';
import '../../core/audio/google_cloud_tts_service.dart';
import '../../core/audio/voice_service.dart';
import '../../core/audio/voice_models_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/motion.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/audio/murf_service.dart';
import '../../core/ai/ai_models_provider.dart';
import '../admin/services/ai_model_service.dart';

// Providers for selected models
final selectedAIModelProvider = StateProvider<String>((ref) {
  return ''; // Initial empty, will be loaded from prefs or available models
});

final selectedTTSVoiceProvider = StateProvider<String>((ref) {
  return 'EXAVITQu4vr4xnSDxMaL'; // Default Sarah voice (ElevenLabs)
});

final selectedTTSModelProvider = StateProvider<String>((ref) {
  return ElevenLabsService.freeModel; // Default free model
});

final selectedGoogleTTSVoiceProvider = StateProvider<String>((ref) {
  return 'en-US-Standard-A'; // Default Google voice
});

final selectedGoogleCloudTTSVoiceProvider = StateProvider<String>((ref) {
  return 'en-US-Journey-F'; // Default Google Cloud voice
});

final selectedMurfVoiceProvider = StateProvider<String>((ref) {
  return 'en-US-natalie'; // Default Murf voice
});

class AIModelSettingsScreen extends ConsumerStatefulWidget {
  const AIModelSettingsScreen({super.key});

  @override
  ConsumerState<AIModelSettingsScreen> createState() =>
      _AIModelSettingsScreenState();
}

class _AIModelSettingsScreenState extends ConsumerState<AIModelSettingsScreen> {
  String _aiProvider = 'gemini'; // gemini or openrouter
  String _ttsProvider = 'google'; // google or elevenlabs
  String _sttProvider = 'device'; // device or deepgram
  bool _isSavingPersonalModel = false;
  bool _isLoadingPersonalModels = false;
  List<AIModel> _personalModels = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadPersonalModels();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final aiModel = prefs.getString('ai_model');

    // Auto-sync provider based on saved model
    if (aiModel != null && aiModel.isNotEmpty) {
      try {
        final models = await ref.read(availableModelsProvider.future);
        // Find the model's actual provider
        String? detectedProvider;
        for (final entry in models.entries) {
          final found = entry.value.where((m) => m.id == aiModel).firstOrNull;
          if (found != null) {
            detectedProvider = entry.key; // 'gemini' or 'openrouter'
            break;
          }
        }
        if (detectedProvider != null) {
          setState(() => _aiProvider = detectedProvider!);
        } else {
          setState(
              () => _aiProvider = prefs.getString('ai_provider') ?? 'gemini');
        }
      } catch (e) {
        setState(
            () => _aiProvider = prefs.getString('ai_provider') ?? 'gemini');
      }
    } else {
      setState(() => _aiProvider = prefs.getString('ai_provider') ?? 'gemini');
    }

    setState(() {
      _ttsProvider = prefs.getString('tts_provider') ?? 'google';
      _sttProvider = prefs.getString('stt_provider') ?? 'device';
    });

    final ttsVoice = prefs.getString('tts_voice');
    final ttsModel = prefs.getString('tts_model');
    final googleTtsVoice = prefs.getString('google_tts_voice');
    final googleCloudTtsVoice = prefs.getString('google_cloud_tts_voice');
    final murfVoice = prefs.getString('tts_murf_voice');

    if (aiModel != null) {
      ref.read(selectedAIModelProvider.notifier).state = aiModel;
    }
    if (ttsVoice != null) {
      ref.read(selectedTTSVoiceProvider.notifier).state = ttsVoice;
    }
    if (ttsModel != null) {
      ref.read(selectedTTSModelProvider.notifier).state = ttsModel;
    }
    if (googleTtsVoice != null) {
      ref.read(selectedGoogleTTSVoiceProvider.notifier).state = googleTtsVoice;
    }
    if (googleCloudTtsVoice != null) {
      ref.read(selectedGoogleCloudTTSVoiceProvider.notifier).state =
          googleCloudTtsVoice;
    }
    if (murfVoice != null) {
      ref.read(selectedMurfVoiceProvider.notifier).state = murfVoice;
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_provider', _aiProvider);
    await prefs.setString('ai_model', ref.read(selectedAIModelProvider));
    await prefs.setString('tts_provider', _ttsProvider);
    await prefs.setString('stt_provider', _sttProvider);
    await prefs.setString('tts_voice', ref.read(selectedTTSVoiceProvider));
    await prefs.setString('tts_model', ref.read(selectedTTSModelProvider));
    await prefs.setString(
        'google_tts_voice', ref.read(selectedGoogleTTSVoiceProvider));
    await prefs.setString('google_cloud_tts_voice',
        ref.read(selectedGoogleCloudTTSVoiceProvider));
    await prefs.setString(
        'tts_murf_voice', ref.read(selectedMurfVoiceProvider));

    await ref.read(voiceServiceProvider).setSttProvider(
          _sttProvider == 'deepgram' ? SttProvider.deepgram : SttProvider.device,
        );

    await ref.read(voiceServiceProvider).setTtsProvider(
          _ttsProvider == 'google'
              ? TtsProvider.google
              : _ttsProvider == 'google_cloud'
                  ? TtsProvider.googleCloud
                  : _ttsProvider == 'murf'
                      ? TtsProvider.murf
                      : TtsProvider.elevenlabs,
        );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings saved!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _loadPersonalModels() async {
    setState(() => _isLoadingPersonalModels = true);
    try {
      final models = await ref.read(aiModelServiceProvider).listPersonalModels();
      if (!mounted) return;
      setState(() {
        _personalModels = models;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _personalModels = [];
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingPersonalModels = false);
      }
    }
  }

  Future<void> _deletePersonalModel(String id) async {
    await ref.read(aiModelServiceProvider).deletePersonalModel(id);
    ref.invalidate(availableModelsProvider);
    await _loadPersonalModels();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Personal model deleted'),
      ),
    );
  }

  Future<void> _showAddPersonalModelDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final modelIdController = TextEditingController();
    final apiKeyController = TextEditingController();
    final descriptionController = TextEditingController();
    final contextWindowController = TextEditingController(text: '0');
    String provider = 'openrouter';

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Personal AI Model'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Display Name'),
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? 'Name is required'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: modelIdController,
                    decoration: const InputDecoration(labelText: 'Model ID'),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                            ? 'Model ID is required'
                            : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: provider,
                    decoration: const InputDecoration(labelText: 'Provider'),
                    items: const [
                      DropdownMenuItem(
                          value: 'gemini', child: Text('Gemini')),
                      DropdownMenuItem(
                          value: 'openrouter', child: Text('OpenRouter')),
                      DropdownMenuItem(value: 'openai', child: Text('OpenAI')),
                      DropdownMenuItem(
                          value: 'anthropic', child: Text('Anthropic')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => provider = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: apiKeyController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'API Key'),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                            ? 'API key is required'
                            : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: contextWindowController,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Context Window'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: descriptionController,
                    decoration:
                        const InputDecoration(labelText: 'Description (optional)'),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _isSavingPersonalModel
                  ? null
                  : () {
                      Navigator.pop(context);
                    },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: _isSavingPersonalModel
                  ? null
                  : () async {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      setState(() => _isSavingPersonalModel = true);
                      try {
                        await ref.read(aiModelServiceProvider).addPersonalModel(
                              name: nameController.text.trim(),
                              modelId: modelIdController.text.trim(),
                              provider: provider,
                              apiKey: apiKeyController.text.trim(),
                              description: descriptionController.text.trim(),
                              contextWindow:
                                  int.tryParse(contextWindowController.text) ??
                                      0,
                            );
                        ref.invalidate(availableModelsProvider);
                        if (!mounted) return;
                        Navigator.of(this.context).pop();
                        await _loadPersonalModels();
                        if (!mounted) return;
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(
                            content: Text('Personal model added'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          SnackBar(content: Text('Failed to add model: $e')),
                        );
                      } finally {
                        if (mounted) {
                          setState(() => _isSavingPersonalModel = false);
                        }
                      }
                    },
              child: const Text('Add Model'),
            ),
          ],
        ),
      ),
    );
  }

  void _showUpgradeDialog(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.lock_open, size: 48, color: scheme.primary),
        title: const Text('Premium Model'),
        content: const Text(
          'This AI model is only available to paid subscribers.\n\n'
          'Upgrade your plan to unlock access to premium models with enhanced capabilities.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              context.push('/subscription');
            },
            icon: const Icon(Icons.upgrade),
            label: const Text('Upgrade Plan'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedAIModel = ref.watch(selectedAIModelProvider);
    final selectedTTSVoice = ref.watch(selectedTTSVoiceProvider);
    final selectedTTSModel = ref.watch(selectedTTSModelProvider);
    final selectedGoogleTTSVoice = ref.watch(selectedGoogleTTSVoiceProvider);
    final selectedGoogleCloudTTSVoice =
        ref.watch(selectedGoogleCloudTTSVoiceProvider);
    final selectedMurfVoice = ref.watch(selectedMurfVoiceProvider);

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: AppTheme.premiumGradient,
          ),
        ),
        title: const Text('AI Model Settings',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: _saveSettings,
            icon: const Icon(Icons.save),
            tooltip: 'Save Settings',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // AI Provider Section
          _SettingsSection(
            title: 'AI Intelligence',
            children: [
              _SelectionCard(
                title: 'Google Gemini',
                subtitle: 'Fast, powerful, paid API (Gemini 2.5/3.0)',
                isSelected: _aiProvider == 'gemini',
                onTap: () async {
                  setState(() => _aiProvider = 'gemini');
                  // Try to find the first available Gemini model from the provider
                  try {
                    final models =
                        await ref.read(availableModelsProvider.future);
                    final gemini = models['gemini'] ?? [];
                    if (gemini.isNotEmpty) {
                      ref.read(selectedAIModelProvider.notifier).state =
                          gemini.first.id;
                    }
                  } catch (e) {
                    ref.read(selectedAIModelProvider.notifier).state = '';
                  }
                },
                icon: Icons.auto_awesome,
                color: Colors.blue,
              ),
              const SizedBox(height: 12),
              _SelectionCard(
                title: 'OpenRouter',
                subtitle: 'Access Free & Premium Models (Claude, GPT-4)',
                isSelected: _aiProvider == 'openrouter',
                onTap: () async {
                  setState(() => _aiProvider = 'openrouter');
                  final models = await ref.read(availableModelsProvider.future);
                  final openrouter = models['openrouter'] ?? [];
                  if (openrouter.isNotEmpty) {
                    ref.read(selectedAIModelProvider.notifier).state =
                        openrouter.first.id;
                  }
                },
                icon: Icons.model_training,
                color: Colors.purple,
              ),
              if (_aiProvider == 'openrouter') ...[
                const SizedBox(height: 16),
                Consumer(
                  builder: (context, ref, _) {
                    final modelsAsync = ref.watch(availableModelsProvider);

                    return modelsAsync.when(
                      data: (models) {
                        final openRouterModels = models['openrouter'] ?? [];
                        // Check if current selection is valid, else default
                        final current = selectedAIModel;

                        return _DropdownConfiguration(
                          label: 'Selected Model',
                          value: openRouterModels.any((m) => m.id == current)
                              ? current
                              : null,
                          items: openRouterModels.map((m) {
                            final isLocked = m.isPremium && !m.canAccess;
                            return DropdownMenuItem(
                              value: isLocked
                                  ? null
                                  : m.id, // Prevent selection of locked models
                              enabled: !isLocked,
                              child: Row(
                                children: [
                                  if (isLocked) ...[
                                    const Icon(Icons.lock,
                                        size: 14, color: Colors.grey),
                                    const SizedBox(width: 4),
                                  ],
                                  Expanded(
                                    child: Text(
                                      m.name + (m.isPremium ? ' ★' : ''),
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isLocked
                                            ? Colors.grey
                                            : (m.isPremium
                                                ? Colors.amber[800]
                                                : Colors.green),
                                      ),
                                    ),
                                  ),
                                  if (isLocked)
                                    const Text(' (Upgrade)',
                                        style: TextStyle(
                                            fontSize: 10, color: Colors.grey)),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (val) async {
                            if (val != null) {
                              // Check if model is accessible
                              final selected = openRouterModels.firstWhere(
                                (m) => m.id == val,
                                orElse: () => openRouterModels.first,
                              );
                              if (selected.isPremium && !selected.canAccess) {
                                // Show upgrade dialog
                                _showUpgradeDialog(context);
                                return;
                              }
                              ref.read(selectedAIModelProvider.notifier).state =
                                  val;
                              // Auto-save when model changes
                              await _saveSettings();
                            }
                          },
                        );
                      },
                      loading: () => const Center(
                          child: LinearProgressIndicator(minHeight: 2)),
                      error: (_, __) => const Text('Failed to load models'),
                    );
                  },
                ),
              ],
              if (_aiProvider == 'gemini') ...[
                const SizedBox(height: 16),
                Consumer(
                  builder: (context, ref, _) {
                    final modelsAsync = ref.watch(availableModelsProvider);

                    return modelsAsync.when(
                      data: (models) {
                        final geminiModels = models['gemini'] ?? [];
                        final current = selectedAIModel;

                        return _DropdownConfiguration(
                          label: 'Selected Model',
                          value: geminiModels.any((m) => m.id == current)
                              ? current
                              : null,
                          items: geminiModels.map((m) {
                            final isLocked = m.isPremium && !m.canAccess;
                            return DropdownMenuItem(
                              value: isLocked ? null : m.id,
                              enabled: !isLocked,
                              child: Row(
                                children: [
                                  if (isLocked) ...[
                                    const Icon(Icons.lock,
                                        size: 14, color: Colors.grey),
                                    const SizedBox(width: 4),
                                  ],
                                  Expanded(
                                    child: Text(
                                      m.name + (m.isPremium ? ' ★' : ''),
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isLocked
                                            ? Colors.grey
                                            : (m.isPremium
                                                ? Colors.amber[800]
                                                : null),
                                      ),
                                    ),
                                  ),
                                  if (isLocked)
                                    const Text(' (Upgrade)',
                                        style: TextStyle(
                                            fontSize: 10, color: Colors.grey)),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (val) async {
                            if (val != null) {
                              final selected = geminiModels.firstWhere(
                                (m) => m.id == val,
                                orElse: () => geminiModels.first,
                              );
                              if (selected.isPremium && !selected.canAccess) {
                                _showUpgradeDialog(context);
                                return;
                              }
                              ref.read(selectedAIModelProvider.notifier).state =
                                  val;
                              await _saveSettings();
                            }
                          },
                        );
                      },
                      loading: () => const Center(
                          child: LinearProgressIndicator(minHeight: 2)),
                      error: (_, __) => const Text('Failed to load models'),
                    );
                  },
                ),
              ],
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: scheme.outline.withValues(alpha: 0.12)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'My Private Models',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _showAddPersonalModelDialog,
                          icon: const Icon(Icons.add),
                          label: const Text('Add'),
                        ),
                      ],
                    ),
                    if (_isLoadingPersonalModels)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(minHeight: 2),
                      )
                    else if (_personalModels.isEmpty)
                      Text(
                        'No personal models yet',
                        style: TextStyle(
                          color: scheme.onSurface.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                      )
                    else
                      ..._personalModels.map((model) {
                        final isSelected = selectedAIModel == model.modelId;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(
                            model.name,
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: Text(
                            '${model.provider} • ${model.modelId}',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurface.withValues(alpha: 0.6),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                onPressed: () async {
                                  setState(() {
                                    _aiProvider = model.provider == 'gemini'
                                        ? 'gemini'
                                        : 'openrouter';
                                  });
                                  ref
                                      .read(selectedAIModelProvider.notifier)
                                      .state = model.modelId;
                                  await _saveSettings();
                                },
                                child: Text(isSelected ? 'Selected' : 'Use'),
                              ),
                              IconButton(
                                onPressed: () => _deletePersonalModel(model.id),
                                icon: const Icon(Icons.delete_outline, size: 18),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ],
          ).animate().premiumFade().premiumSlide(),

          const SizedBox(height: 32),

          _SettingsSection(
            title: 'Voice Input',
            children: [
              _SelectionCard(
                title: 'Device Speech-to-Text',
                subtitle: 'Free, uses built-in OS recognition',
                isSelected: _sttProvider == 'device',
                onTap: () => setState(() => _sttProvider = 'device'),
                icon: Icons.mic,
                color: Colors.indigo,
              ),
              const SizedBox(height: 12),
              _SelectionCard(
                title: 'Deepgram Speech-to-Text',
                subtitle: 'Fast cloud transcription (requires API key)',
                isSelected: _sttProvider == 'deepgram',
                onTap: () => setState(() => _sttProvider = 'deepgram'),
                icon: Icons.cloud,
                color: Colors.blue,
              ),
            ],
          ).animate().premiumFade(delay: 150.ms).premiumSlide(delay: 150.ms),

          const SizedBox(height: 32),

          // TTS Provider Section
          _SettingsSection(
            title: 'Voice & Speech',
            children: [
              _SelectionCard(
                title: 'Google TTS',
                subtitle: 'Free, native device voices',
                isSelected: _ttsProvider == 'google',
                onTap: () => setState(() => _ttsProvider = 'google'),
                icon: Icons.android,
                color: Colors.green,
              ),
              const SizedBox(height: 12),
              _SelectionCard(
                title: 'ElevenLabs',
                subtitle: 'Premium cloud TTS, ultra-realistic',
                isSelected: _ttsProvider == 'elevenlabs',
                onTap: () => setState(() => _ttsProvider = 'elevenlabs'),
                icon: Icons.graphic_eq,
                color: Colors.orange,
              ),
              const SizedBox(height: 12),
              _SelectionCard(
                title: 'Google Cloud TTS',
                subtitle: 'Premium Journey/Studio voices (Paid)',
                isSelected: _ttsProvider == 'google_cloud',
                onTap: () => setState(() => _ttsProvider = 'google_cloud'),
                icon: Icons.cloud,
                color: Colors.blueGrey,
              ),
              const SizedBox(height: 12),
              _SelectionCard(
                title: 'Murf.ai',
                subtitle: 'Studio quality voices (Gen 2)',
                isSelected: _ttsProvider == 'murf',
                onTap: () => setState(() => _ttsProvider = 'murf'),
                icon: Icons.record_voice_over,
                color: Colors.pinkAccent,
              ),
              const SizedBox(height: 16),
              if (_ttsProvider == 'google')
                Consumer(
                  builder: (context, ref, _) {
                    final voicesAsync = ref.watch(availableVoiceModelsProvider);
                    return voicesAsync.when(
                      data: (voices) {
                        final googleVoices = voices['google'] ?? [];
                        return _DropdownConfiguration(
                          label: 'Voice Selection',
                          value: googleVoices.any(
                                  (v) => v.voiceId == selectedGoogleTTSVoice)
                              ? selectedGoogleTTSVoice
                              : googleVoices.isNotEmpty
                                  ? googleVoices.first.voiceId
                                  : null,
                          items: googleVoices
                              .map((v) => DropdownMenuItem(
                                    value: v.voiceId,
                                    child: Text(
                                        '${v.name}${v.isPremium ? ' (Premium)' : ''}',
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: v.isPremium
                                                ? Colors.amber[800]
                                                : null)),
                                  ))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              ref
                                  .read(selectedGoogleTTSVoiceProvider.notifier)
                                  .state = val;
                            }
                          },
                        );
                      },
                      loading: () =>
                          const LinearProgressIndicator(minHeight: 2),
                      error: (_, __) => _DropdownConfiguration(
                        label: 'Voice Selection',
                        value: selectedGoogleTTSVoice,
                        items: GoogleTtsService.voices.entries
                            .map((e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value,
                                    style: const TextStyle(fontSize: 13))))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            ref
                                .read(selectedGoogleTTSVoiceProvider.notifier)
                                .state = val;
                          }
                        },
                      ),
                    );
                  },
                ),
              if (_ttsProvider == 'elevenlabs') ...[
                Consumer(
                  builder: (context, ref, _) {
                    final voicesAsync = ref.watch(availableVoiceModelsProvider);
                    return voicesAsync.when(
                      data: (voices) {
                        final elevenVoices = voices['elevenlabs'] ?? [];
                        return _DropdownConfiguration(
                          label: 'Voice Selection',
                          value: elevenVoices
                                  .any((v) => v.voiceId == selectedTTSVoice)
                              ? selectedTTSVoice
                              : elevenVoices.isNotEmpty
                                  ? elevenVoices.first.voiceId
                                  : null,
                          items: elevenVoices
                              .map((v) => DropdownMenuItem(
                                    value: v.voiceId,
                                    child: Text('${v.name} (${v.gender})',
                                        style: const TextStyle(fontSize: 13)),
                                  ))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              ref
                                  .read(selectedTTSVoiceProvider.notifier)
                                  .state = val;
                            }
                          },
                        );
                      },
                      loading: () =>
                          const LinearProgressIndicator(minHeight: 2),
                      error: (_, __) => _DropdownConfiguration(
                        label: 'Voice Selection',
                        value: selectedTTSVoice,
                        items: ElevenLabsService.voices.entries
                            .map((e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value,
                                    style: const TextStyle(fontSize: 13))))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            ref.read(selectedTTSVoiceProvider.notifier).state =
                                val;
                          }
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                _DropdownConfiguration(
                  label: 'Model Selection',
                  value: selectedTTSModel,
                  items: ElevenLabsService.models.entries
                      .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value,
                              style: const TextStyle(fontSize: 13))))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      ref.read(selectedTTSModelProvider.notifier).state = val;
                    }
                  },
                ),
              ],
              if (_ttsProvider == 'google_cloud')
                Consumer(
                  builder: (context, ref, _) {
                    final voicesAsync = ref.watch(availableVoiceModelsProvider);
                    return voicesAsync.when(
                      data: (voices) {
                        final cloudVoices = voices['google_cloud'] ?? [];
                        return _DropdownConfiguration(
                          label: 'Voice Selection',
                          value: cloudVoices.any((v) =>
                                  v.voiceId == selectedGoogleCloudTTSVoice)
                              ? selectedGoogleCloudTTSVoice
                              : cloudVoices.isNotEmpty
                                  ? cloudVoices.first.voiceId
                                  : null,
                          items: cloudVoices
                              .map((v) => DropdownMenuItem(
                                    value: v.voiceId,
                                    child: Text(
                                        '${v.name}${v.isPremium ? ' (Premium)' : ''}',
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: v.isPremium
                                                ? Colors.amber[800]
                                                : null)),
                                  ))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              ref
                                  .read(selectedGoogleCloudTTSVoiceProvider
                                      .notifier)
                                  .state = val;
                            }
                          },
                        );
                      },
                      loading: () =>
                          const LinearProgressIndicator(minHeight: 2),
                      error: (_, __) => _DropdownConfiguration(
                        label: 'Voice Selection',
                        value: selectedGoogleCloudTTSVoice,
                        items: GoogleCloudTtsService.voices.entries
                            .map((e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value,
                                    style: const TextStyle(fontSize: 13))))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            ref
                                .read(selectedGoogleCloudTTSVoiceProvider
                                    .notifier)
                                .state = val;
                          }
                        },
                      ),
                    );
                  },
                ),
              if (_ttsProvider == 'murf')
                Consumer(
                  builder: (context, ref, _) {
                    final voicesAsync = ref.watch(availableVoiceModelsProvider);
                    return voicesAsync.when(
                      data: (voices) {
                        final murfVoices = voices['murf'] ?? [];
                        return _DropdownConfiguration(
                          label: 'Voice Selection',
                          value: murfVoices
                                  .any((v) => v.voiceId == selectedMurfVoice)
                              ? selectedMurfVoice
                              : murfVoices.isNotEmpty
                                  ? murfVoices.first.voiceId
                                  : null,
                          items: murfVoices
                              .map((v) => DropdownMenuItem(
                                    value: v.voiceId,
                                    child: Text('${v.name} (${v.gender})',
                                        style: const TextStyle(fontSize: 13)),
                                  ))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              ref
                                  .read(selectedMurfVoiceProvider.notifier)
                                  .state = val;
                            }
                          },
                        );
                      },
                      loading: () =>
                          const LinearProgressIndicator(minHeight: 2),
                      error: (_, __) => _DropdownConfiguration(
                        label: 'Voice Selection',
                        value: selectedMurfVoice,
                        items: MurfService.voices.entries
                            .map((e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value,
                                    style: const TextStyle(fontSize: 13))))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            ref.read(selectedMurfVoiceProvider.notifier).state =
                                val;
                          }
                        },
                      ),
                    );
                  },
                ),
            ],
          ).animate().premiumFade(delay: 200.ms).premiumSlide(delay: 200.ms),

          const SizedBox(height: 32),

          // Tools Section
          _SettingsSection(
            title: 'Tools',
            children: [
              _ActionTile(
                title: 'API Keys',
                subtitle: 'Use your own Gemini/OpenRouter keys (private per user)',
                icon: Icons.vpn_key,
                color: Colors.amber,
                onTap: () => context.push('/settings/api-keys'),
              ),
              _ActionTile(
                title: 'Custom Agents',
                subtitle: 'Create agents and attach skills',
                icon: Icons.smart_toy_outlined,
                color: Colors.teal,
                onTap: () => context.push('/custom-agents'),
              ),
              _ActionTile(
                title: 'Agent Skills',
                subtitle: 'Manage prompt skills and plugins',
                icon: Icons.extension,
                color: Colors.blue,
                onTap: () => context.push('/agent-skills'),
              ),
              _ActionTile(
                title: 'Agent Connections',
                subtitle: 'Connect external coding agents',
                icon: Icons.terminal,
                color: Colors.deepOrange,
                onTap: () => context.push('/agent-connections'),
              ),
              _ActionTile(
                title: 'Migrate Agent ID',
                subtitle: 'Move ElevenLabs Agent ID to database',
                icon: Icons.support_agent,
                color: Colors.indigo,
                onTap: () => context.push('/migrate-agent-id'),
              ),
              _ActionTile(
                title: 'Manage AI Models',
                subtitle: 'Add or configure AI models (Admin)',
                icon: Icons.psychology,
                color: Colors.deepPurple,
                onTap: () => context.push('/admin/ai-models'),
              ),
            ],
          ).animate().premiumFade(delay: 400.ms).premiumSlide(delay: 400.ms),

          const SizedBox(height: 32),

          _SettingsSection(
            title: 'About',
            children: [
              _ActionTile(
                title: 'Subscription & Credits',
                subtitle: 'Manage your credits and subscription plan',
                icon: Icons.credit_card,
                color: Colors.green,
                onTap: () => context.push('/subscription'),
              ),
              _ActionTile(
                title: 'Privacy Policy',
                subtitle: 'View application privacy policy',
                icon: Icons.privacy_tip,
                color: Colors.blueGrey,
                onTap: () => context.push('/privacy-policy'),
              ),
            ],
          ).animate().premiumFade(delay: 500.ms).premiumSlide(delay: 500.ms),

          const SizedBox(height: 32),

          // Info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outline.withValues(alpha: 0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 20,
                        color: scheme.onSurface.withValues(alpha: 0.7)),
                    const SizedBox(width: 8),
                    Text(
                      'Free vs Paid Options',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '• Google TTS: 100% free, native features\n'
                  '• OpenRouter: Includes free models (with limits)\n'
                  '• ElevenLabs: Generous free tier (10k chars/mo)\n'
                  '• Paid options require your own API keys',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.6),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ).animate().premiumFade(delay: 600.ms),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}

class _SelectionCard extends StatelessWidget {
  const _SelectionCard({
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
    required this.icon,
    required this.color,
  });

  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.1)
              : scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : scheme.outline.withValues(alpha: 0.1),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  )
                ]
              : [],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected ? color : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon,
                  size: 24,
                  color: isSelected ? Colors.white : scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isSelected ? color : scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: color)
            else
              Icon(Icons.circle_outlined,
                  color: scheme.outline.withValues(alpha: 0.3)),
          ],
        ),
      ),
    );
  }
}

class _DropdownConfiguration extends StatelessWidget {
  const _DropdownConfiguration({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurface.withValues(alpha: 0.5),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              items: items,
              onChanged: onChanged,
              isExpanded: true,
              style: TextStyle(
                fontSize: 14,
                color: scheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
              icon: Icon(Icons.keyboard_arrow_down,
                  color: scheme.onSurface.withValues(alpha: 0.4)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      tileColor: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.1)),
      ),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      subtitle: Text(subtitle,
          style: TextStyle(
              fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.6))),
      trailing: Icon(Icons.arrow_forward_ios,
          size: 14, color: scheme.onSurface.withValues(alpha: 0.3)),
    );
  }
}
