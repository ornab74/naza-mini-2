import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../models.dart';
import 'crypto_service.dart';

class NazaStorageService {
  NazaStorageService(this.crypto);

  final NazaCryptoService crypto;

  late Directory rootDir;
  late Directory modelsDir;
  late File encryptedDbFile;
  late File keyFile;
  late Uint8List _key;
  Future<void> _dbTail = Future<void>.value();

  Uint8List get key => Uint8List.fromList(_key);

  Future<void> initialize() async {
    rootDir = Directory(
      '${(await getApplicationSupportDirectory()).path}/naza',
    );
    modelsDir = Directory('${rootDir.path}/models');
    await modelsDir.create(recursive: true);
    encryptedDbFile = File('${rootDir.path}/scanner_history.db.aes');
    keyFile = File('${rootDir.path}/.enc_key.json');
    _key = await _readOrCreateKey();
    await _withDatabase<void>((db) {
      _ensureSchema(db);
      _putSettingIfMissing(
        db,
        'security_settings',
        SecuritySettings.defaultSettings.toJson(),
      );
      // Version 1 marks databases created before the current defaults
      // migration. The controller upgrades them to version 3 once.
      _putSettingIfMissing(db, 'security_defaults_version', 1);
      _putSettingIfMissing(db, 'selected_model_id', nazaModelProfiles.first.id);
      _putSettingIfMissing(db, 'model_selection_mode', 'entropy');
      _putSettingIfMissing(db, 'colorwheel_state', <String, Object>{
        'tick': 0,
        'digest': DateTime.now().microsecondsSinceEpoch.toRadixString(16),
      });
    });
  }

  Future<Uint8List> _readOrCreateKey() async {
    if (await keyFile.exists()) {
      final json =
          jsonDecode(await keyFile.readAsString()) as Map<String, dynamic>;
      final raw = base64Decode(json['key'] as String);
      if (raw.length != 32)
        throw const FormatException('Stored NAZA key is not 256-bit.');
      return Uint8List.fromList(raw);
    }
    final generated = crypto.generateKey();
    await persistKey(generated, mode: 'random');
    return generated;
  }

