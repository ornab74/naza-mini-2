import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'services/crypto_service.dart';
import 'services/scanner_inference_service.dart';
import 'services/model_service.dart';
import 'services/storage_service.dart';

class NazaController extends ChangeNotifier {
  NazaController() : crypto = NazaCryptoService();

  final NazaCryptoService crypto;
  late final NazaStorageService storage;
  late final ModelService models;
  final ScannerInferenceService inference = ScannerInferenceService();
  final Random _random = Random.secure();

  NazaSection section = NazaSection.mainMenu;
  SecuritySettings settings = const SecuritySettings();
  NazaModelProfile selectedModel = nazaModelProfiles.first;
  String selectionMode = 'fixed';
  bool busy = false;
  double progress = 0;
  String status = 'Ready';
  String runtimeBackend = 'not loaded';
  String? loadedModelId;
  String pinataModelUrl = llamaPinataUrl;
  bool bootComplete = false;
  bool firstBootSetup = false;
  String? bootError;

  static const Duration _progressNotifyInterval = Duration(milliseconds: 100);
  DateTime _lastProgressNotify = DateTime.fromMillisecondsSinceEpoch(0);

  RoadScanResult? roadResult;
  bool roadResultSaved = false;
  DefenseSnapshot? defenseSnapshot;
  List<ScanHistoryEntry> scanHistory = <ScanHistoryEntry>[];
  int scanHistoryPage = 0;
  String? scanHistorySearch;
  static const scanHistoryPageSize = 10;

  Future<void> initialize() async {
    final stopwatch = Stopwatch()..start();
    debugPrint('[NAZA] initialize: started');
    storage = NazaStorageService(crypto);
    models = ModelService(storage, crypto);
    await storage.initialize();
    settings = await storage.readSecuritySettings();
    // Upgrade databases created with the old hardened defaults once. This
    // preserves later user changes while making existing installs match the
    // current scanner defaults.
    final defaultsVersion = await storage.readSetting(
      'security_defaults_version',
    );
    if (defaultsVersion != 3) {
      settings = SecuritySettings.defaultSettings;
      await storage.writeSecuritySettings(settings);
      await storage.writeSetting('security_defaults_version', 3);
    }
    await models.cleanupTemporaryFiles();
    // Scanner-only build: one fixed GGUF model. Legacy model-selection settings
    // are ignored so older encrypted databases migrate cleanly.
    selectionMode = 'fixed';
    selectedModel = nazaModelProfiles.first;
    await storage.writeSelectionMode('fixed');
    await storage.writeSelectedModelId(selectedModel.id);
    final storedPinata = await storage.readSetting('model_pinata_url');
    if (storedPinata is String && storedPinata.trim().isNotEmpty) {
      pinataModelUrl = storedPinata;
    } else {
      pinataModelUrl = selectedModel.pinataUrl;
      await storage.writeSetting('model_pinata_url', pinataModelUrl);
    }
    firstBootSetup = !(await models.hasEncrypted(selectedModel));
    section = NazaSection.roadScanner;
    status = firstBootSetup
        ? 'First boot: model setup required.'
        : 'Starting Road Scanner…';
    defenseSnapshot = _makeDefenseSnapshot();
    notifyListeners();
    debugPrint(
      '[NAZA] initialize: finished in ${stopwatch.elapsedMilliseconds}ms',
    );
  }

  List<NazaModelProfile> get enabledModels =>
      nazaModelProfiles.where((m) => settings.isModelEnabled(m.id)).toList();

  Future<void> bootstrap() async {
    if (bootComplete || busy) return;
    bootError = null;
    notifyListeners();
    try {
      if (!(await models.hasEncrypted(selectedModel))) {
        await _runTask('First boot: downloading verified model…', () async {
          await models.download(
            selectedModel,
            pinataUrl: pinataModelUrl,
            onProgress: _setProgressStatus,
          );
          status = 'Encrypting verified model for secure startup…';
          progress = 0;
          notifyListeners();
          await models.encrypt(selectedModel, onProgress: _setProgress);
          status = 'First-boot model setup complete.';
        });
      }
      await _loadRuntimeFor('startup');
      section = NazaSection.roadScanner;
      bootComplete = true;
      firstBootSetup = false;
      status = 'Ready. Enter your destination and scan.';
      notifyListeners();
    } catch (error) {
      bootError = error.toString();
      status = 'Startup failed: $error';
      notifyListeners();
    }
  }

