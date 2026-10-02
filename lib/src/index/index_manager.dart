import 'dart:convert';
import 'dart:io';

import '../storage/record_store.dart';

class IndexManager {
  IndexManager({required String path}) : _indexPath = '$path.indexes';

  final String _indexPath;
  final Map<String, Map<String, Map<String, Set<String>>>> _indexes = {};
  final Map<String, Set<String>> _definitions = {};

  Future<void> load() async {
    _definitions.clear();
    _indexes.clear();

    final file = File(_indexPath);
    if (!await file.exists()) {
      return;
    }

    final content = await file.readAsString();
    if (content.trim().isEmpty) {
      return;
    }

    final decoded = jsonDecode(content);
    if (decoded is! Map) {
      return;
    }

    for (final entry in decoded.entries) {
      final collection = entry.key.toString();
      final fieldMap = entry.value;
      if (fieldMap is! Map) {
        continue;
      }

      final fieldSet = <String>{};
      for (final fieldEntry in fieldMap.keys) {
        fieldSet.add(fieldEntry.toString());
      }
      _definitions[collection] = fieldSet;
    }
  }

  Future<void> save() async {
    final payload = <String, Map<String, dynamic>>{
      for (final entry in _definitions.entries)
        entry.key: {
          for (final field in entry.value) field: true,
        },
    };

    final file = File(_indexPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(payload));
  }

  Future<void> createIndex(RecordStore store, String collection, String field) async {
    final fieldSet = _definitions.putIfAbsent(collection, () => <String>{});
    fieldSet.add(field);

    final collectionIndexes = _indexes.putIfAbsent(
      collection,
      () => <String, Map<String, Set<String>>>{},
    );
    collectionIndexes.putIfAbsent(field, () => <String, Set<String>>{});

    await _rebuildCollectionIndex(store, collection, field);
    await save();
  }

  Future<void> rebuildFrom(RecordStore store) async {
    _indexes.clear();

    for (final collection in _definitions.keys) {
      final fields = _definitions[collection]!;
      for (final field in fields) {
        final collectionIndexes = _indexes.putIfAbsent(
          collection,
          () => <String, Map<String, Set<String>>>{},
        );
        collectionIndexes.putIfAbsent(field, () => <String, Set<String>>{});
        await _rebuildCollectionIndex(store, collection, field);
      }
    }
  }

  void recordWritten(
    String collection,
    String key,
    Map<String, dynamic> record,
  ) {
    final collectionIndexes = _indexes[collection];
    if (collectionIndexes == null) {
      return;
    }

    for (final fieldEntry in collectionIndexes.entries) {
      final field = fieldEntry.key;
      final fieldIndex = fieldEntry.value;
      final value = record[field];
      if (value == null) {
        continue;
      }

      final normalized = _normalize(value);
      fieldIndex.putIfAbsent(normalized, () => <String>{});
      fieldIndex[normalized]!.add(key);
    }
  }

  void recordRemoved(
    String collection,
    String key,
    Map<String, dynamic> record,
  ) {
    final collectionIndexes = _indexes[collection];
    if (collectionIndexes == null) {
      return;
    }

    for (final fieldEntry in collectionIndexes.entries) {
      final field = fieldEntry.key;
      final fieldIndex = fieldEntry.value;
      final value = record[field];
      if (value == null) {
        continue;
      }

      final normalized = _normalize(value);
      final keys = fieldIndex[normalized];
      if (keys == null) {
        continue;
      }

      keys.remove(key);
      if (keys.isEmpty) {
        fieldIndex.remove(normalized);
      }
    }
  }

  List<String> lookup(
    String collection,
    String field,
    Object? value,
  ) {
    final fieldIndex = _indexes[collection]?[field];
    if (fieldIndex == null) {
      return const <String>[];
    }

    final normalized = _normalize(value);
    return fieldIndex[normalized]?.toList(growable: false) ?? const <String>[];
  }

  bool hasIndex(String collection, String field) {
    return _definitions[collection]?.contains(field) ?? false;
  }

  Future<void> _rebuildCollectionIndex(
    RecordStore store,
    String collection,
    String field,
  ) async {
    final collectionIndexes = _indexes.putIfAbsent(
      collection,
      () => <String, Map<String, Set<String>>>{},
    );
    final fieldIndex = collectionIndexes.putIfAbsent(field, () => <String, Set<String>>{});
    fieldIndex.clear();

    final snapshot = store.snapshot(collection);
    for (final entry in snapshot.entries) {
      final key = entry.key;
      final value = entry.value[field];
      if (value == null) {
        continue;
      }

      final normalized = _normalize(value);
      fieldIndex.putIfAbsent(normalized, () => <String>{});
      fieldIndex[normalized]!.add(key);
    }
  }

  String _normalize(Object? value) {
    return jsonEncode(value);
  }
}
