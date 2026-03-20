import 'dart:typed_data';

import 'file_download_stub.dart'
    if (dart.library.html) 'file_download_web.dart'
    if (dart.library.io) 'file_download_io.dart' as impl;

Future<String?> saveFileBytes({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) {
  return impl.saveFileBytes(
    bytes: bytes,
    fileName: fileName,
    mimeType: mimeType,
  );
}
