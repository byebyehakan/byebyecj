import 'dart:async';

import 'package:byebyecj/byebyecj.dart';
import 'package:test/test.dart';

void main() {
  group('LockManager', () {
    test('exclusive lock is released before the next waiter proceeds', () async {
      final manager = LockManager();
      final first = await manager.acquire('users:42', LockMode.exclusive);

      final secondFuture = manager.acquire('users:42', LockMode.exclusive);
      final secondCompleted = Completer<bool>();
      secondFuture.then((_) => secondCompleted.complete(true));

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(secondCompleted.isCompleted, isFalse);

      await manager.release(first);
      final second = await secondFuture;
      expect(second.resource, 'users:42');
      await manager.release(second);
    });

    test('shared locks are compatible with each other', () async {
      final manager = LockManager();
      final first = await manager.acquire('users:42', LockMode.shared);
      final second = await manager.acquire('users:42', LockMode.shared);

      expect(first.mode, LockMode.shared);
      expect(second.mode, LockMode.shared);

      await manager.release(first);
      await manager.release(second);
    });
  });
}
