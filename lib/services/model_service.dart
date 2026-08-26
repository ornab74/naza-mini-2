import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../models.dart';
import 'crypto_service.dart';
import 'storage_service.dart';

typedef ModelDownloadProgress = void Function(double value, String detail);

enum _MirrorKind { github, huggingFace, pinata }

class _ModelMirror {
  const _ModelMirror({
    required this.id,
    required this.label,
    required this.uri,
    required this.kind,
  });

  final String id;
  final String label;
  final Uri uri;
  final _MirrorKind kind;
}

class _MirrorSession {
  _MirrorSession(this.mirror)
      : client = HttpClient()
          ..connectionTimeout = ModelService._connectTimeout
          ..autoUncompress = false;

  final _ModelMirror mirror;
  final HttpClient client;
  double ewmaBytesPerSecond = 0;
  int successes = 0;
  int failures = 0;
  String? lastError;
  DateTime cooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool disabled = false;

  bool get ready => !disabled && DateTime.now().isAfter(cooldownUntil);

  double get score {
    final speed = ewmaBytesPerSecond <= 0 ? 1 : ewmaBytesPerSecond;
    final reliability = 1 / (1 + failures * 0.8);
    return speed * reliability;
  }

  void recordSuccess(int bytes, Duration elapsed) {
    final micros = max(1, elapsed.inMicroseconds);
    final instant = bytes * Duration.microsecondsPerSecond / micros;
    ewmaBytesPerSecond = ewmaBytesPerSecond <= 0
        ? instant
        : (ewmaBytesPerSecond * 0.70) + (instant * 0.30);
    successes++;
    if (failures > 0) failures--;
    cooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);
  }

  void recordFailure([Object? error]) {
    failures++;
    lastError = error?.toString();
    final exponent = min(5, failures);
    cooldownUntil = DateTime.now().add(
      Duration(milliseconds: 350 * (1 << exponent)),
    );
  }

  void close() => client.close(force: true);
}

class _DownloadChunk {
  _DownloadChunk({
    required this.index,
    required this.start,
    required this.end,
  });

  final int index;
  final int start;
  final int end;
  int attempts = 0;
  int get length => end - start + 1;
}

class ModelService {
  ModelService(this.storage, this.crypto);

  final NazaStorageService storage;
  final NazaCryptoService crypto;
  Future<void> _operationTail = Future<void>.value();

  /// Model files are shared by download, decrypt, inference cleanup, and
  /// manual encrypt actions. Serialize those operations so two UI actions
  /// cannot delete or rename the same `.partial` file at once.
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

  static const int _chunkSize = 4 * 1024 * 1024;
  static const int _probeBytes = 256 * 1024;
  static const int _adaptiveWorkers = 2;
  static const int _maxChunkAttempts = 9;
  static const int _maxRedirects = 6;
  static const Duration _connectTimeout = Duration(seconds: 18);
  static const Duration _responseTimeout = Duration(seconds: 30);
  static const Duration _idleTimeout = Duration(seconds: 35);

  File plainFile(NazaModelProfile profile) =>
      File('${storage.modelsDir.path}/${profile.fileName}');
  File encryptedFile(NazaModelProfile profile) =>
      File('${plainFile(profile).path}.aes');

  Future<bool> hasPlain(NazaModelProfile profile) => plainFile(profile).exists();
  Future<bool> hasEncrypted(NazaModelProfile profile) =>
      encryptedFile(profile).exists();

  Future<String> verify(NazaModelProfile profile) async {
    final file = plainFile(profile);
    if (!await file.exists()) throw StateError('No plaintext model found.');
    return crypto.sha256File(file);
  }

  /// Normalizes a Pinata gateway URL or an `ipfs://CID[/path]` URI.
  /// Only HTTPS Pinata gateway hosts are accepted after normalization.
  static Uri? normalizePinataUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;

