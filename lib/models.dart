import 'dart:convert';

const llamaHuggingFaceUrl =
    'https://huggingface.co/tensorblock/llama3-small-GGUF/resolve/main/llama3-small-Q3_K_M.gguf';
const llamaGitHubReleaseUrl =
    'https://github.com/ornab74/naza_one_generation_ui_code/releases/download/v1/llama3-small-Q3_K_M.gguf';
const llamaPinataUrl =
    'https://silver-southern-echidna-758.mypinata.cloud/ipfs/bafybeifb3732qilucogsp7d3q4kgqewkyu2lguyhndgzv5jlbkqiptqt5a';
const llamaModelFile = 'llama3-small-Q3_K_M.gguf';
const llamaExpectedHash =
    '8e4f4856fb84bafb895f1eb08e6c03e4be613ead2d942f91561aeac742a619aa';
const llamaExpectedSize = 111454016;

enum NazaSection {
  mainMenu,
  modelManager,
  settings,
  roadScanner,
  defenseLab,
  scanHistory,
  rekey,
  exit,
}

extension NazaSectionLabel on NazaSection {
  String get label => switch (this) {
    NazaSection.mainMenu => 'Main Menu',
    NazaSection.modelManager => 'Model setup',
    NazaSection.settings => 'Settings',
    NazaSection.roadScanner => 'Scan',
    NazaSection.defenseLab => 'Advanced checks',
    NazaSection.scanHistory => 'History',
    NazaSection.rekey => 'Change encryption key',
    NazaSection.exit => 'Exit',
  };
}

class NazaModelProfile {
  const NazaModelProfile({
    required this.id,
    required this.name,
    required this.runtime,
    required this.huggingFaceUrl,
    required this.githubReleaseUrl,
    required this.pinataUrl,
    required this.expectedSize,
    required this.fileName,
    required this.expectedSha256,
  });

  final String id;
  final String name;
  final String runtime;
  final String huggingFaceUrl;
  final String githubReleaseUrl;
  final String pinataUrl;
  final int expectedSize;
  final String fileName;
  final String expectedSha256;

  String get label => '$name [$runtime]';
}

const nazaModelProfiles = <NazaModelProfile>[
  NazaModelProfile(
    id: 'llama3-small',
    name: 'Llama 3 Small GGUF',
    runtime: 'llama.cpp',
    huggingFaceUrl: llamaHuggingFaceUrl,
    githubReleaseUrl: llamaGitHubReleaseUrl,
    pinataUrl: llamaPinataUrl,
    expectedSize: llamaExpectedSize,
    fileName: llamaModelFile,
    expectedSha256: llamaExpectedHash,
  ),
];

class SecuritySettings {
  const SecuritySettings({
    this.disabledModelIds = const <String>[],
    this.defenseProfile = 'standard',
    this.defenseVoting = false,
    this.metricSamples = 5,
    this.maxDefensePasses = 3,
    this.noiseWidth = 1,
    this.jitterScale = 0.8,
    this.colorwheelEnabled = false,
    this.colorwheelSpins = 48,
    this.colorwheelRings = 8,
    this.mlTraceScramble = false,
    this.saveScanHistory = false,
  });

  static const defaultSettings = SecuritySettings();

  final List<String> disabledModelIds;
  final String defenseProfile;
  final bool defenseVoting;
  final int metricSamples;
  final int maxDefensePasses;
  final int noiseWidth;
  final double jitterScale;
  final bool colorwheelEnabled;
  final int colorwheelSpins;
  final int colorwheelRings;
  final bool mlTraceScramble;
  final bool saveScanHistory;

  static const presets = <String, Map<String, Object>>{
    'standard': {
      'metric_samples': 5,
      'max_defense_passes': 3,
      'noise_width': 1,
      'jitter_scale': 0.8,
      'defense_voting': false,
      'colorwheel_enabled': false,
      'colorwheel_spins': 48,
      'colorwheel_rings': 8,
      'ml_trace_scramble': false,
      'save_scan_history': false,
    },
    'hardened': {
      'metric_samples': 7,
      'max_defense_passes': 5,
      'noise_width': 2,
      'jitter_scale': 1.2,
      'defense_voting': true,
      'colorwheel_enabled': true,
      'colorwheel_spins': 96,
      'colorwheel_rings': 12,
      'ml_trace_scramble': true,
      'save_scan_history': false,
    },
    'maximum': {
      'metric_samples': 9,
      'max_defense_passes': 5,
      'noise_width': 3,
      'jitter_scale': 1.6,
      'defense_voting': true,
      'colorwheel_enabled': true,
      'colorwheel_spins': 144,
      'colorwheel_rings': 16,
      'ml_trace_scramble': true,
      'save_scan_history': false,
    },
  };

  bool isModelEnabled(String id) => !disabledModelIds.contains(id);

  SecuritySettings normalized() {
    final valid = nazaModelProfiles.map((e) => e.id).toSet();
    var disabled = disabledModelIds.where(valid.contains).toSet().toList();
    if (disabled.length >= nazaModelProfiles.length) {
      disabled = disabled.take(nazaModelProfiles.length - 1).toList();
    }
    final profile = presets.containsKey(defenseProfile)
        ? defenseProfile
        : 'standard';
    return copyWith(
      disabledModelIds: disabled,
      defenseProfile: profile,
      metricSamples: metricSamples.clamp(3, 13).toInt(),
      maxDefensePasses: maxDefensePasses.clamp(1, 5).toInt(),
      noiseWidth: noiseWidth.clamp(1, 4).toInt(),
      jitterScale: jitterScale.clamp(0.5, 2.0).toDouble(),
      colorwheelSpins: colorwheelSpins.clamp(16, 256).toInt(),
      colorwheelRings: colorwheelRings.clamp(6, 24).toInt(),
    );
  }

