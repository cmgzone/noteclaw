import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'chunk.dart';
import '../../features/sources/source.dart';
import '../api/api_service.dart';

class RealIngestionService {
  final ApiService _api;

  RealIngestionService(this._api);

  Future<List<Chunk>> chunkSource(Source source) async {
    try {
      // Ingestion is heavy: PDF parse → chunking → N embedding API calls →
      // pgvector inserts. Use a generous 5-minute receive timeout.
      await _api.postWithTimeout(
        '/rag/ingestion/process',
        {'sourceId': source.id},
        receiveTimeout: const Duration(minutes: 5),
        sendTimeout: const Duration(minutes: 2),
      );

      // Embeddings are stored server-side; no chunks need to be returned to
      // the client (search happens via the backend RAG endpoint).
      return [];
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Ingestion failed: $e');
      }
      rethrow;
    }
  }
}

final realIngestionProvider = Provider((ref) {
  final api = ref.read(apiServiceProvider);
  return RealIngestionService(api);
});
