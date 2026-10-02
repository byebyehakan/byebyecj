import 'dart:io';

import 'package:byebyecj/byebyecj.dart';
import 'package:test/test.dart';

void main() {
  group('Large value storage', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('byebyecj_large_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('records larger than one page are persisted and read back intact', () async {
      final dbPath = '${tempDir.path}${Platform.pathSeparator}large.db';
      final db = await ByebyeCJ.open(dbPath);

      final payload = {
        'name': 'Hakan',
        'notes': 'x' * 50000,
        'tags': List<String>.generate(500, (index) => 'tag-$index'),
      };

      await db.put('posts', 'p-1', payload);

      final roundTrip = await db.get('posts', 'p-1');
      expect(roundTrip, isNotNull);
      expect(roundTrip!['name'], 'Hakan');
      expect(roundTrip['notes'], payload['notes']);
      expect(roundTrip['tags'], payload['tags']);

      await db.close();
    });
  });
}
