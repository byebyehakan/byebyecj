import 'dart:io';

import 'package:byebyecj/byebyecj.dart';
import 'package:test/test.dart';

void main() {
  group('ByebyeCJ Phase 1', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('byebyecj_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('put/get/update/delete and query work', () async {
      final dbPath = '${tempDir.path}${Platform.pathSeparator}engine.db';
      final db = await ByebyeCJ.open(dbPath);

      await db.put('users', '123', {'name': 'Hakan', 'age': 20});
      final user = await db.get('users', '123');
      expect(user, {'name': 'Hakan', 'age': 20});

      await db.put('users', '123', {'name': 'Hakan', 'age': 21});
      final updated = await db.get('users', '123');
      expect(updated, {'name': 'Hakan', 'age': 21});

      final all = await db.query('users');
      expect(all, [
        {'name': 'Hakan', 'age': 21},
      ]);

      await db.delete('users', '123');
      expect(await db.get('users', '123'), isNull);
      expect(await db.query('users'), isEmpty);

      await db.close();
    });

    test('database persists across reopen', () async {
      final dbPath = '${tempDir.path}${Platform.pathSeparator}persist.db';
      var db = await ByebyeCJ.open(dbPath);

      await db.put('users', '1', {'email': 'a@example.com', 'status': 'active'});
      await db.close();

      db = await ByebyeCJ.open(dbPath);
      final value = await db.get('users', '1');
      expect(value, {'email': 'a@example.com', 'status': 'active'});

      await db.close();
    });

    test('indexed queries remain correct after compaction', () async {
      final dbPath = '${tempDir.path}${Platform.pathSeparator}index_compact.db';
      final db = await ByebyeCJ.open(dbPath);

      await db.put('users', '1', {'name': 'Hakan', 'role': 'admin'});
      await db.put('users', '2', {'name': 'Ayşe', 'role': 'user'});
      await db.put('users', '3', {'name': 'Mert', 'role': 'admin'});
      await db.createIndex('users', 'role');

      final adminsBefore = await db.queryBy('users', 'role', 'admin');
      expect(adminsBefore.length, 2);
      expect(adminsBefore.map((row) => row['name']).toList(), containsAll(['Hakan', 'Mert']));

      await db.compact();

      final adminsAfter = await db.queryBy('users', 'role', 'admin');
      expect(adminsAfter.length, 2);
      expect(adminsAfter.map((row) => row['name']).toList(), containsAll(['Hakan', 'Mert']));

      await db.close();
    });
  });
}
