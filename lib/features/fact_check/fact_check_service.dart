import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ai/ai_settings_service.dart';
import '../../core/api/api_service.dart';

class FactCheckResult {
  final String claim;
  final String verdict; // 'True', 'False', 'Misleading', 'Unverified'
  final String explanation;
  final double confidence;

  FactCheckResult({
    required this.claim,
    required this.verdict,
    required this.explanation,
    required this.confidence,
  });

  factory FactCheckResult.fromJson(Map<String, dynamic> json) {
    return FactCheckResult(
      claim: json['claim'] as String? ?? 'Unknown claim',
      verdict: json['verdict'] as String? ?? 'Unverified',
      explanation: json['explanation'] as String? ?? 'No explanation provided',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Code analysis result from the backend
class CodeAnalysisResult {
  final int rating;
  final String ratingExplanation;
  final String summary;
  final String purpose;
  final List<ComponentAnalysis> keyComponents;
  final QualityMetrics qualityMetrics;
  final List<String> strengths;
  final List<String> improvements;
  final List<String> securityNotes;
  final String language;
  final int linesOfCode;
  final String complexity;

  CodeAnalysisResult({
    required this.rating,
    required this.ratingExplanation,
    required this.summary,
    required this.purpose,
    required this.keyComponents,
    required this.qualityMetrics,
    required this.strengths,
    required this.improvements,
    required this.securityNotes,
    required this.language,
    required this.linesOfCode,
    required this.complexity,
  });

  factory CodeAnalysisResult.fromJson(Map<String, dynamic> json) {
    return CodeAnalysisResult(
      rating: json['rating'] as int? ?? 5,
      ratingExplanation: json['ratingExplanation'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      purpose: json['purpose'] as String? ?? '',
      keyComponents: (json['keyComponents'] as List<dynamic>?)
              ?.map((e) => ComponentAnalysis.fromJson(e))
              .toList() ??
          [],
      qualityMetrics: QualityMetrics.fromJson(
          json['qualityMetrics'] as Map<String, dynamic>? ?? {}),
      strengths: (json['strengths'] as List<dynamic>?)?.cast<String>() ?? [],
      improvements:
          (json['improvements'] as List<dynamic>?)?.cast<String>() ?? [],
      securityNotes:
          (json['securityNotes'] as List<dynamic>?)?.cast<String>() ?? [],
      language: json['language'] as String? ?? 'unknown',
      linesOfCode: json['linesOfCode'] as int? ?? 0,
      complexity: json['complexity'] as String? ?? 'unknown',
    );
  }
}

class ComponentAnalysis {
  final String name;
  final String type;
  final String description;

  ComponentAnalysis({
    required this.name,
    required this.type,
    required this.description,
  });

  factory ComponentAnalysis.fromJson(Map<String, dynamic> json) {
    return ComponentAnalysis(
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? 'other',
      description: json['description'] as String? ?? '',
    );
  }
}

class QualityMetrics {
  final int readability;
  final int maintainability;
  final int testability;
  final int documentation;
  final int errorHandling;

  QualityMetrics({
    required this.readability,
    required this.maintainability,
    required this.testability,
    required this.documentation,
    required this.errorHandling,
  });

  factory QualityMetrics.fromJson(Map<String, dynamic> json) {
    return QualityMetrics(
      readability: json['readability'] as int? ?? 5,
      maintainability: json['maintainability'] as int? ?? 5,
      testability: json['testability'] as int? ?? 5,
      documentation: json['documentation'] as int? ?? 5,
      errorHandling: json['errorHandling'] as int? ?? 5,
    );
  }

  double get average =>
      (readability +
          maintainability +
          testability +
          documentation +
          errorHandling) /
      5;
}

class FactCheckService {
  final Ref ref;

  FactCheckService(this.ref);

  Future<String> _generateContent(String prompt) async {
    final settings = await AISettingsService.getSettingsWithDefault(ref.read);
    final model = settings.getEffectiveModel();

    // Use Backend Proxy (Admin's API keys)
    final apiService = ref.read(apiServiceProvider);
    final messages = [
      {'role': 'user', 'content': prompt}
    ];

    return await apiService.chatWithAI(
      messages: messages,
      provider: settings.provider,
      model: model,
      billingFeature: 'chat_message',
    );
  }

  /// Verify content with optional code analysis context
  /// When analysisContext is provided, it enhances fact-checking for code sources
  Future<List<FactCheckResult>> verifyContent(
    String content, {
    String? analysisContext,
    CodeAnalysisResult? codeAnalysis,
  }) async {
    if (content.trim().isEmpty) return [];

    // Truncate if too long to avoid token limits (rudimentary check)
    final truncatedContent = content.length > 20000
        ? '${content.substring(0, 20000)}...(truncated)'
        : content;

    // Build context section for code analysis
    String codeContext = '';
    if (codeAnalysis != null) {
      codeContext = '''

CODE ANALYSIS CONTEXT (Use this to inform your fact-checking):
- Overall Quality Rating: ${codeAnalysis.rating}/10 - ${codeAnalysis.ratingExplanation}
- Purpose: ${codeAnalysis.purpose}
- Summary: ${codeAnalysis.summary}
- Language: ${codeAnalysis.language}
- Complexity: ${codeAnalysis.complexity}
- Lines of Code: ${codeAnalysis.linesOfCode}

Quality Metrics:
- Readability: ${codeAnalysis.qualityMetrics.readability}/10
- Maintainability: ${codeAnalysis.qualityMetrics.maintainability}/10
- Testability: ${codeAnalysis.qualityMetrics.testability}/10
- Documentation: ${codeAnalysis.qualityMetrics.documentation}/10
- Error Handling: ${codeAnalysis.qualityMetrics.errorHandling}/10

Key Components:
${codeAnalysis.keyComponents.map((c) => '- ${c.name} (${c.type}): ${c.description}').join('\n')}

Strengths:
${codeAnalysis.strengths.map((s) => '- $s').join('\n')}

Areas for Improvement:
${codeAnalysis.improvements.map((i) => '- $i').join('\n')}

${codeAnalysis.securityNotes.isNotEmpty ? 'Security Notes:\n${codeAnalysis.securityNotes.map((n) => '- $n').join('\n')}' : ''}
''';
    } else if (analysisContext != null && analysisContext.isNotEmpty) {
      codeContext = '''

CODE ANALYSIS CONTEXT (Use this to inform your fact-checking):
$analysisContext
''';
    }

    final prompt = '''
You are a professional fact-checker and research analyst. Analyze the following text and identify specific factual claims that can be verified. 
For each claim, verify its accuracy based on your general knowledge.
$codeContext
Text to analyze:
"""
$truncatedContent
"""

Return a JSON array where each object has:
- "claim": The specific claim extracted from the text (quote it exactly or paraphrase clearly).
- "verdict": "True", "False", "Misleading", or "Unverified".
- "explanation": A DETAILED explanation (2-4 sentences) explaining:
  1. WHY this verdict was given
  2. What evidence or reasoning supports this conclusion
  3. Any important context or nuance
  4. If False/Misleading, what the correct information is
- "confidence": A score from 0.0 to 1.0 indicating your certainty.

${codeAnalysis != null ? '''
For CODE sources, also verify:
- Claims about code quality (compare with the analysis rating)
- Claims about what the code does (compare with the purpose/summary)
- Claims about security (compare with security notes)
- Claims about best practices (compare with improvements)
''' : ''}

IMPORTANT: The explanation must be thorough and educational. Don't just state the verdict - explain the reasoning behind it so users understand WHY a claim is true, false, or misleading.

Ensure the output is valid JSON. Do not include markdown code blocks (` ` `json).
''';

    try {
      final response = await _generateContent(prompt);

      // Clean response
      String jsonStr = response.trim();
      if (jsonStr.startsWith('```json')) jsonStr = jsonStr.substring(7);
      if (jsonStr.startsWith('```')) jsonStr = jsonStr.substring(3);
      if (jsonStr.endsWith('```')) {
        jsonStr = jsonStr.substring(0, jsonStr.length - 3);
      }

      final List<dynamic> jsonList = jsonDecode(jsonStr);
      return jsonList.map((e) => FactCheckResult.fromJson(e)).toList();
    } catch (e) {
      throw Exception('Fact check verification failed: $e');
    }
  }

  /// Verify code-specific claims using the code analysis
  Future<List<FactCheckResult>> verifyCodeClaims(
    String code,
    CodeAnalysisResult analysis,
  ) async {
    final prompt = '''
You are a code quality analyst. Based on the following code and its AI analysis, verify the accuracy of the analysis claims.

CODE:
```${analysis.language}
${code.length > 10000 ? '${code.substring(0, 10000)}...(truncated)' : code}
```

AI ANALYSIS CLAIMS TO VERIFY:
1. Rating: ${analysis.rating}/10 - "${analysis.ratingExplanation}"
2. Purpose: "${analysis.purpose}"
3. Summary: "${analysis.summary}"
4. Complexity: ${analysis.complexity}
5. Quality Metrics: Readability ${analysis.qualityMetrics.readability}/10, Maintainability ${analysis.qualityMetrics.maintainability}/10

Strengths claimed:
${analysis.strengths.map((s) => '- $s').join('\n')}

Improvements suggested:
${analysis.improvements.map((i) => '- $i').join('\n')}

Return a JSON array verifying each major claim. For each:
- "claim": The specific claim from the analysis
- "verdict": "True", "False", "Misleading", or "Unverified"
- "explanation": Why this verdict (2-3 sentences)
- "confidence": 0.0 to 1.0

Focus on verifiable claims about the code. Be objective and technical.
Ensure the output is valid JSON. Do not include markdown code blocks.
''';

    try {
      final response = await _generateContent(prompt);

      String jsonStr = response.trim();
      if (jsonStr.startsWith('```json')) jsonStr = jsonStr.substring(7);
      if (jsonStr.startsWith('```')) jsonStr = jsonStr.substring(3);
      if (jsonStr.endsWith('```')) {
        jsonStr = jsonStr.substring(0, jsonStr.length - 3);
      }

      final List<dynamic> jsonList = jsonDecode(jsonStr);
      return jsonList.map((e) => FactCheckResult.fromJson(e)).toList();
    } catch (e) {
      throw Exception('Code claim verification failed: $e');
    }
  }
}

final factCheckServiceProvider =
    Provider<FactCheckService>((ref) => FactCheckService(ref));
