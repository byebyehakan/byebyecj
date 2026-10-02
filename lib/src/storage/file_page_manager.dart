import 'dart:io';
import 'dart:typed_data';

import '../exceptions.dart';
import '../serialization/json_serializer.dart';
import 'page.dart';
import 'page_manager.dart';

class FilePageManager implements PageManager {
  FilePageManager({required String path}) : _file = File(path);

  final File _file;
  final JsonSerializer _serializer = const JsonSerializer();
  final List<int> _freePages = <int>[];
  int _nextPageId = 2;
  bool _initialized = false;

  int get freePageCount => _freePages.length;

  @override
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    final parent = _file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    if (!await _file.exists()) {
      final header = _buildFileHeader();
      await _file.writeAsBytes(header, flush: true);
    }

    final fileLength = await _file.length();
    if (fileLength < PageManager.headerSize) {
      await _file.writeAsBytes(_buildFileHeader(), flush: true);
    }

    _freePages.clear();
    _nextPageId = 2;
    _initialized = true;

    final metadata = await readMetadata();
    final knownPages = <int>[...metadata.values];
    knownPages.addAll(_freePages);
    if (knownPages.isNotEmpty) {
      _nextPageId = knownPages.reduce((a, b) => a > b ? a : b) + 1;
    }
  }

  @override
  Future<Page> read(int pageId) async {
    _ensureInitialized();

    final raw = await _readRawPage(pageId);
    if (raw.length != PageManager.pageSize) {
      throw const StorageCorruptionException('Page length is invalid.');
    }

    final header = ByteData.sublistView(raw, 0, PageManager.headerSize);
    final id = header.getUint32(0, Endian.little);
    final typeCode = header.getUint32(4, Endian.little);
    final version = header.getUint32(8, Endian.little);
    final freeSpace = header.getUint32(12, Endian.little);
    final payloadLength = header.getUint32(16, Endian.little);
    final storedChecksum = header.getUint32(20, Endian.little);

    if (id != pageId) {
      throw StorageCorruptionException('Page ID mismatch for page $pageId.');
    }

    final payload = raw.sublist(PageManager.headerSize, PageManager.headerSize + payloadLength);
    final actualChecksum = _checksum(payload);
    if (storedChecksum != actualChecksum) {
      throw StorageCorruptionException('Checksum mismatch for page $pageId.');
    }

    return Page(
      id: id,
      type: PageType.fromCode(typeCode),
      version: version,
      payload: payload,
      freeSpace: freeSpace,
    );
  }

  @override
  Future<void> write(Page page) async {
    _ensureInitialized();

    if (page.payload.length > PageManager.pageSize - PageManager.headerSize) {
      throw StorageLimitExceededException(
        'Page ${page.id} exceeds the maximum payload size.',
      );
    }

    final encoded = _encodePage(page);
    final offset = _offsetFor(page.id);
    final existingBytes = await _file.exists() ? await _file.readAsBytes() : <int>[];
    final requiredLength = existingBytes.length > offset + encoded.length
        ? existingBytes.length
        : offset + encoded.length;
    final nextBytes = Uint8List(requiredLength);
    if (existingBytes.isNotEmpty) {
      nextBytes.setRange(0, existingBytes.length, existingBytes);
    }
    nextBytes.setRange(offset, offset + encoded.length, encoded);
    await _file.writeAsBytes(nextBytes, flush: true);

    if (page.id >= _nextPageId) {
      _nextPageId = page.id + 1;
    }
  }

  @override
  Future<int> allocate() async {
    _ensureInitialized();
    if (_freePages.isNotEmpty) {
      final pageId = _freePages.removeLast();
      if (pageId >= _nextPageId) {
        _nextPageId = pageId + 1;
      }
      return pageId;
    }

    final allocated = _nextPageId;
    _nextPageId += 1;
    return allocated;
  }

  @override
  Future<void> release(int pageId) async {
    _ensureInitialized();
    if (pageId < 1 || _freePages.contains(pageId)) {
      return;
    }

    _freePages.add(pageId);
    _freePages.sort();
    await _persistFreePages();
  }

  @override
  Future<void> compact() async {
    _ensureInitialized();

    final uniquePages = _freePages.toSet().toList()..sort();
    _freePages.clear();
    _freePages.addAll(uniquePages);

    _freePages.clear();
    await writeMetadata(<String, int>{});
  }

  @override
  Future<void> flush() async {
    _ensureInitialized();
  }

  @override
  Future<Map<String, int>> readMetadata() async {
    _ensureInitialized();

    final fileLength = await _file.length();
    final minimumSize = _offsetFor(1) + PageManager.pageSize;
    if (fileLength < minimumSize) {
      return <String, int>{};
    }

    try {
      final metadataPage = await read(1);
      if (metadataPage.type != PageType.metadata) {
        return <String, int>{};
      }

      final decoded = _serializer.decode(metadataPage.payload);
      final rawCollections = decoded['collections'];
      if (rawCollections is! Map) {
        return <String, int>{};
      }

      final result = <String, int>{};
      final entries = rawCollections;
      for (final entry in entries.entries) {
        result[entry.key.toString()] = int.parse(entry.value.toString());
      }

      final rawFreePages = decoded['free_pages'];
      if (rawFreePages is List) {
        _freePages
          ..clear()
          ..addAll(rawFreePages.map((value) => int.parse(value.toString())));
        _freePages.sort();
      }

      return result;
    } on StorageCorruptionException {
      return <String, int>{};
    }
  }

  @override
  Future<void> writeMetadata(Map<String, int> collectionPages) async {
    _ensureInitialized();

    final payload = _serializer.encode({
      'collections': {
        for (final entry in collectionPages.entries) entry.key: entry.value,
      },
      'free_pages': _freePages.toList(growable: false),
    });

    final page = Page(
      id: 1,
      type: PageType.metadata,
      version: 1,
      payload: payload,
      freeSpace: PageManager.pageSize - PageManager.headerSize - payload.length,
    );

    await write(page);
  }

  Uint8List _buildFileHeader() {
    final header = Uint8List(PageManager.headerSize);
    final buffer = ByteData.sublistView(header);
    buffer.setUint32(0, 0x424A434A, Endian.little);
    buffer.setUint32(4, 1, Endian.little);
    buffer.setUint32(8, PageManager.pageSize, Endian.little);
    buffer.setUint32(12, 1, Endian.little);
    buffer.setUint32(16, 0, Endian.little);
    buffer.setUint32(20, 0, Endian.little);
    return header;
  }

  Uint8List _encodePage(Page page) {
    final result = Uint8List(PageManager.pageSize);
    final header = ByteData.sublistView(result, 0, PageManager.headerSize);
    header.setUint32(0, page.id, Endian.little);
    header.setUint32(4, page.type.code, Endian.little);
    header.setUint32(8, page.version, Endian.little);
    header.setUint32(12, page.freeSpace, Endian.little);
    header.setUint32(16, page.payload.length, Endian.little);
    header.setUint32(20, _checksum(page.payload), Endian.little);

    result.setRange(
      PageManager.headerSize,
      PageManager.headerSize + page.payload.length,
      page.payload,
    );

    return result;
  }

  Future<Uint8List> _readRawPage(int pageId) async {
    final offset = _offsetFor(pageId);
    final fileBytes = await _file.readAsBytes();
    final minimumLength = offset + PageManager.pageSize;
    if (fileBytes.length < minimumLength) {
      throw StorageCorruptionException('Page $pageId is missing from storage.');
    }

    return Uint8List.fromList(
      fileBytes.sublist(offset, offset + PageManager.pageSize),
    );
  }

  Future<void> _persistFreePages() async {
    final metadata = await readMetadata();
    await writeMetadata(metadata);
  }

  int _offsetFor(int pageId) {
    if (pageId <= 0) {
      return 0;
    }
    return PageManager.headerSize + ((pageId - 1) * PageManager.pageSize);
  }

  int _checksum(Uint8List payload) {
    var checksum = 0;
    for (final byte in payload) {
      checksum = (checksum + byte) & 0xFFFFFFFF;
    }
    return checksum;
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('FilePageManager has not been initialized.');
    }
  }
}
