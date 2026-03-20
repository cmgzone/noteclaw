import 'dart:convert';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'infographic.freezed.dart';
part 'infographic.g.dart';

/// Represents an AI-generated infographic for a source
@freezed
class Infographic with _$Infographic {
  const factory Infographic({
    required String id,
    required String title,
    required String sourceId,
    required String notebookId,
    String? imageUrl, // URL if stored remotely
    String? imageBase64, // Base64 if stored locally
    String? description,
    @Default(InfographicStyle.modern) InfographicStyle style,
    required DateTime createdAt,
  }) = _Infographic;

  const Infographic._();

  bool get hasHtmlContent =>
      imageUrl != null && imageUrl!.startsWith('data:text/html');

  String? get htmlContent {
    final url = imageUrl;
    if (url == null || !url.startsWith('data:text/html')) {
      return null;
    }

    final commaIndex = url.indexOf(',');
    if (commaIndex == -1 || commaIndex + 1 >= url.length) {
      return null;
    }

    final metadata = url.substring(0, commaIndex);
    final payload = url.substring(commaIndex + 1);

    try {
      if (metadata.contains(';base64')) {
        return utf8.decode(base64Decode(payload));
      }
      return Uri.decodeComponent(payload);
    } catch (_) {
      return null;
    }
  }

  factory Infographic.fromBackendJson(Map<String, dynamic> json) => Infographic(
        id: json['id'],
        title: json['title'],
        sourceId: json['source_id'],
        notebookId: json['notebook_id'],
        imageUrl: json['image_url'],
        imageBase64: json['image_base64'],
        description: json['description'],
        style: InfographicStyle.values.firstWhere(
          (s) => s.name == (json['style'] ?? 'modern'),
          orElse: () => InfographicStyle.modern,
        ),
        createdAt: DateTime.parse(json['created_at']),
      );

  Map<String, dynamic> toBackendJson() => {
        'id': id,
        'title': title,
        'source_id': sourceId,
        'notebook_id': notebookId,
        'image_url': imageUrl,
        'image_base64': imageBase64,
        'description': description,
        'style': style.name,
        'created_at': createdAt.toIso8601String(),
      };

  factory Infographic.fromJson(Map<String, dynamic> json) =>
      _$InfographicFromJson(json);
}

/// Visual style for infographics
enum InfographicStyle {
  modern,
  minimal,
  colorful,
  professional,
  playful,
}
