import 'dart:typed_data';

Future<String?> saveFileBytes({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) async {
  throw UnsupportedError('File download is not supported on this platform.');
}