  Future<void> persistKey(
    Uint8List newKey, {
    required String mode,
    Uint8List? salt,
  }) async {
    final temp = File('${keyFile.path}.partial');
    final payload = <String, Object>{
      'version': 1,
      'mode': mode,
      'key': base64Encode(newKey),
      if (salt != null) 'salt': base64Encode(salt),
    };
    final backup = File('${keyFile.path}.backup');
    if (await temp.exists()) await temp.delete();
    if (await backup.exists()) await backup.delete();
    await temp.writeAsString(jsonEncode(payload), flush: true);
    if (await keyFile.exists()) await keyFile.rename(backup.path);
    try {
      await temp.rename(keyFile.path);
      if (await backup.exists()) await backup.delete();
      _key = Uint8List.fromList(newKey);
    } catch (_) {
      if (await keyFile.exists()) await keyFile.delete();
      if (await backup.exists()) await backup.rename(keyFile.path);
      rethrow;
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<T> _withDatabase<T>(
    T Function(Database db) action, {
    Uint8List? keyOverride,
  }) {
    return _serializeDb(
      () => _withDatabaseUnlocked(action, keyOverride: keyOverride),
    );
  }

  Future<T> _serializeDb<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _dbTail = _dbTail.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<T> _withDatabaseUnlocked<T>(
    T Function(Database db) action, {
    Uint8List? keyOverride,
  }) async {
    final useKey = keyOverride ?? _key;
    final tempDir = await getTemporaryDirectory();
    final temp = File(
      '${tempDir.path}/naza_${DateTime.now().microsecondsSinceEpoch}.db',
    );
    final partial = File('${encryptedDbFile.path}.partial');
    Database? db;
    try {
      if (await encryptedDbFile.exists() &&
          await encryptedDbFile.length() > 0) {
        final decrypted = await crypto.decryptBytes(
          await encryptedDbFile.readAsBytes(),
          useKey,
        );
        await temp.writeAsBytes(decrypted, flush: true);
      }

      db = sqlite3.open(temp.path);
      _ensureSchema(db);
      final result = action(db);
      db.dispose();
      db = null;

      final clear = await temp.readAsBytes();
      final encrypted = await crypto.encryptBytes(clear, useKey);
      await partial.writeAsBytes(encrypted, flush: true);
      final backup = File('${encryptedDbFile.path}.backup');
      if (await backup.exists()) await backup.delete();
      if (await encryptedDbFile.exists())
        await encryptedDbFile.rename(backup.path);
      try {
        await partial.rename(encryptedDbFile.path);
        if (await backup.exists()) await backup.delete();
      } catch (_) {
        if (await encryptedDbFile.exists()) await encryptedDbFile.delete();
        if (await backup.exists()) await backup.rename(encryptedDbFile.path);
        rethrow;
      }
      return result;
    } finally {
      db?.dispose();
      if (await temp.exists()) await temp.delete();
      if (await partial.exists()) await partial.delete();
    }
  }

  void _ensureSchema(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS scan_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        location TEXT NOT NULL,
        classification TEXT NOT NULL,
        model TEXT NOT NULL,
        generator TEXT NOT NULL,
        details_json TEXT NOT NULL
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  void _putSettingIfMissing(Database db, String key, Object value) {
    db.execute(
      'INSERT OR IGNORE INTO app_settings (key,value,updated_at) VALUES (?,?,?)',
      [key, jsonEncode(value), DateTime.now().toIso8601String()],
    );
  }

  Future<Object?> readSetting(String key) => _withDatabase<Object?>((db) {
    final rows = db.select(
      'SELECT value FROM app_settings WHERE key = ? LIMIT 1',
      [key],
    );
    if (rows.isEmpty) return null;
    return jsonDecode(rows.first['value'] as String);
  });

  Future<void> writeSetting(String key, Object value) =>
      _withDatabase<void>((db) {
        db.execute(
          '''INSERT INTO app_settings(key,value,updated_at) VALUES (?,?,?)
             ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at''',
          [key, jsonEncode(value), DateTime.now().toIso8601String()],
        );
      });

  Future<SecuritySettings> readSecuritySettings() async {
    final raw = await readSetting('security_settings');
    if (raw is Map<String, dynamic>) return SecuritySettings.fromJson(raw);
    if (raw is Map)
      return SecuritySettings.fromJson(raw.cast<String, dynamic>());
    return const SecuritySettings();
  }

  Future<void> writeSecuritySettings(SecuritySettings settings) =>
      writeSetting('security_settings', settings.normalized().toJson());

  Future<String> readSelectedModelId() async =>
      (await readSetting('selected_model_id') as String?) ??
      nazaModelProfiles.first.id;

  Future<void> writeSelectedModelId(String id) =>
      writeSetting('selected_model_id', id);

  Future<String> readSelectionMode() async =>
      (await readSetting('model_selection_mode') as String?) == 'fixed'
      ? 'fixed'
      : 'entropy';

  Future<void> writeSelectionMode(String mode) => writeSetting(
    'model_selection_mode',
    mode == 'fixed' ? 'fixed' : 'entropy',
  );

  Future<void> addScanResult(RoadScanResult result) => _withDatabase<void>((
    db,
  ) {
    db.execute(
      'INSERT INTO scan_history(timestamp,location,classification,model,generator,details_json) VALUES (?,?,?,?,?,?)',
      [
        DateTime.now().toIso8601String(),
        result.location,
        result.classification,
        result.model,
        result.generator,
        jsonEncode(result.toJson()),
      ],
    );
  });

  Future<List<ScanHistoryEntry>> fetchScanHistory({
    int limit = 10,
    int offset = 0,
    String? search,
  }) {
    return _withDatabase<List<ScanHistoryEntry>>((db) {
      final ResultSet rows;
      if (search != null && search.trim().isNotEmpty) {
        final q = '%${search.trim()}%';
        rows = db.select(
          'SELECT id,timestamp,location,classification,model,generator,details_json FROM scan_history WHERE location LIKE ? OR classification LIKE ? OR model LIKE ? ORDER BY id DESC LIMIT ? OFFSET ?',
          [q, q, q, limit, offset],
        );
      } else {
        rows = db.select(
          'SELECT id,timestamp,location,classification,model,generator,details_json FROM scan_history ORDER BY id DESC LIMIT ? OFFSET ?',
          [limit, offset],
        );
      }
      return rows
          .map(
            (row) => ScanHistoryEntry(
              id: row['id'] as int,
              timestamp: row['timestamp'] as String,
              location: row['location'] as String,
              classification: row['classification'] as String,
              model: row['model'] as String,
              generator: row['generator'] as String,
              detailsJson: row['details_json'] as String,
            ),
          )
          .toList();
    });
  }

  Future<void> reencryptDatabase(Uint8List oldKey, Uint8List newKey) {
    return _serializeDb(() async {
      if (!await encryptedDbFile.exists()) return;
      final clear = await crypto.decryptBytes(
        await encryptedDbFile.readAsBytes(),
        oldKey,
      );
      final encrypted = await crypto.encryptBytes(clear, newKey);
      final partial = File('${encryptedDbFile.path}.rekey');
      final backup = File('${encryptedDbFile.path}.rekey.backup');
      if (await partial.exists()) await partial.delete();
      if (await backup.exists()) await backup.delete();
      await partial.writeAsBytes(encrypted, flush: true);
      await encryptedDbFile.rename(backup.path);
      try {
        await partial.rename(encryptedDbFile.path);
        await backup.delete();
      } catch (_) {
        if (await encryptedDbFile.exists()) await encryptedDbFile.delete();
        if (await backup.exists()) await backup.rename(encryptedDbFile.path);
        rethrow;
      } finally {
        if (await partial.exists()) await partial.delete();
      }
    });
  }
}