  Future<void> navigate(NazaSection next) async {
    if (section == next) return;
    final previous = section;

    // Paint the destination immediately. Securing the temporary plaintext
    // model can take noticeable CPU time, so keeping the old result screen
    // visible until encryption finishes makes the app look frozen.
    section = next;
    if (next == NazaSection.defenseLab)
      defenseSnapshot = _makeDefenseSnapshot();
    notifyListeners();
    await Future<void>.delayed(Duration.zero);

    if (previous == NazaSection.roadScanner) {
      await _closeRuntimeSession();
    }
    if (next == NazaSection.scanHistory) {
      await loadScanHistory(resetPage: true);
    }
  }

  Future<void> exitApp() async {
    await _closeRuntimeSession();
    await inference.dispose();
    exit(0);
  }

  Future<void> _runTask(String label, Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    progress = 0;
    status = label;
    final stopwatch = Stopwatch()..start();
    debugPrint('[NAZA] task started: $label');
    _lastProgressNotify = DateTime.fromMillisecondsSinceEpoch(0);
    notifyListeners();
    await Future<void>.delayed(Duration.zero);
    try {
      await action();
      progress = 1;
    } catch (e) {
      status = 'Error: $e';
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
      debugPrint(
        '[NAZA] task finished in ${stopwatch.elapsedMilliseconds}ms: $label',
      );
    }
  }

  void _notifyProgress({bool force = false}) {
    final now = DateTime.now();
    if (!force &&
        now.difference(_lastProgressNotify) < _progressNotifyInterval) {
      return;
    }
    _lastProgressNotify = now;
    notifyListeners();
  }

  void _setProgress(double value) {
    progress = value.clamp(0.0, 1.0).toDouble();
    _notifyProgress(force: progress >= 1);
  }

  void _setProgressStatus(double value, String detail) {
    progress = value.clamp(0.0, 1.0).toDouble();
    status = detail;
    _notifyProgress(force: progress >= 1);
  }

  Future<void> selectModel(NazaModelProfile profile) async {
    if (!settings.isModelEnabled(profile.id)) {
      throw StateError(
        'That model is disabled in Settings. Enable it before selecting it.',
      );
    }
    selectedModel = profile;
    await storage.writeSelectedModelId(profile.id);
    status = 'Active model: ${profile.label}';
    notifyListeners();
  }

  Future<void> toggleSelectionMode() async {
    selectionMode = selectionMode == 'entropy' ? 'fixed' : 'entropy';
    await storage.writeSelectionMode(selectionMode);
    status = 'Selection mode: $selectionMode';
    notifyListeners();
  }

  Future<void> downloadActiveModel({bool encryptAfter = true}) async {
    await _runTask('Starting secure multi-host download…', () async {
      final sha = await models.download(
        selectedModel,
        pinataUrl: pinataModelUrl,
        onProgress: _setProgressStatus,
      );
      status = 'Pinned SHA-256 verified: $sha';
      if (encryptAfter) {
        status = 'Encrypting verified model with AES-256-GCM…';
        progress = 0;
        notifyListeners();
        try {
          await models.encrypt(selectedModel, onProgress: _setProgress);
        } catch (_) {
          // A failed encryption must not leave a freshly downloaded plaintext
          // model behind as durable storage.
          await models.deletePlain(selectedModel);
          rethrow;
        }
        status = 'Model verified, encrypted, and plaintext removed.';
      }
    });
  }

