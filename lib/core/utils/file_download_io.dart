import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<String?> saveFileBytes({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) async {
  Directory? targetDir;

  if (Platform.isAndroid) {
    final androidDownloads = Directory('/storage/emulated/0/Download');
    if (await androidDownloads.exists()) {
      targetDir = androidDownloads;
    } else {
      targetDir = await getExternalStorageDirectory();
    }
  } else {
    targetDir = await getDownloadsDirectory();
  }

  targetDir ??= await getApplicationDocumentsDirectory();

  final safeFileName = fileName
      .replaceAll(RegExp(r'[<>:"/\\|?*]+'), '_')
      .replaceAll(RegExp(r'\s+'), '_');

  final path = p.join(targetDir.path, safeFileName);
  final file = File(path);
  await file.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
