import 'dart:convert';
import 'dart:typed_data';

import '../exceptions.dart';
import '../serialization/serializer.dart';
import 'page.dart';
import 'page_manager.dart';

class RecordStore {
  RecordStore({
    required this._pageManager,
    required this._serializer,
  });

  final PageManager _pageManager;
  final Serializer _serializer;

  final Map<String, Map<String, Map<String, dynamic>>> _collections = {};
  final Map<String, int> _collectionPages = {};

  List<String> get collections => _collections.keys.toList(growable: false);

  Future<void> load() async {
    _collections.clear();
    _collectionPages.clear();

    final loadedPages = await _pageManager.readMetadata();
    _collectionPages.addAll(loadedPages);

    for (final entry in _collectionPages.entries) {
      final records = await _readCollectionRecords(entry.key, entry.value);
      _collections[entry.key] = records;
    }
  }

  Future<void> put(
    String collection,
    String key,
    Map<String, dynamic> value,
  ) async {
    final collectionRecords = _collections.putIfAbsent(collection, () => <String, Map<String, dynamic>>{});
    collectionRecords[key] = _cloneMap(value);
    await _persistCollection(collection, collectionRecords);
  }

  Future<Map<String, dynamic>?> get(String collection, String key) async {
    final collectionRecords = _collections[collection];
    if (collectionRecords == null) {
      return null;
    }

    final record = collectionRecords[key];
    if (record == null) {
      return null;
    }

    return _cloneMap(record);
  }

  Future<void> delete(String collection, String key) async {
    final collectionRecords = _collections[collection];
    if (collectionRecords == null) {
      return;
    }

    final deleted = collectionRecords.remove(key);
    if (deleted == null) {
      return;
    }

    if (collectionRecords.isEmpty) {
      _collections.remove(collection);
      final pageId = _collectionPages.remove(collection);
      if (pageId != null) {
        await _releaseCollectionPages(pageId);
      }
      await _pageManager.writeMetadata(_collectionPages);
      return;
    }

    await _persistCollection(collection, collectionRecords);
  }

  Future<List<Map<String, dynamic>>> query(String collection) async {
    final collectionRecords = snapshot(collection);
    return collectionRecords.values.toList(growable: false);
  }

  Map<String, Map<String, dynamic>> snapshot(String collection) {
    final collectionRecords = _collections[collection];
    if (collectionRecords == null) {
      return const <String, Map<String, dynamic>>{};
    }

    final snapshot = <String, Map<String, dynamic>>{};
    for (final entry in collectionRecords.entries) {
      snapshot[entry.key] = _cloneMap(entry.value);
    }
    return snapshot;
  }

  Future<void> _persistCollection(
    String collection,
    Map<String, Map<String, dynamic>> collectionRecords,
  ) async {
    final payload = _serializer.encode({
      'collection': collection,
      'records': {
        for (final entry in collectionRecords.entries) entry.key: entry.value,
      },
    });

    final existingPageId = _collectionPages[collection];
    if (existingPageId != null) {
      await _releaseCollectionPages(existingPageId);
      _collectionPages.remove(collection);
    }

    if (payload.length <= PageManager.pageSize - PageManager.headerSize) {
      final pageId = await _pageManager.allocate();
      _collectionPages[collection] = pageId;

      final page = Page(
        id: pageId,
        type: PageType.collection,
        version: 1,
        payload: payload,
        freeSpace: PageManager.pageSize - PageManager.headerSize - payload.length,
      );

      await _pageManager.write(page);
      await _pageManager.writeMetadata(_collectionPages);
      return;
    }

    final fragmentPageIds = <int>[];
    final maxFragmentSize = PageManager.pageSize - PageManager.headerSize;
    final chunks = _chunkBySize(payload, maxFragmentSize);
    for (final chunk in chunks) {
      final pageId = await _pageManager.allocate();
      fragmentPageIds.add(pageId);
      final page = Page(
        id: pageId,
        type: PageType.collection,
        version: 1,
        payload: chunk,
        freeSpace: PageManager.pageSize - PageManager.headerSize - chunk.length,
      );
      await _pageManager.write(page);
    }

    final chainPageId = await _pageManager.allocate();
    final chainPayload = _serializer.encode({
      '__collection_chain__': true,
      'pages': fragmentPageIds,
    });
    final chainPage = Page(
      id: chainPageId,
      type: PageType.collection,
      version: 1,
      payload: chainPayload,
      freeSpace: PageManager.pageSize - PageManager.headerSize - chainPayload.length,
    );

    _collectionPages[collection] = chainPageId;
    await _pageManager.write(chainPage);
    await _pageManager.writeMetadata(_collectionPages);
  }

  Future<Map<String, Map<String, dynamic>>> _readCollectionRecords(
    String collection,
    int pageId,
  ) async {
    final page = await _pageManager.read(pageId);
    final decoded = _serializer.decode(page.payload);

    if (decoded['__collection_chain__'] == true) {
      final pageIds = decoded['pages'] as List<dynamic>? ?? const <dynamic>[];

      final buffer = StringBuffer();
      for (final value in pageIds) {
        final fragmentPage = await _pageManager.read(int.parse(value.toString()));
        buffer.write(utf8.decode(fragmentPage.payload));
      }

      return _extractRecords(
        _serializer.decode(Uint8List.fromList(utf8.encode(buffer.toString()))),
      );
    }

    return _extractRecords(decoded);
  }

  Map<String, Map<String, dynamic>> _extractRecords(dynamic decoded) {
    final rawRecords = decoded['records'];
    if (rawRecords is! Map) {
      return const <String, Map<String, dynamic>>{};
    }

    final records = <String, Map<String, dynamic>>{};
    for (final recordEntry in rawRecords.entries) {
      final current = recordEntry.value;
      if (current is Map) {
        records[recordEntry.key.toString()] = Map<String, dynamic>.from(current);
      }
    }
    return records;
  }

  Future<void> _releaseCollectionPages(int pageId) async {
    try {
      final page = await _pageManager.read(pageId);
      final decoded = _serializer.decode(page.payload);
      if (decoded['__collection_chain__'] == true) {
        final pages = decoded['pages'] as List<dynamic>? ?? const <dynamic>[];
        for (final value in pages) {
          final fragmentPageId = int.parse(value.toString());
          await _pageManager.release(fragmentPageId);
        }
      }
    } on StorageCorruptionException {
      // Ignore corrupted stale pages during replacement.
    }

    await _pageManager.release(pageId);
  }

  List<Uint8List> _chunkBySize(Uint8List payload, int maxChunkSize) {
    final chunks = <Uint8List>[];
    for (var offset = 0; offset < payload.length; offset += maxChunkSize) {
      final end = offset + maxChunkSize;
      chunks.add(payload.sublist(offset, end < payload.length ? end : payload.length));
    }
    return chunks;
  }

  Map<String, dynamic> _cloneMap(Map<String, dynamic> value) {
    final cloned = <String, dynamic>{};
    for (final entry in value.entries) {
      cloned[entry.key] = _cloneValue(entry.value);
    }
    return cloned;
  }

  dynamic _cloneValue(dynamic value) {
    if (value is Map) {
      final clone = <String, dynamic>{};
      for (final entry in value.entries) {
        clone[entry.key.toString()] = _cloneValue(entry.value);
      }
      return clone;
    }
    if (value is List) {
      return value.map(_cloneValue).toList();
    }
    return value;
  }
}
