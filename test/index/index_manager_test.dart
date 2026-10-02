import 'dart:io';

import 'package:byebyecj/byebyecj.dart';
import 'package:test/test.dart';

void main() {
  group('Index manager and query planner', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('byebyecj_index_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('createIndex and queryBy use the index for field lookups', () async {
      final dbPath = '${tempDir.path}${Platform.pathSeparator}indexed.db';
      final db = await ByebyeCJ.open(dbPath);

      await db.put('users', '1', {'name': 'Hakan', 'age': 20, 'status': 'active'});
      await db.put('users', '2', {'name': 'Ali', 'age': 24, 'status': 'active'});
      await db.put('users', '3', {'name': 'Veli', 'age': 30, 'status': 'inactive'});

      await db.createIndex('users', 'status');

      final activeUsers = await db.queryBy('users', 'status', 'active');
      expect(activeUsers.map((e) => e['name']), orderedEquals(['Hakan', 'Ali']));

      final plan = db.queryPlanner.plan('users', 'status', 'active');
      expect(plan.usesIndex, isTrue);

      await db.close();
    });

    test('index state rebuilds after reopen', () async {
      final dbPath = '${tempDir.path}${Platform.pathSeparator}rebuild.db';
      var db = await ByebyeCJ.open(dbPath);

      await db.put('orders', 'o-1', {'customer': 'hakan', 'total': 10});
      await db.put('orders', 'o-2', {'customer': 'ali', 'total': 20});
      await db.createIndex('orders', 'customer');
      await db.close();

      db = await ByebyeCJ.open(dbPath);
      final result = await db.queryBy('orders', 'customer', 'hakan');
      expect(result, [
        {'customer': 'hakan', 'total': 10},
      ]);

      await db.close();
    });
  });
}
