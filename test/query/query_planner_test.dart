import 'dart:io';

import 'package:byebyecj/byebyecj.dart';
import 'package:test/test.dart';

void main() {
  group('Query planner', () {
    late Directory tempDir;
    late ByebyeCJ db;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('byebyecj_query_');
      final dbPath = '${tempDir.path}${Platform.pathSeparator}planner.db';
      db = await ByebyeCJ.open(dbPath);

      await db.put('users', '1', {'id': 1, 'role': 'admin'});
      await db.put('users', '2', {'id': 2, 'role': 'user'});
      await db.put('users', '3', {'id': 3, 'role': 'user'});
      await db.put('users', '4', {'id': 4, 'role': 'user'});
      await db.createIndex('users', 'role');
    });

    tearDown(() async {
      await db.close();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('prefers indexed access when the field is selective', () async {
      final plan = db.queryPlanner.plan('users', 'role', 'admin');
      expect(plan.usesIndex, isTrue);
      expect(plan.estimatedCost, lessThan(100));
    });

    test('falls back to full scan when the field is not selective enough', () async {
      final plan = db.queryPlanner.plan('users', 'role', 'user');
      expect(plan.usesIndex, isFalse);
      expect(plan.estimatedCost, greaterThanOrEqualTo(100));
    });
  });
}