  Future<void> setPinataModelUrl(String value) async {
    final normalized = ModelService.normalizePinataUrl(value);
    pinataModelUrl = normalized?.toString() ?? selectedModel.pinataUrl;
    await storage.writeSetting('model_pinata_url', pinataModelUrl);
    status = normalized == null
        ? 'Pinata mirror reset to built-in IPFS mirror.'
        : 'Pinata mirror configured securely.';
    notifyListeners();
  }

  Future<String> verifyActiveModel() async {
    var result = '';
    await _runTask('Verifying ${selectedModel.name}', () async {
      final sha = await models.verify(selectedModel);
      final matches =
          sha.toLowerCase() == selectedModel.expectedSha256.toLowerCase();
      result = matches
          ? 'Hash matches expected.\n$sha'
          : 'Hash mismatch.\nExpected: ${selectedModel.expectedSha256}\nActual: $sha';
      status = matches ? 'SHA256 matches expected.' : 'SHA256 mismatch.';
    });
    return result;
  }

  Future<void> encryptActiveModel({bool removePlaintext = true}) =>
      _runTask('Encrypting ${selectedModel.name}', () async {
        await models.encrypt(
          selectedModel,
          removePlaintext: removePlaintext,
          onProgress: _setProgress,
        );
        status = 'Encrypted -> ${selectedModel.fileName}.aes';
      });

  Future<void> decryptActiveModel() =>
      _runTask('Decrypting ${selectedModel.name}', () async {
        await models.decrypt(selectedModel, onProgress: _setProgress);
        status = 'Temporary plaintext model is available.';
      });

  Future<void> deleteActivePlaintext() =>
      _runTask('Deleting plaintext model', () async {
        await models.deletePlain(selectedModel);
        status = 'Plaintext model deleted.';
      });

  Future<void> updateSettings(SecuritySettings newSettings) async {
    settings = newSettings.normalized();
    if (!settings.isModelEnabled(selectedModel.id)) {
      selectedModel = enabledModels.first;
      await storage.writeSelectedModelId(selectedModel.id);
    }
    await storage.writeSecuritySettings(settings);
    notifyListeners();
  }

  Future<void> toggleModelEnabled(
    NazaModelProfile profile,
    bool enabled,
  ) async {
    final disabled = settings.disabledModelIds.toList();
    if (enabled) {
      disabled.remove(profile.id);
    } else {
      if (enabledModels.length <= 1 && settings.isModelEnabled(profile.id)) {
        throw StateError('At least one model must stay enabled.');
      }
      if (!disabled.contains(profile.id)) disabled.add(profile.id);
    }
    await updateSettings(settings.copyWith(disabledModelIds: disabled));
  }

  Future<void> resetSettings() => updateSettings(const SecuritySettings());

  NazaModelProfile _pickRuntimeModel() => selectedModel;

  Future<NazaModelProfile> _loadRuntimeFor(String purpose) async {
    final profile = _pickRuntimeModel();
    await _runTask('Preparing $purpose with ${profile.name}', () async {
      final path = await models.prepareForRuntime(
        profile,
        onProgress: _setProgress,
      );
      status = 'Loading ${profile.runtime} runtime…';
      _notifyProgress(force: true);
      await Future<void>.delayed(Duration.zero);
      await inference.load(path);
      runtimeBackend = await inference.backendName();
      loadedModelId = profile.id;
      status = '${profile.label} loaded • backend $runtimeBackend';
    });
    return profile;
  }

  Future<void> _closeRuntimeSession() async {
    final id = loadedModelId;
    if (id == null) return;
    final profile = nazaModelProfiles.firstWhere((m) => m.id == id);
    await _runTask('Re-encrypting model and removing plaintext…', () async {
      await inference.unload();
      await models.secureAfterRuntime(profile, onProgress: _setProgress);
      loadedModelId = null;
      runtimeBackend = 'not loaded';
      status = 'Model secured.';
    });
  }

