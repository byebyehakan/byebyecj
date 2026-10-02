import 'package:byebyecj/byebyecj.dart';
import 'package:test/test.dart';

void main() {
  group('LockManager deadlock detection', () {
    test('throws when two owners request each other\'s locks', () async {
      final manager = LockManager();
      final ownerA = Object();
      final ownerB = Object();

      final aFirst = await manager.acquire('users', LockMode.exclusive, owner: ownerA);
      final bFirst = await manager.acquire('orders', LockMode.exclusive, owner: ownerB);

      final aTask = manager.acquire('orders', LockMode.exclusive, owner: ownerA);
      final bTask = manager.acquire('users', LockMode.exclusive, owner: ownerB);

      await expectLater(
        Future.wait([aTask, bTask], eagerError: false),
        throwsA(isA<StateError>()),
      );

      await manager.release(aFirst);
      await manager.release(bFirst);
    });
  });
}
