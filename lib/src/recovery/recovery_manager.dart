import 'dart:async';

import '../wal/wal_manager.dart';
import '../wal/wal_record.dart';

class RecoveryManager {
  RecoveryManager({
    required String path,
    required this.onReplay,
  }) : _walManager = WalManager(path: path);

  final WalManager _walManager;
  final FutureOr<void> Function(String collection, String key, Map<String, dynamic>? value) onReplay;

  Future<void> recover() async {
    final records = await _walManager.readAll();
    for (final record in records) {
      if (!record.committed) {
        continue;
      }

      if (record.operation == WalOperation.delete) {
        final result = onReplay(record.collection, record.key, null);
        if (result is Future) {
          await result;
        }
      } else {
        final result = onReplay(
          record.collection,
          record.key,
          record.afterImage ?? record.beforeImage,
        );
        if (result is Future) {
          await result;
        }
      }
    }
  }
}
