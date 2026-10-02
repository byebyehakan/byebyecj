import 'dart:convert';
import 'dart:io';

import 'wal_record.dart';

class WalManager {
  WalManager({required String path}) : _file = File(path);

  final File _file;
  int _nextLsn = 1;

  Future<void> append(WalRecord record) async {
    final parent = _file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    final line = '${jsonEncode(record.toJson())}\n';
    final sink = _file.openWrite(mode: FileMode.append);
    sink.write(line);
    await sink.flush();
    await sink.close();

    if (record.lsn >= _nextLsn) {
      _nextLsn = record.lsn + 1;
    }
  }

  Future<List<WalRecord>> readAll() async {
    if (!await _file.exists()) {
      return const <WalRecord>[];
    }

    final lines = await _file.readAsLines();
    final records = <WalRecord>[];
    for (final line in lines) {
      if (line.trim().isEmpty) {
        continue;
      }

      final decoded = jsonDecode(line);
      if (decoded is! Map) {
        continue;
      }

      final record = WalRecord.fromJson(Map<String, dynamic>.from(decoded));
      records.add(record);
    }
    return records;
  }

  Future<void> close() async {
    if (await _file.exists()) {
      // The log is intentionally flushed on each append. This leaves the
      // lifecycle explicit and prevents open file handles from leaking.
    }
  }
}
