import 'dart:async';
import 'dart:io';

import 'package:byebyecj/byebyecj.dart';
import 'package:test/test.dart';

void main() {
  group('WAL and recovery', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('byebyecj_wal_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('recovery replays committed WAL entries only', () async {
      final walPath = '${tempDir.path}${Platform.pathSeparator}engine.wal';
      final wal = WalManager(path: walPath);

      await wal.append(
        WalRecord(
          lsn: 1,
          transactionId: 'tx-1',
          collection: 'users',
          key: '42',
          operation: WalOperation.insert,
          beforeImage: null,
          afterImage: {'name': 'Hakan'},
          committed: true,
        ),
      );

      await wal.append(
        WalRecord(
          lsn: 2,
          transactionId: 'tx-2',
          collection: 'users',
          key: '43',
          operation: WalOperation.delete,
          beforeImage: {'name': 'Ali'},
          afterImage: null,
          committed: false,
        ),
      );

      final recovered = <String, Map<String, dynamic>>{};
      final recovery = RecoveryManager(
        path: walPath,
        onReplay: (String collection, String key, Map<String, dynamic>? value) {
          if (value == null) {
            recovered.remove(key);
          } else {
            recovered[key] = value;
          }
        },
      );

      await recovery.recover();
      expect(recovered['42'], {'name': 'Hakan'});
      expect(recovered.containsKey('43'), isFalse);
    });

    test('transaction commit increments WAL metrics and rollback keeps state consistent', () async {
      final dbPath = '${tempDir.path}${Platform.pathSeparator}tx.db';
      final db = await ByebyeCJ.open(dbPath);

      await db.transaction((tx) async {
        await tx.put('users', '1', {'name': 'Alice'});
        await tx.put('users', '2', {'name': 'Bob'});
      });

      expect(db.metrics.transactionsCommitted, 1);
      expect(db.metrics.walRecords, greaterThanOrEqualTo(2));

      var rollbackThrown = false;
      try {
        await db.transaction((tx) async {
          await tx.put('users', '3', {'name': 'Charlie'});
          throw StateError('rollback me');
        });
      } on StateError {
        rollbackThrown = true;
      }

      expect(rollbackThrown, isTrue);
      expect(db.metrics.transactionsRolledBack, 1);
      expect(await db.get('users', '3'), isNull);

      await db.close();
    });

    test('transaction keeps locks until commit so other writers cannot interleave', () async {
      final dbPath = '${tempDir.path}${Platform.pathSeparator}tx_lock.db';
      final db = await ByebyeCJ.open(dbPath);

      final waiter = Completer<void>();
      final txResult = await db.transaction((tx) async {
        await tx.put('users', '1', {'name': 'Alice'});

        unawaited(
          db.put('users', '1', {'name': 'Mallory'}).then((_) => waiter.complete()),
        );

        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(waiter.isCompleted, isFalse);
        return 'done';
      });

      expect(txResult, 'done');
      await waiter.future;
      expect(await db.get('users', '1'), {'name': 'Mallory'});
      await db.close();
    });
  });
}
