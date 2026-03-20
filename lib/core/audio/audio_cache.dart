import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/studio/audio_overview.dart';
import 'package:dio/dio.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

class AudioCacheNotifier extends StateNotifier<List<AudioOverview>> {
  AudioCacheNotifier() : super([]);

  Future<void> cache(AudioOverview overview) async {
    if (overview.isOffline) return;
    if (overview.url.isEmpty) return;
    final localUrl = await _resolveLocalUrl(overview);
    if (localUrl == null) return;
    final cached = overview.copyWith(isOffline: true, url: localUrl);
    state = [...state.where((a) => a.id != overview.id), cached];
  }

  Future<void> remove(AudioOverview overview) async {
    state = state.where((a) => a.id != overview.id).toList();
  }

  Future<String?> _resolveLocalUrl(AudioOverview overview) async {
    if (_isRemoteUrl(overview.url)) {
      final dir = Directory.systemTemp.path;
      final safeTitle =
          overview.title.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final extension = p.extension(overview.url).isNotEmpty
          ? p.extension(overview.url)
          : '.mp3';
      final fileName = '${safeTitle}_${overview.id}$extension';
      final outPath = p.join(dir, fileName);
      await Dio().download(overview.url, outPath);
      return Uri.file(outPath, windows: Platform.isWindows).toString();
    }

    final sourcePath = _normalizeLocalPath(overview.url);
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      return null;
    }

    return Uri.file(sourceFile.path, windows: Platform.isWindows).toString();
  }

  bool _isRemoteUrl(String value) {
    final uri = Uri.tryParse(value);
    final scheme = uri?.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https';
  }

  String _normalizeLocalPath(String value) {
    final uri = Uri.tryParse(value);
    if (uri != null && uri.scheme == 'file') {
      return uri.toFilePath(windows: Platform.isWindows);
    }
    return value;
  }
}

final audioCacheProvider =
    StateNotifierProvider<AudioCacheNotifier, List<AudioOverview>>(
        (ref) => AudioCacheNotifier());