  SecuritySettings applyPreset(String name) {
    final p = presets[name] ?? presets['hardened']!;
    return copyWith(
      defenseProfile: name,
      metricSamples: p['metric_samples'] as int,
      maxDefensePasses: p['max_defense_passes'] as int,
      noiseWidth: p['noise_width'] as int,
      jitterScale: p['jitter_scale'] as double,
      defenseVoting: p['defense_voting'] as bool,
      colorwheelEnabled: p['colorwheel_enabled'] as bool,
      colorwheelSpins: p['colorwheel_spins'] as int,
      colorwheelRings: p['colorwheel_rings'] as int,
      mlTraceScramble: p['ml_trace_scramble'] as bool,
    ).normalized();
  }

  SecuritySettings copyWith({
    List<String>? disabledModelIds,
    String? defenseProfile,
    bool? defenseVoting,
    int? metricSamples,
    int? maxDefensePasses,
    int? noiseWidth,
    double? jitterScale,
    bool? colorwheelEnabled,
    int? colorwheelSpins,
    int? colorwheelRings,
    bool? mlTraceScramble,
    bool? saveScanHistory,
  }) {
    return SecuritySettings(
      disabledModelIds: disabledModelIds ?? this.disabledModelIds,
      defenseProfile: defenseProfile ?? this.defenseProfile,
      defenseVoting: defenseVoting ?? this.defenseVoting,
      metricSamples: metricSamples ?? this.metricSamples,
      maxDefensePasses: maxDefensePasses ?? this.maxDefensePasses,
      noiseWidth: noiseWidth ?? this.noiseWidth,
      jitterScale: jitterScale ?? this.jitterScale,
      colorwheelEnabled: colorwheelEnabled ?? this.colorwheelEnabled,
      colorwheelSpins: colorwheelSpins ?? this.colorwheelSpins,
      colorwheelRings: colorwheelRings ?? this.colorwheelRings,
      mlTraceScramble: mlTraceScramble ?? this.mlTraceScramble,
      saveScanHistory: saveScanHistory ?? this.saveScanHistory,
    );
  }

  Map<String, Object> toJson() => {
    'disabled_model_ids': disabledModelIds,
    'defense_profile': defenseProfile,
    'defense_voting': defenseVoting,
    'metric_samples': metricSamples,
    'max_defense_passes': maxDefensePasses,
    'noise_width': noiseWidth,
    'jitter_scale': jitterScale,
    'colorwheel_enabled': colorwheelEnabled,
    'colorwheel_spins': colorwheelSpins,
    'colorwheel_rings': colorwheelRings,
    'ml_trace_scramble': mlTraceScramble,
    'save_scan_history': saveScanHistory,
  };

  factory SecuritySettings.fromJson(Map<String, dynamic> json) {
    return SecuritySettings(
      disabledModelIds:
          (json['disabled_model_ids'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList(),
      defenseProfile: json['defense_profile'] as String? ?? 'standard',
      defenseVoting: json['defense_voting'] as bool? ?? false,
      metricSamples: (json['metric_samples'] as num?)?.toInt() ?? 5,
      maxDefensePasses: (json['max_defense_passes'] as num?)?.toInt() ?? 3,
      noiseWidth: (json['noise_width'] as num?)?.toInt() ?? 1,
      jitterScale: (json['jitter_scale'] as num?)?.toDouble() ?? 0.8,
      colorwheelEnabled: json['colorwheel_enabled'] as bool? ?? false,
      colorwheelSpins: (json['colorwheel_spins'] as num?)?.toInt() ?? 48,
      colorwheelRings: (json['colorwheel_rings'] as num?)?.toInt() ?? 8,
      mlTraceScramble: json['ml_trace_scramble'] as bool? ?? false,
      saveScanHistory: json['save_scan_history'] as bool? ?? false,
    ).normalized();
  }

  String encode() => jsonEncode(toJson());
}

class ScanHistoryEntry {
  const ScanHistoryEntry({
    required this.id,
    required this.timestamp,
    required this.location,
    required this.classification,
    required this.model,
    required this.generator,
    required this.detailsJson,
  });

  final int id;
  final String timestamp;
  final String location;
  final String classification;
  final String model;
  final String generator;
  final String detailsJson;
}

class RoadScanResult {
  const RoadScanResult({
    required this.location,
    required this.classification,
    required this.generator,
    required this.model,
    required this.votes,
    required this.multiNode,
    required this.colorwheel,
    required this.defenseCapsule,
    required this.generatedOutput,
  });

  final String location;
  final String classification;
  final String generator;
  final String model;
  final List<String> votes;
  final String multiNode;
  final String colorwheel;
  final String defenseCapsule;
  final String generatedOutput;

  Map<String, Object> toJson() => {
    'input': {'location': location},
    'result': classification,
    'generator': generator,
    'model': model,
    'defense_votes': votes,
    'multi_node': multiNode,
    'colorwheel': colorwheel,
    'defense_capsule': defenseCapsule,
    'generated_output': generatedOutput,
    'timestamp': DateTime.now().toIso8601String(),
  };
}

class DefenseSnapshot {
  const DefenseSnapshot({
    required this.capsule,
    required this.colorwheel,
    required this.interference,
    required this.multiNode,
    required this.vectorScores,
    required this.recommendations,
  });

  final String capsule;
  final String colorwheel;
  final double interference;
  final double multiNode;
  final Map<String, double> vectorScores;
  final List<String> recommendations;
}
