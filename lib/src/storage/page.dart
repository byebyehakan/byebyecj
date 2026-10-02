import 'dart:typed_data';

enum PageType {
  metadata(0),
  collection(1),
  unknown(-1);

  const PageType(this.code);

  final int code;

  static PageType fromCode(int code) {
    for (final type in values) {
      if (type.code == code) {
        return type;
      }
    }
    return PageType.unknown;
  }
}

class Page {
  const Page({
    required this.id,
    required this.type,
    required this.version,
    required this.payload,
    this.freeSpace = 0,
  });

  final int id;
  final PageType type;
  final int version;
  final Uint8List payload;
  final int freeSpace;

  static const int pageSize = 4096;
  static const int headerSize = 32;

  int get totalSize => pageSize;

  Page copyWith({
    int? id,
    PageType? type,
    int? version,
    Uint8List? payload,
    int? freeSpace,
  }) {
    return Page(
      id: id ?? this.id,
      type: type ?? this.type,
      version: version ?? this.version,
      payload: payload ?? this.payload,
      freeSpace: freeSpace ?? this.freeSpace,
    );
  }
}
