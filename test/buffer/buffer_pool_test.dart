import 'dart:io';
import 'dart:typed_data';

import 'package:byebyecj/byebyecj.dart';
import 'package:test/test.dart';

void main() {
  group('BufferPool', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('byebyecj_buffer_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('evicts least recently used pages once the cache limit is reached', () async {
      final dbPath = '${tempDir.path}${Platform.pathSeparator}buffer.db';
      final pageManager = FilePageManager(path: dbPath);
      await pageManager.initialize();

      final pool = BufferPool(
        pageManager: pageManager,
        maxPages: 2,
      );

      final page1 = Page(
        id: 2,
        type: PageType.collection,
        version: 1,
        payload: Uint8List.fromList([1, 2, 3]),
      );
      final page2 = Page(
        id: 3,
        type: PageType.collection,
        version: 1,
        payload: Uint8List.fromList([4, 5, 6]),
      );
      final page3 = Page(
        id: 4,
        type: PageType.collection,
        version: 1,
        payload: Uint8List.fromList([7, 8, 9]),
      );

      await pageManager.write(page1);
      await pageManager.write(page2);
      await pageManager.write(page3);

      final first = await pool.fetch(2);
      final second = await pool.fetch(3);
      final third = await pool.fetch(4);

      expect(first.id, 2);
      expect(second.id, 3);
      expect(third.id, 4);
      expect(pool.contains(2), isFalse);
      expect(pool.contains(4), isTrue);

      await pool.flushAll();
    });
  });
}
