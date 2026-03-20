import 'dart:typed_data';

UriData? tryParseImageDataUri(String? value) {
  if (value == null) return null;

  final trimmed = value.trim();
  if (!trimmed.startsWith('data:image/')) return null;

  try {
    return Uri.parse(trimmed).data;
  } catch (_) {
    return null;
  }
}

bool isImageDataUri(String? value) => tryParseImageDataUri(value) != null;

bool isSvgImageDataUri(String? value) {
  final data = tryParseImageDataUri(value);
  return data?.mimeType.toLowerCase() == 'image/svg+xml';
}

Uint8List? decodeImageDataUriBytes(String? value) {
  final data = tryParseImageDataUri(value);
  if (data == null) return null;

  try {
    return data.contentAsBytes();
  } catch (_) {
    return null;
  }
}
