import '../storage/page.dart';
import '../storage/page_manager.dart';

class BufferPool {
  BufferPool({
    required this._pageManager,
    this.maxPages = 64,
  });

  final PageManager _pageManager;
  final Map<int, Page> _cache = <int, Page>{};
  final Set<int> _dirtyPages = <int>{};
  final List<int> _lruOrder = <int>[];
  final int maxPages;

  int cacheHits = 0;
  int cacheMisses = 0;
  int pagesRead = 0;
  int pagesWritten = 0;

  bool contains(int pageId) => _cache.containsKey(pageId);

  Future<Page> fetch(int pageId) async {
    final cached = _cache[pageId];
    if (cached != null) {
      cacheHits += 1;
      _touch(pageId);
      return cached;
    }

    cacheMisses += 1;
    final page = await _pageManager.read(pageId);
    pagesRead += 1;
    _cache[pageId] = page;
    _touch(pageId);
    _evictIfNeeded();
    return page;
  }

  Future<void> markDirty(int pageId) async {
    final cached = _cache[pageId];
    if (cached == null) {
      return;
    }
    _dirtyPages.add(pageId);
  }

  Future<void> flush(int pageId) async {
    final cached = _cache[pageId];
    if (cached == null) {
      return;
    }

    await _pageManager.write(cached);
    pagesWritten += 1;
    _dirtyPages.remove(pageId);
  }

  Future<void> flushAll() async {
    final ids = _cache.keys.toList();
    for (final id in ids) {
      await flush(id);
    }
  }

  void _touch(int pageId) {
    _lruOrder.remove(pageId);
    _lruOrder.add(pageId);
  }

  void _evictIfNeeded() {
    while (_cache.length > maxPages) {
      final oldest = _lruOrder.first;
      _lruOrder.removeAt(0);
      final page = _cache.remove(oldest);
      if (page == null) {
        continue;
      }
      if (_dirtyPages.contains(oldest)) {
        _pageManager.write(page);
        pagesWritten += 1;
        _dirtyPages.remove(oldest);
      }
    }
  }
}
