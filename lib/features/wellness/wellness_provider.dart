import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ai/deep_research_service.dart';
import '../../core/ai/ai_settings_service.dart';
import '../../core/api/api_service.dart';
import '../../core/audio/voice_service.dart';

class WellnessState {
  final List<WellnessMessage> messages;
  final bool isTyping;
  final bool isResearching;
  final bool isListening;
  final String? researchStatus;
  final double researchProgress;
  final String? error;
  final String currentSpeechText;

  const WellnessState({
    this.messages = const [],
    this.isTyping = false,
    this.isResearching = false,
    this.isListening = false,
    this.researchStatus,
    this.researchProgress = 0.0,
    this.error,
    this.currentSpeechText = '',
  });

  WellnessState copyWith({
    List<WellnessMessage>? messages,
    bool? isTyping,
    bool? isResearching,
    bool? isListening,
    String? researchStatus,
    double? researchProgress,
    String? error,
    String? currentSpeechText,
  }) {
    return WellnessState(
      messages: messages ?? this.messages,
      isTyping: isTyping ?? this.isTyping,
      isResearching: isResearching ?? this.isResearching,
      isListening: isListening ?? this.isListening,
      researchStatus: researchStatus ?? this.researchStatus,
      researchProgress: researchProgress ?? this.researchProgress,
      error: error,
      currentSpeechText: currentSpeechText ?? this.currentSpeechText,
    );
  }
}

class WellnessMessage {
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final bool isResearchResult;

  WellnessMessage({
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.isResearchResult = false,
  });
}

class WellnessNotifier extends StateNotifier<WellnessState> {
  final Ref ref;
  bool _shouldSpeakResponse = false;

  WellnessNotifier(this.ref) : super(const WellnessState());

  Future<void> sendEmotionalSupportMessage(String message,
      {bool triggeredByVoice = false}) async {
    _addUserMessage(message);
    state = state.copyWith(isTyping: true, error: null);
    _shouldSpeakResponse = triggeredByVoice;

    try {
      final response = await _getAIResponse(message, isMedical: false);
      _addAIMessage(response);

      if (_shouldSpeakResponse) {
        await ref.read(voiceServiceProvider).speak(response);
      }
    } catch (e) {
      state = state.copyWith(isTyping: false, error: e.toString());
    }
  }

  Future<void> startMedicalResearch(String query,
      {bool triggeredByVoice = false}) async {
    _addUserMessage("Research medical info about: $query");
    state = state.copyWith(
        isResearching: true,
        researchStatus: "Initiating research...",
        researchProgress: 0.0,
        error: null);
    _shouldSpeakResponse = triggeredByVoice;

    try {
      final deepResearchService = ref.read(deepResearchServiceProvider);

      // Listen to the stream
      await for (final update in deepResearchService.research(
        query: query,
        notebookId: '',
        owner: 'wellness',
      )) {
        state = state.copyWith(
          researchStatus: update.status,
          researchProgress: update.progress,
        );

        if (update.progress >= 1.0 && update.result != null) {
          _addAIMessage(update.result!, isResearchResult: true);

          if (_shouldSpeakResponse) {
            // Summarize for speech because full reports are too long
            final summary =
                "I've completed the research on $query. The report is ready for you to read.";
            await ref.read(voiceServiceProvider).speak(summary);
          }
        }
      }

      state = state.copyWith(
          isResearching: false, researchStatus: null, researchProgress: 0.0);
    } catch (e) {
      state = state.copyWith(
          isResearching: false,
          error: "Research failed: $e. Please check API keys.",
          researchStatus: null);
    }
  }

  Future<void> toggleVoice({Function(String)? onInputComplete}) async {
    final voiceService = ref.read(voiceServiceProvider);

    if (state.isListening) {
      try {
        await voiceService.stopListening();
        state = state.copyWith(isListening: false);
      } catch (e) {
        debugPrint('Error stopping voice: $e');
        state = state.copyWith(
            isListening: false, error: 'Failed to stop voice: $e');
      }
    } else {
      state = state.copyWith(isListening: true, currentSpeechText: '');

      try {
        await voiceService.listen(
          onResult: (text) {
            state = state.copyWith(currentSpeechText: text);
          },
          onDone: (text) async {
            state = state.copyWith(isListening: false, currentSpeechText: '');
            if (text.trim().isNotEmpty) {
              if (onInputComplete != null) {
                onInputComplete(text);
              } else {
                // Fallback if no callback provided
                sendEmotionalSupportMessage(text, triggeredByVoice: true);
              }
            }
          },
        );
      } catch (e) {
        debugPrint('Error starting voice: $e');
        state = state.copyWith(
          isListening: false,
          error:
              'Voice initialization failed: $e. Please check microphone permissions.',
        );
      }
    }
  }

  // Method to stop voice (if leaving screen)
  Future<void> stopVoice() async {
    final voiceService = ref.read(voiceServiceProvider);
    await voiceService.stopListening();
    await voiceService.stopSpeaking();
    state = state.copyWith(isListening: false);
  }

  void _addUserMessage(String text) {
    state = state.copyWith(messages: [
      ...state.messages,
      WellnessMessage(content: text, isUser: true, timestamp: DateTime.now())
    ]);
  }

  void _addAIMessage(String text, {bool isResearchResult = false}) {
    state = state.copyWith(isTyping: false, messages: [
      ...state.messages,
      WellnessMessage(
          content: text,
          isUser: false,
          timestamp: DateTime.now(),
          isResearchResult: isResearchResult)
    ]);
  }

  Future<String> _getSelectedProvider() async {
    final settings = await AISettingsService.getSettingsWithDefault(ref.read);
    return settings.provider;
  }

  Future<String> _getSelectedModel() async {
    final settings = await AISettingsService.getSettingsWithDefault(ref.read);
    return settings.getEffectiveModel();
  }

  Future<String> _getAIResponse(String userMessage,
      {required bool isMedical}) async {
    final model = await _getSelectedModel();

    final systemPrompt = isMedical
        ? "You are a medical research assistant. Provide accurate, citation-backed information. Always clarify you are an AI and not a doctor."
        : "You are a compassionate, empathetic emotional support companion. Listen actively, validate feelings, and offer gentle coping strategies for stress and anxiety. Help the user feel heard and understood. Do not give medical advice. Keep responses concise and conversational for voice interaction.";

    final fullPrompt = "$systemPrompt\n\nUser: $userMessage";

    // Use Backend Proxy (Admin's API keys)
    final apiService = ref.read(apiServiceProvider);
    final messages = [
      {'role': 'user', 'content': fullPrompt}
    ];

    final provider = await _getSelectedProvider();
    return await apiService.chatWithAI(
      messages: messages,
      provider: provider,
      model: model,
      billingFeature: 'chat_message',
    );
  }
}

final wellnessProvider =
    StateNotifierProvider<WellnessNotifier, WellnessState>((ref) {
  return WellnessNotifier(ref);
});
