import 'package:byebyecj/byebyecj.dart';
import 'package:test/test.dart';

void main() {
  test('package exposes the public API', () {
    expect(ByebyeCJ.open, isNotNull);
    expect(Serializer, isNotNull);
    expect(StorageCorruptionException, isNotNull);
  });
}