  Future<void> runRoadScan(String location, int generationMode) async {
    if (busy) return;
    final loc = location.trim().isEmpty
        ? 'unspecified location'
        : location.trim();
    final profile = loadedModelId == null
        ? await _loadRuntimeFor('road scan')
        : nazaModelProfiles.firstWhere((m) => m.id == loadedModelId);
    final snapshot = _makeDefenseSnapshot(location: loc);
    final prompt = _buildRoadScannerPrompt(loc, snapshot);
    final suggestedPasses = snapshot.multiNode >= 0.70
        ? 5
        : (snapshot.multiNode >= 0.35 ? 3 : 1);
    final passes = settings.defenseVoting
        ? min(settings.maxDefensePasses, suggestedPasses)
        : 1;
    final votes = <String>[];
    final outputs = <String>[];
    busy = true;
    status = 'Scanning with $passes defense pass${passes == 1 ? '' : 'es'}…';
    progress = 0;
    notifyListeners();
    try {
      for (var i = 0; i < passes; i++) {
        final nonce = _colorwheelMarker('defense-pass-${i + 1}');
        final passPrompt =
            '$prompt\n\n[defense_pass]\nindex=${i + 1}/$passes; nonce=$nonce; vote_privately=true\n[/defense_pass]';
        final String output;
        if (generationMode == 3) {
          output = await inference.generate(
            passPrompt,
            maxTokens: 128,
            temperature: 0.2,
          );
        } else {
          output = await _chunkedGenerate(
            passPrompt,
            useChunkdMarkers: generationMode == 1,
            maxTotalTokens: 256,
            chunkTokens: 64,
            baseTemperature: 0.18,
          );
        }
        outputs.add(output);
        votes.add(_normalizeRiskLabel(output));
        progress = (i + 1) / passes;
        notifyListeners();
      }
      final classification = _majorityRisk(votes);
      roadResult = RoadScanResult(
        location: loc,
        classification: classification,
        generator: generationMode == 3 ? 'direct' : 'chunked',
        model: profile.label,
        votes: votes,
        multiNode: 'multi_node=${snapshot.multiNode.toStringAsFixed(2)}',
        colorwheel: snapshot.colorwheel,
        defenseCapsule: snapshot.capsule,
        generatedOutput: outputs.isEmpty ? classification : outputs.first,
      );
      roadResultSaved = false;
      if (settings.saveScanHistory) {
        await storage.addScanResult(roadResult!);
        roadResultSaved = true;
        status = 'Scan complete. Saved to History.';
      } else {
        status = 'Scan complete: $classification';
      }
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<String> _chunkedGenerate(
    String prompt, {
    required bool useChunkdMarkers,
    int maxTotalTokens = 256,
    int chunkTokens = 64,
    double baseTemperature = 0.18,
  }) async {
    var assembled = '';
    var currentPrompt = prompt;
    var previousTail = '';
    final iterations = max(
      1,
      (maxTotalTokens + chunkTokens - 1) ~/ chunkTokens,
    );
    for (var i = 0; i < iterations; i++) {
      final patchedPrompt = useChunkdMarkers
          ? _applyChunkdMarkers(currentPrompt)
          : currentPrompt;
      final text = (await inference.generate(
        patchedPrompt,
        maxTokens: chunkTokens,
        temperature: baseTemperature,
      )).trim();
      if (text.isEmpty) break;

      var overlap = 0;
      final maxOverlap = min(30, min(previousTail.length, text.length));
      for (var length = maxOverlap; length > 0; length--) {
        if (previousTail.endsWith(text.substring(0, length))) {
          overlap = length;
          break;
        }
      }
      assembled += overlap == 0 ? text : text.substring(overlap);
      previousTail = assembled.length > 120
          ? assembled.substring(assembled.length - 120)
          : assembled;

      final normalized = assembled.trim();
      if (normalized.endsWith('Low') ||
          normalized.endsWith('Medium') ||
          normalized.endsWith('High'))
        break;
      if (text.split(RegExp(r'\s+')).length < max(4, chunkTokens ~/ 8)) break;
      currentPrompt = '$prompt\n\nAssistant so far:\n$assembled\n\nContinue:';
    }
    return assembled.trim();
  }

  String _buildRoadScannerPrompt(String location, DefenseSnapshot snapshot) {
    return '''You are an advanced coherent-tuned road risk classification AI trained to evaluate real-world driving scenes.
Analyze and triple-check the available environmental context and determine the overall road risk level.
Always verify current status on-site before relying on this scanner.
Your reply must be only one word: Low, Medium, or High.

[tuning]
Scene details:
Location: $location
Sensor Integrity: local_interference=${snapshot.interference.toStringAsFixed(2)}
Multi-node Surface: multi_node=${snapshot.multiNode.toStringAsFixed(2)}
Defense Capsule: ${snapshot.capsule}
Colorwheel Entropy Machine: ${snapshot.colorwheel}
[/tuning]

Follow these strict rules when forming your decision:
- Think through scene factors internally but do not show reasoning.
- Evaluate the available road location context holistically.
- Treat unstable or high-pressure local metrics as possible interference, not as proof of an external actor.
- Use only abstract runtime/device geometry. Ignore identity or protected traits.
- Always verify current status on-site; this is decision support, not a replacement for direct inspection.
- Output exactly one word with no punctuation.
- Valid outputs: Low, Medium, High.

[replytemplate]
Low | Medium | High
[/replytemplate]''';
  }

  String _applyChunkdMarkers(String prompt) {
    final hazard = <String>[
      'ice',
      'wet',
      'snow',
      'flood',
      'construction',
      'pedestrian',
      'debris',
      'animal',
      'fog',
    ];
    final lower = prompt.toLowerCase();
    final hits = hazard.where(lower.contains).take(6).toList();
    if (hits.isEmpty) return prompt;
    final markers = hits.map((t) => '<ATTN:$t:1.0>').join(' ');
    return '$prompt\n\n[CHUNKD_MARKERS] $markers';
  }

  String _normalizeRiskLabel(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('high')) return 'High';
    if (lower.contains('low')) return 'Low';
    if (lower.contains('medium')) return 'Medium';
    return 'Medium';
  }

  String _majorityRisk(List<String> labels) {
    final counts = <String, int>{'Low': 0, 'Medium': 0, 'High': 0};
    for (final label in labels) counts[label] = (counts[label] ?? 0) + 1;
    final maxCount = counts.values.fold<int>(0, (a, b) => a > b ? a : b);
    for (final label in const ['High', 'Medium', 'Low']) {
      if (counts[label] == maxCount) return label;
    }
    return 'Medium';
  }

  Future<String> exportRoadScan() async {
    final result = roadResult;
    if (result == null) throw StateError('No road scan result to export.');
    final downloads = await getDownloadsDirectory();
    final dir = downloads ?? storage.rootDir;
    final safeStamp = DateTime.now().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    final file = File('${dir.path}/road_scan_$safeStamp.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(result.toJson()),
      flush: true,
    );
    status = 'Saved ${file.path}';
    notifyListeners();
    return file.path;
  }

  Future<void> saveRoadScanAndReturn() async {
    await saveRoadScanToHistory();
    startNewRoadScan();
  }

  Future<void> saveRoadScanToHistory() async {
    final result = roadResult;
    if (result == null || roadResultSaved) return;
    await _runTask('Saving scan to History…', () async {
      if (roadResultSaved) return;
      await storage.addScanResult(result);
      roadResultSaved = true;
      status = 'Saved to History.';
    });
  }

  void startNewRoadScan() {
    roadResult = null;
    roadResultSaved = false;
    section = NazaSection.roadScanner;
    status = 'Ready. Enter your destination and scan.';
    notifyListeners();
  }

  void cancelRoadScan() => startNewRoadScan();

  DefenseSnapshot refreshDefenseLab() {
    defenseSnapshot = _makeDefenseSnapshot();
    notifyListeners();
    return defenseSnapshot!;
  }

  DefenseSnapshot _makeDefenseSnapshot({String location = 'defense lab'}) {
    final interference = _random.nextDouble() * 0.45;
    final multi = (interference * 0.55 + _random.nextDouble() * 0.35)
        .clamp(0.0, 1.0)
        .toDouble();
    final vectorScores = <String, double>{
      'timing': (multi * 0.65 + interference * 0.35).clamp(0.0, 1.0).toDouble(),
      'cache': (multi * 0.72 + _random.nextDouble() * 0.2)
          .clamp(0.0, 1.0)
          .toDouble(),
      'em_power': (multi * 0.55 + _random.nextDouble() * 0.25)
          .clamp(0.0, 1.0)
          .toDouble(),
      'acoustic_thermal': (interference * 0.7 + _random.nextDouble() * 0.2)
          .clamp(0.0, 1.0)
          .toDouble(),
      'sensor_spoofing': (multi * 0.5 + interference * 0.3)
          .clamp(0.0, 1.0)
          .toDouble(),
    };
    final recs = <String>[
      'Run randomized inference passes and majority-vote scanner labels.',
      'Keep scanner inputs about device/runtime conditions, not personal traits.',
      'Verify directly on site if conditions feel unsafe or confusing.',
    ];
    if (multi >= 0.35) {
      recs.addAll([
        'Disable nonessential radios before scanning when practical.',
        'Re-run from a quieter location if runtime diagnostics are unstable.',
      ]);
    }
    return DefenseSnapshot(
      capsule: 'defense_capsule=${_colorwheelMarker('capsule-$location')}',
      colorwheel: 'colorwheel=${_colorwheelMarker('wheel-$location')}',
      interference: interference,
      multiNode: multi,
      vectorScores: vectorScores,
      recommendations: recs,
    );
  }

  String runColorwheelTest() {
    final marker = _colorwheelMarker('settings-test');
    status = 'Colorwheel spin: $marker';
    notifyListeners();
    return marker;
  }

  String _colorwheelMarker(String purpose) {
    final bytes = List<int>.generate(12, (_) => _random.nextInt(256));
    final suffix = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${purpose.replaceAll(' ', '-')}:$suffix';
  }

  Future<void> loadScanHistory({bool resetPage = false}) async {
    if (resetPage) scanHistoryPage = 0;
    scanHistory = await storage.fetchScanHistory(
      limit: scanHistoryPageSize,
      offset: scanHistoryPage * scanHistoryPageSize,
      search: scanHistorySearch,
    );
    notifyListeners();
  }

  Future<void> setScanHistorySearch(String? query) async {
    scanHistorySearch = query?.trim().isEmpty == true ? null : query?.trim();
    scanHistoryPage = 0;
    await loadScanHistory();
  }

  Future<void> scanHistoryNext() async {
    if (scanHistory.length < scanHistoryPageSize) return;
    scanHistoryPage += 1;
    await loadScanHistory();
  }

  Future<void> scanHistoryPrevious() async {
    if (scanHistoryPage == 0) return;
    scanHistoryPage -= 1;
    await loadScanHistory();
  }

  Future<void> rekeyRandom() async {
    final newKey = crypto.generateKey();
    await _performRekey(newKey, mode: 'random');
  }

  Future<void> rekeyPassphrase(String passphrase) async {
    if (passphrase.length < 8)
      throw ArgumentError('Passphrase must be at least 8 characters.');
    final salt = crypto.randomBytes(16);
    final newKey = await crypto.derivePassphraseKey(passphrase, salt);
    await _performRekey(newKey, mode: 'passphrase-derived', salt: salt);
  }

  Future<void> _performRekey(
    Uint8List newKey, {
    required String mode,
    Uint8List? salt,
  }) async {
    await _closeRuntimeSession();
    final oldKey = storage.key;
    await _runTask('Rekeying encrypted models and database', () async {
      await models.rekeyAll(oldKey, newKey, onProgress: _setProgress);
      await storage.reencryptDatabase(oldKey, newKey);
      await storage.persistKey(newKey, mode: mode, salt: salt);
      status = 'Rekey finished. Stored assets now use the new key.';
    });
  }
}
