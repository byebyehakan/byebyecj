import 'dart:convert';
import 'dart:typed_data';

import 'serializer.dart';

class JsonSerializer implements Serializer {
  const JsonSerializer();

  @override
  Uint8List encode(Map<String, dynamic> value) {
    final json = jsonEncode(_normalize(value));
    return Uint8List.fromList(utf8.encode(json));
  }

  @override
  Map<String, dynamic> decode(Uint8List bytes) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const FormatException('Serialized payload must decode to a map.');
    }

    return Map<String, dynamic>.from(decoded);
  }

  Map<String, dynamic> _normalize(Map<String, dynamic> value) {
    final normalized = <String, dynamic>{};
    for (final entry in value.entries) {
      normalized[entry.key] = _normalizeValue(entry.value);
    }
    return normalized;
  }

  dynamic _normalizeValue(dynamic value) {
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _normalizeValue(entry.value),
      };
    }
    if (value is List) {
      return value.map(_normalizeValue).toList();
    }
    return value;
  }
}
