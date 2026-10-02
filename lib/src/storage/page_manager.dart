import 'page.dart';

abstract interface class PageManager {
  static const int pageSize = 4096;
  static const int headerSize = 32;

  Future<void> initialize();

  Future<Page> read(int pageId);

  Future<void> write(Page page);

  Future<int> allocate();

  Future<void> release(int pageId);

  Future<void> compact();

  Future<void> flush();

  Future<Map<String, int>> readMetadata();

  Future<void> writeMetadata(Map<String, int> collectionPages);
}