    Uri? uri;
    if (value.startsWith('ipfs://')) {
      final ipfs = Uri.tryParse(value);
      if (ipfs == null || ipfs.host.isEmpty) {
        throw const FormatException('Invalid IPFS URI.');
      }
      final suffix = ipfs.path.isEmpty ? '' : ipfs.path;
      uri = Uri.parse('https://gateway.pinata.cloud/ipfs/${ipfs.host}$suffix');
    } else if (!value.contains('://') &&
        RegExp(r'^[A-Za-z0-9]{40,}(?:/.*)?$').hasMatch(value)) {
      uri = Uri.parse('https://gateway.pinata.cloud/ipfs/$value');
    } else {
      uri = Uri.tryParse(value);
    }

    if (uri == null || uri.scheme != 'https' || !_isPinataHost(uri.host)) {
      throw const FormatException(
        'Pinata mirror must be an HTTPS *.mypinata.cloud / *.pinata.cloud URL, '
        'an ipfs:// URI, or a bare CID.',
      );
    }
    return uri;
  }

  Future<void> cleanupTemporaryFiles() => _serialize(() async {
        for (final profile in nazaModelProfiles) {
          final plainPath = plainFile(profile).path;
          await for (final entity in storage.modelsDir.list()) {
            if (entity is File &&
                entity.path.startsWith(plainPath) &&
                entity.path.endsWith('.partial')) {
              await _deleteIfExists(entity);
            }
          }
        }
      });

  Future<String> download(
    NazaModelProfile profile, {
    String? pinataUrl,
    ModelDownloadProgress? onProgress,
  }) =>
      _serialize(
        () => _download(
          profile,
          pinataUrl: pinataUrl,
          onProgress: onProgress,
        ),
      );

  Future<String> _download(
    NazaModelProfile profile, {
    String? pinataUrl,
    ModelDownloadProgress? onProgress,
  }) async {
    final destination = plainFile(profile);
    await destination.parent.create(recursive: true);

    if (await destination.exists()) {
      final size = await destination.length();
      if (size == profile.expectedSize) {
        onProgress?.call(0.02, 'Checking existing plaintext model…');
        final existingHash = await crypto.sha256File(destination);
        if (_constantTimeHexEquals(existingHash, profile.expectedSha256)) {
          onProgress?.call(1, 'Existing model already verified.');
          return existingHash;
        }
      }
      await destination.delete();
    }

    final mirrors = <_ModelMirror>[
      _ModelMirror(
        id: 'github',
        label: 'GitHub Release',
        uri: Uri.parse(profile.githubReleaseUrl),
        kind: _MirrorKind.github,
      ),
      _ModelMirror(
        id: 'huggingface',
        label: 'Hugging Face',
        uri: Uri.parse(profile.huggingFaceUrl),
        kind: _MirrorKind.huggingFace,
      ),
    ];
    final configuredPinata = pinataUrl?.trim();
    final pinata = normalizePinataUrl(
      configuredPinata == null || configuredPinata.isEmpty
          ? profile.pinataUrl
          : configuredPinata,
    );
    if (pinata != null) {
      mirrors.add(
        _ModelMirror(
          id: 'pinata',
          label: 'Pinata IPFS',
          uri: pinata,
          kind: _MirrorKind.pinata,
        ),
      );
    }

    for (final mirror in mirrors) {
      _validateMirrorRoot(mirror);
    }

    final workDir = Directory('${destination.path}.multihost');
    final manifestFile = File('${workDir.path}/resume.json');
    await workDir.create(recursive: true);

    final sessions = mirrors.map(_MirrorSession.new).toList(growable: false);
    try {
      onProgress?.call(
        0.01,
        'Racing ${sessions.length} secure provider${sessions.length == 1 ? '' : 's'}…',
      );
      await Future.wait(
        sessions.map(
          (session) => _probeWithRetry(
            session,
            profile,
            workDir,
            onProgress: onProgress,
          ),
        ),
      );

      final live = sessions.where((session) => !session.disabled).toList();
      if (live.isEmpty) {
        final details = sessions
            .map(
              (session) =>
                  '${session.mirror.label}: ${session.lastError ?? 'unknown error'}',
            )
            .join(' | ');
        throw StateError(
          'All model mirrors failed the range/TLS probe. Details: $details',
        );
      }

      onProgress?.call(0.03, 'Secure mirrors ready • ${_telemetry(live)}');

      final chunkCount = (profile.expectedSize + _chunkSize - 1) ~/ _chunkSize;
      final chunks = List<_DownloadChunk>.generate(chunkCount, (index) {
        final start = index * _chunkSize;
        final end = min(profile.expectedSize - 1, start + _chunkSize - 1);
        return _DownloadChunk(index: index, start: start, end: end);
      });

      final resumeDigests = await _loadResumeManifest(
        manifestFile,
        profile: profile,
        chunkCount: chunkCount,
      );

      final pending = Queue<_DownloadChunk>();
      var completedBytes = 0;
      for (final chunk in chunks) {
        final chunkFile = _chunkFile(workDir, chunk.index);
        final remembered = resumeDigests[chunk.index];
        if (remembered != null &&
            await chunkFile.exists() &&
            await chunkFile.length() == chunk.length) {
          final digest = await crypto.sha256File(chunkFile);
          if (_constantTimeHexEquals(digest, remembered)) {
            completedBytes += chunk.length;
            continue;
          }
          await chunkFile.delete();
          resumeDigests.remove(chunk.index);
        }
        pending.add(chunk);
      }

      Object? fatalError;
      StackTrace? fatalStack;
      Future<void> manifestTail = Future<void>.value();

      Future<void> persistManifest() {
        final snapshot = Map<int, String>.from(resumeDigests);
        manifestTail = manifestTail.then(
          (_) => _writeResumeManifest(
            manifestFile,
            profile: profile,
            chunkCount: chunkCount,
            digests: snapshot,
          ),
        );
        return manifestTail;
      }

      _DownloadChunk? claim() {
        if (pending.isEmpty) return null;
        return pending.removeFirst();
      }

      _MirrorSession bestMirror() {
        final ready = live.where((session) => session.ready).toList();
        final candidates = ready.isEmpty ? live : ready;
        candidates.sort((a, b) => b.score.compareTo(a.score));
        return candidates.first;
      }

      Future<void> worker(_MirrorSession? fixedSession) async {
        while (fatalError == null) {
          final session = fixedSession ?? bestMirror();
          if (!session.ready) {
            await Future<void>.delayed(const Duration(milliseconds: 180));
            continue;
          }

          final task = claim();
          if (task == null) {
            if (pending.isEmpty) return;
            await Future<void>.delayed(const Duration(milliseconds: 80));
            continue;
          }

          final chunkFile = _chunkFile(workDir, task.index);
          final partial = File('${chunkFile.path}.partial');
          try {
            await _deleteIfExists(partial);
            final stopwatch = Stopwatch()..start();
            await _downloadRange(
              session: session,
              uri: session.mirror.uri,
              start: task.start,
              end: task.end,
              expectedTotal: profile.expectedSize,
              destination: partial,
            );
            stopwatch.stop();

            if (await partial.length() != task.length) {
              throw StateError(
                'Chunk ${task.index} length mismatch from ${session.mirror.label}.',
              );
            }

            final digest = await crypto.sha256File(partial);
            if (await chunkFile.exists()) await chunkFile.delete();
            await partial.rename(chunkFile.path);

            session.recordSuccess(task.length, stopwatch.elapsed);
            resumeDigests[task.index] = digest;
            completedBytes += task.length;
            await persistManifest();

            final fraction = completedBytes / profile.expectedSize;
            onProgress?.call(
              (0.04 + fraction * 0.78).clamp(0.04, 0.82).toDouble(),
              'Multi-host CHUNKD download • ${_telemetry(live)}',
            );
          } catch (error, stack) {
            await _deleteIfExists(partial);
            session.recordFailure();
            task.attempts++;
            if (task.attempts >= _maxChunkAttempts) {
              fatalError = StateError(
                'Chunk ${task.index} failed after ${task.attempts} attempts. '
                'Last provider: ${session.mirror.label}. Error: $error',
              );
              fatalStack = stack;
              return;
            }

            pending.addLast(task);
            onProgress?.call(
              (0.04 + (completedBytes / profile.expectedSize) * 0.78)
                  .clamp(0.04, 0.82)
                  .toDouble(),
              '${session.mirror.label} retry/failover • ${_telemetry(live)}',
            );
          }
        }
      }

      final workers = <Future<void>>[
        for (final session in live) worker(session),
        for (var i = 0; i < min(_adaptiveWorkers, live.length + 1); i++)
          worker(null),
      ];
      await Future.wait(workers);
      await manifestTail;

      if (fatalError != null) {
        Error.throwWithStackTrace(fatalError!, fatalStack ?? StackTrace.current);
      }
      if (pending.isNotEmpty) {
        throw StateError('${pending.length} model chunks were not completed.');
      }

      final staging = File('${destination.path}.verified.partial');
      await _deleteIfExists(staging);
      final sink = staging.openWrite(mode: FileMode.writeOnly);
      try {
        for (var index = 0; index < chunkCount; index++) {
          final chunkFile = _chunkFile(workDir, index);
          final remembered = resumeDigests[index];
          if (remembered == null || !await chunkFile.exists()) {
            throw StateError('Missing verified chunk $index during assembly.');
          }
          final actual = await crypto.sha256File(chunkFile);
          if (!_constantTimeHexEquals(actual, remembered)) {
            throw StateError('Chunk $index changed after download.');
          }
          await for (final bytes in chunkFile.openRead()) {
            sink.add(bytes);
          }
          onProgress?.call(
            0.82 + ((index + 1) / chunkCount) * 0.08,
            'Assembling verified chunks ${index + 1}/$chunkCount…',
          );
        }
      } finally {
        await sink.close();
      }

      if (await staging.length() != profile.expectedSize) {
        await _deleteIfExists(staging);
        throw StateError(
          'Final model size mismatch. Expected ${profile.expectedSize} bytes.',
        );
      }

      onProgress?.call(0.91, 'Computing pinned full-file SHA-256…');
      final sha = await crypto.sha256File(staging);
      if (!_constantTimeHexEquals(sha, profile.expectedSha256)) {
        await _deleteIfExists(staging);
        await workDir.delete(recursive: true);
        throw StateError(
          'Final SHA-256 mismatch. Refusing model. Expected '
          '${profile.expectedSha256}, got $sha.',
        );
      }

      onProgress?.call(0.98, 'SHA-256 verified • promoting atomically…');
      if (await destination.exists()) await destination.delete();
      await staging.rename(destination.path);
      if (await workDir.exists()) await workDir.delete(recursive: true);
      onProgress?.call(1, 'Verified model ready for AES-256-GCM encryption.');
      return sha;
    } finally {
      for (final session in sessions) {
        session.close();
      }
    }
  }

  Future<void> _probeWithRetry(
    _MirrorSession session,
    NazaModelProfile profile,
    Directory workDir, {
    ModelDownloadProgress? onProgress,
  }) async {
    final probe = File('${workDir.path}/probe_${session.mirror.id}.partial');
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        await _deleteIfExists(probe);
        final end = min(profile.expectedSize - 1, _probeBytes - 1);
        final stopwatch = Stopwatch()..start();
        await _downloadRange(
          session: session,
          uri: session.mirror.uri,
          start: 0,
          end: end,
          expectedTotal: profile.expectedSize,
          destination: probe,
        );
        stopwatch.stop();
        final bytes = await probe.length();
        session.recordSuccess(bytes, stopwatch.elapsed);
        await _deleteIfExists(probe);
        return;
      } catch (error) {
        await _deleteIfExists(probe);
        session.recordFailure(error);
        if (attempt == 2) {
          session.disabled = true;
          onProgress?.call(
            0.02,
            '${session.mirror.label} probe unavailable; continuing securely.',
          );
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 450));
      }
    }
  }

  Future<void> _downloadRange({
    required _MirrorSession session,
    required Uri uri,
    required int start,
    required int end,
    required int expectedTotal,
    required File destination,
  }) async {
    var current = uri;
    for (var redirect = 0; redirect <= _maxRedirects; redirect++) {
      _validateRedirect(current, session.mirror.kind);
      final request = await session.client.getUrl(current).timeout(_connectTimeout);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.userAgentHeader, 'NAZA-Scanner/1 secure-multihost');
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
      request.headers.set('Accept-Encoding', 'identity');
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-transform');

      final response = await request.close().timeout(_responseTimeout);
      if (_isRedirect(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (location == null || location.isEmpty) {
          throw StateError('${session.mirror.label} returned an empty redirect.');
        }
        current = current.resolve(location);
        continue;
      }

      if (response.statusCode != HttpStatus.partialContent) {
        await response.drain<void>();
        throw StateError(
          '${session.mirror.label} does not honor secure byte ranges '
          '(HTTP ${response.statusCode}).',
        );
      }

      final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
      final match = contentRange == null
          ? null
          : RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(contentRange.trim());
      if (match == null ||
          int.parse(match.group(1)!) != start ||
          int.parse(match.group(2)!) != end ||
          int.parse(match.group(3)!) != expectedTotal) {
        await response.drain<void>();
        throw StateError(
          '${session.mirror.label} returned an invalid Content-Range: '
          '${contentRange ?? 'missing'}.',
        );
      }

      final expectedLength = end - start + 1;
      if (response.contentLength >= 0 && response.contentLength != expectedLength) {
        await response.drain<void>();
        throw StateError(
          '${session.mirror.label} Content-Length mismatch for range $start-$end.',
        );
      }

      final sink = destination.openWrite(mode: FileMode.writeOnly);
      var received = 0;
      try {
        await for (final chunk in response.timeout(_idleTimeout)) {
          received += chunk.length;
          if (received > expectedLength) {
            throw StateError('${session.mirror.label} exceeded requested range.');
          }
          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }

      if (received != expectedLength) {
        throw StateError(
          '${session.mirror.label} truncated range $start-$end '
          '($received/$expectedLength bytes).',
        );
      }
      return;
    }

    throw StateError('${session.mirror.label} exceeded $_maxRedirects redirects.');
  }

  Future<Map<int, String>> _loadResumeManifest(
    File file, {
    required NazaModelProfile profile,
    required int chunkCount,
  }) async {
    if (!await file.exists()) return <int, String>{};
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return <int, String>{};
      if (decoded['version'] != 1 ||
          decoded['sha256'] != profile.expectedSha256 ||
          decoded['size'] != profile.expectedSize ||
          decoded['chunk_size'] != _chunkSize ||
          decoded['chunk_count'] != chunkCount) {
        await file.parent.delete(recursive: true);
        await file.parent.create(recursive: true);
        return <int, String>{};
      }
      final rawChunks = decoded['chunks'];
      if (rawChunks is! Map) return <int, String>{};
      final result = <int, String>{};
      for (final entry in rawChunks.entries) {
        final index = int.tryParse(entry.key.toString());
        final digest = entry.value?.toString();
        if (index != null &&
            index >= 0 &&
            index < chunkCount &&
            digest != null &&
            RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(digest)) {
          result[index] = digest.toLowerCase();
        }
      }
      return result;
    } catch (_) {
      await file.parent.delete(recursive: true);
      await file.parent.create(recursive: true);
      return <int, String>{};
    }
  }

  Future<void> _writeResumeManifest(
    File file, {
    required NazaModelProfile profile,
    required int chunkCount,
    required Map<int, String> digests,
  }) async {
    final partial = File('${file.path}.partial');
    final payload = <String, Object>{
      'version': 1,
      'sha256': profile.expectedSha256,
      'size': profile.expectedSize,
      'chunk_size': _chunkSize,
      'chunk_count': chunkCount,
      'chunks': <String, String>{
        for (final entry in digests.entries) '${entry.key}': entry.value,
      },
    };
    await partial.writeAsString(jsonEncode(payload), flush: true);
    if (await file.exists()) await file.delete();
    await partial.rename(file.path);
  }

  File _chunkFile(Directory dir, int index) =>
      File('${dir.path}/chunk_${index.toString().padLeft(4, '0')}.bin');

  static void _validateMirrorRoot(_ModelMirror mirror) {
    if (mirror.uri.scheme != 'https') {
      throw StateError('Refusing non-HTTPS model mirror: ${mirror.uri}');
    }
    _validateRedirect(mirror.uri, mirror.kind);
  }

  static void _validateRedirect(Uri uri, _MirrorKind kind) {
    if (uri.scheme != 'https') {
      throw StateError('Blocked model redirect downgrade: $uri');
    }
    if (uri.userInfo.isNotEmpty) {
      throw StateError('Blocked credentials embedded in model mirror URL.');
    }
    if (uri.hasPort && uri.port != 443) {
      throw StateError('Blocked non-standard HTTPS model mirror port: ${uri.port}.');
    }
    final host = uri.host.toLowerCase();
    final allowed = switch (kind) {
      _MirrorKind.github =>
        host == 'github.com' ||
            host.endsWith('.github.com') ||
            host == 'githubusercontent.com' ||
            host.endsWith('.githubusercontent.com'),
      _MirrorKind.huggingFace =>
        host == 'huggingface.co' ||
            host.endsWith('.huggingface.co') ||
            host == 'hf.co' ||
            host.endsWith('.hf.co'),
      _MirrorKind.pinata => _isPinataHost(host),
    };
    if (!allowed) {
      throw StateError('Blocked untrusted model redirect host: $host');
    }
  }

  static bool _isPinataHost(String host) {
    final value = host.toLowerCase();
    return value == 'gateway.pinata.cloud' ||
        value.endsWith('.mypinata.cloud') ||
        value.endsWith('.pinata.cloud');
  }

  static bool _isRedirect(int status) =>
      status == HttpStatus.movedPermanently ||
      status == HttpStatus.found ||
      status == HttpStatus.seeOther ||
      status == HttpStatus.temporaryRedirect ||
      status == HttpStatus.permanentRedirect;

  static String _telemetry(List<_MirrorSession> sessions) {
    final active = sessions.where((session) => !session.disabled).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return active
        .map(
          (session) =>
              '${session.mirror.label} ${_formatRate(session.ewmaBytesPerSecond)}',
        )
        .join(' • ');
  }

  static String _formatRate(double bytesPerSecond) {
    if (bytesPerSecond <= 0) return 'probing';
    final mib = bytesPerSecond / (1024 * 1024);
    if (mib >= 1) return '${mib.toStringAsFixed(1)} MiB/s';
    return '${(bytesPerSecond / 1024).toStringAsFixed(0)} KiB/s';
  }

  static bool _constantTimeHexEquals(String a, String b) {
    final left = a.toLowerCase();
    final right = b.toLowerCase();
    if (left.length != right.length) return false;
    var diff = 0;
    for (var index = 0; index < left.length; index++) {
      diff |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
    }
    return diff == 0;
  }

  static Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) await file.delete();
  }

  Future<void> encrypt(
    NazaModelProfile profile, {
    Uint8List? key,
    bool removePlaintext = true,
    void Function(double value)? onProgress,
  }) =>
      _serialize(
        () => _encryptUnlocked(
          profile,
          key: key,
          removePlaintext: removePlaintext,
          onProgress: onProgress,
        ),
      );

  Future<void> _encryptUnlocked(
    NazaModelProfile profile, {
    Uint8List? key,
    bool removePlaintext = true,
    void Function(double value)? onProgress,
  }) async {
    final plain = plainFile(profile);
    if (!await plain.exists()) throw StateError('No plaintext model to encrypt.');
    await crypto.encryptFileChunked(
      plain,
      encryptedFile(profile),
      key ?? storage.key,
      onProgress: onProgress,
    );
    if (removePlaintext && await plain.exists()) await plain.delete();
  }

  Future<void> decrypt(
    NazaModelProfile profile, {
    Uint8List? key,
    void Function(double value)? onProgress,
  }) =>
      _serialize(
        () => _decryptUnlocked(
          profile,
          key: key,
          onProgress: onProgress,
        ),
      );

  Future<void> _decryptUnlocked(
    NazaModelProfile profile, {
    Uint8List? key,
    void Function(double value)? onProgress,
  }) async {
    final encrypted = encryptedFile(profile);
    if (!await encrypted.exists()) throw StateError('No .aes model present.');
    await crypto.decryptFileChunked(
      encrypted,
      plainFile(profile),
      key ?? storage.key,
      onProgress: onProgress,
    );
  }

  Future<void> deletePlain(NazaModelProfile profile) => _serialize(() async {
    final plain = plainFile(profile);
    if (await plain.exists()) await plain.delete();
  });

  Future<String> prepareForRuntime(
    NazaModelProfile profile, {
    void Function(double value)? onProgress,
  }) =>
      _serialize(() async {
        final encrypted = encryptedFile(profile);
        if (!await encrypted.exists()) {
          // Recover a completed, verified download if the process died
          // between download and its encryption step.
          final plain = plainFile(profile);
          if (await plain.exists() &&
              await plain.length() == profile.expectedSize &&
              _constantTimeHexEquals(
                await crypto.sha256File(plain),
                profile.expectedSha256,
              )) {
            await _encryptUnlocked(
              profile,
              removePlaintext: true,
              onProgress: onProgress,
            );
          } else {
            if (await plain.exists()) await plain.delete();
            throw StateError(
              'No encrypted model found for ${profile.label}. '
              'Download & encrypt it first.',
            );
          }
        }
        await _decryptUnlocked(profile, onProgress: onProgress);
        return plainFile(profile).path;
      });

  Future<void> secureAfterRuntime(
    NazaModelProfile profile, {
    void Function(double value)? onProgress,
  }) =>
      _serialize(() async {
        final plain = plainFile(profile);
        if (!await plain.exists()) return;
        await _encryptUnlocked(profile, removePlaintext: true, onProgress: onProgress);
      });

  Future<void> rekeyAll(
    Uint8List oldKey,
    Uint8List newKey, {
    void Function(double value)? onProgress,
  }) => _serialize(() => _rekeyAllUnlocked(oldKey, newKey, onProgress: onProgress));

  Future<void> _rekeyAllUnlocked(
    Uint8List oldKey,
    Uint8List newKey, {
    void Function(double value)? onProgress,
  }) async {
    final encryptedProfiles = <NazaModelProfile>[];
    for (final profile in nazaModelProfiles) {
      if (await encryptedFile(profile).exists()) encryptedProfiles.add(profile);
    }
    if (encryptedProfiles.isEmpty) {
      onProgress?.call(1);
      return;
    }
    for (var i = 0; i < encryptedProfiles.length; i++) {
      final profile = encryptedProfiles[i];
      final encrypted = encryptedFile(profile);
      final tempPlain = File('${plainFile(profile).path}.rekey.clear');
      final newEncrypted = File('${encrypted.path}.rekey');
      try {
        await crypto.decryptFileChunked(
          encrypted,
          tempPlain,
          oldKey,
          onProgress: (v) =>
              onProgress?.call((i + v * 0.5) / encryptedProfiles.length),
        );
        await crypto.encryptFileChunked(
          tempPlain,
          newEncrypted,
          newKey,
          onProgress: (v) => onProgress?.call(
            (i + 0.5 + v * 0.5) / encryptedProfiles.length,
          ),
        );
        final backup = File('${encrypted.path}.rekey.backup');
        if (await backup.exists()) await backup.delete();
        await encrypted.rename(backup.path);
        try {
          await newEncrypted.rename(encrypted.path);
          await backup.delete();
        } catch (_) {
          if (await encrypted.exists()) await encrypted.delete();
          if (await backup.exists()) await backup.rename(encrypted.path);
          rethrow;
        }
      } finally {
        if (await tempPlain.exists()) await tempPlain.delete();
        if (await newEncrypted.exists()) await newEncrypted.delete();
      }
    }
    onProgress?.call(1);
  }
}
