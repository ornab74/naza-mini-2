import 'dart:async';

import 'package:llamadart/llamadart.dart';

/// Scanner-only local inference wrapper.
///
/// NAZA deliberately exposes no chat/session API here. LlamaDart is used only
/// for one-shot and chunked road-risk classifier prompts.
class ScannerInferenceService {
  final LlamaEngine _engine = LlamaEngine(LlamaBackend());
  String? _loadedPath;
  Future<void> _operationTail = Future<void>.value();

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = Completer<T>();
    final previous = _operationTail;
    _operationTail = previous.then<void>((_) async {
      try {
        result.complete(await action());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  bool get isLoaded => _engine.isReady;
  String? get loadedPath => _loadedPath;

  Future<void> load(String path) async {
    return _serialize(() async {
      if (_loadedPath == path && _engine.isReady) return;
      if (_engine.isReady) await _engine.unloadModel();
      await _engine.loadModel(
        path,
        modelParams: const ModelParams(
          contextSize: 2048,
          gpuLayers: 0,
          preferredBackend: GpuBackend.cpu,
          numberOfThreads: 4,
          numberOfThreadsBatch: 4,
          batchSize: 256,
          microBatchSize: 128,
          useMmap: true,
          useMlock: false,
        ),
      );
      _loadedPath = path;
    });
  }

  Future<String> backendName() async {
    return _serialize(() async {
      if (!_engine.isReady) return 'not loaded';
      try {
        return await _engine.getBackendName();
      } catch (_) {
        return 'auto';
      }
    });
  }

  Future<String> generate(
    String prompt, {
    int maxTokens = 128,
    double temperature = 0.2,
  }) {
    return _serialize(() async {
      final buffer = StringBuffer();
      await for (final text in _engine.generate(
        prompt,
        params: GenerationParams(maxTokens: maxTokens, temp: temperature),
      )) {
        buffer.write(text);
      }
      return buffer.toString().trim();
    });
  }

  void cancel() => _engine.cancelGeneration();

  Future<void> unload() {
    return _serialize(() async {
      if (_engine.isReady) await _engine.unloadModel();
      _loadedPath = null;
    });
  }

  Future<void> dispose() {
    return _serialize(() => _engine.dispose());
  }
}
