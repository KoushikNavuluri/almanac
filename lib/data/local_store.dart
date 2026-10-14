import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../models/day_record.dart';

/// App-private JSON storage. Lives in the app's sandboxed support directory (not visible to
/// other apps, excluded from cloud backup via android:allowBackup="false").
class LocalStore {
  Directory? _dir;

  Future<Directory> _root() async {
    final existing = _dir;
    if (existing != null) return existing;
    final d = await getApplicationSupportDirectory();
    if (!await d.exists()) await d.create(recursive: true);
    _dir = d;
    return d;
  }

  Future<File> _file(String name) async => File('${(await _root()).path}/$name');

  Future<Map<String, dynamic>?> _readJson(String name) async {
    try {
      final f = await _file(name);
      if (!await f.exists()) return null;
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return null;
      final v = jsonDecode(raw);
      return v is Map<String, dynamic> ? v : null;
    } catch (e) {
      debugPrint('Almanac: could not read $name ($e)');
      return null;
    }
  }

  /// Atomic write: temp file + rename, so a crash never leaves half a file.
  Future<void> _writeJson(String name, Map<String, dynamic> data) async {
    final f = await _file(name);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename(f.path);
  }

  Future<Map<String, dynamic>?> readState() => _readJson('almanac_state.json');
  Future<void> writeState(Map<String, dynamic> s) => _writeJson('almanac_state.json', s);

  Future<List<DayRecord>> readRecords() async {
    final j = await _readJson('almanac_records.json');
    final list = (j?['records'] as List?) ?? const [];
    return list.whereType<Map>().map((m) => DayRecord.fromJson(Map<String, dynamic>.from(m))).toList();
  }

  Future<void> writeRecords(List<DayRecord> records) =>
      _writeJson('almanac_records.json', {'v': 1, 'records': records.map((r) => r.toJson()).toList()});

  Future<void> wipe() async {
    for (final name in ['almanac_state.json', 'almanac_records.json']) {
      final f = await _file(name);
      if (await f.exists()) await f.delete();
    }
  }
}

/// The Gemini API key lives only in the Android Keystore-backed secure storage.
class KeyVault {
  static const _keyName = 'almanac.gemini_api_key';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<String?> read() async {
    try {
      return await _storage.read(key: _keyName);
    } catch (e) {
      debugPrint('Almanac: secure storage read failed ($e)');
      return null;
    }
  }

  Future<void> write(String key) => _storage.write(key: _keyName, value: key);

  Future<void> delete() async {
    try {
      await _storage.delete(key: _keyName);
    } catch (_) {}
  }
}
