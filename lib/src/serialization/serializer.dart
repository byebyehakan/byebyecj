import 'dart:typed_data';

abstract interface class Serializer {
  const Serializer();

  Uint8List encode(Map<String, dynamic> value);

  Map<String, dynamic> decode(Uint8List bytes);
}
