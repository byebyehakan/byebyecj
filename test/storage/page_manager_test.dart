import 'dart:io';

import 'package:byebyecj/byebyecj.dart';
import 'package:test/test.dart';

void main() {
  group('Page manager free-list behavior', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('byebyecj_pages_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('release reuses freed pages before allocating new ones', () async {
      final path = '${tempDir.path}${Platform.pathSeparator}pages.db';
      final manager = FilePageManager(path: path);
      await manager.initialize();

      await manager.allocate();
      final second = await manager.allocate();
      final third = await manager.allocate();

      await manager.release(second);

      final reused = await manager.allocate();
      expect(reused, second);
      expect(await manager.allocate(), third + 1);

      expect(await manager.readMetadata(), isEmpty);
    });

    test('compact purges stale free list entries and keeps metadata consistent', () async {
      final path = '${tempDir.path}${Platform.pathSeparator}compact.db';
      final manager = FilePageManager(path: path);
      await manager.initialize();

      final first = await manager.allocate();
      final second = await manager.allocate();
      final third = await manager.allocate();

      await manager.release(first);
      await manager.release(first);
      await manager.release(second);
      await manager.compact();

      expect(await manager.allocate(), equals(third + 1));
      expect((await manager.readMetadata()).isEmpty, isTrue);
      expect(manager.freePageCount, equals(0));
    });
  });
}
