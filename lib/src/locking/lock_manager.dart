import 'dart:async';

enum LockMode {
  shared,
  exclusive,
}

class LockHandle {
  const LockHandle({
    required this.resource,
    required this.mode,
    required this.id,
    required this.owner,
  });

  final String resource;
  final LockMode mode;
  final int id;
  final Object owner;
}

class LockManager {
  LockManager();

  final Map<String, List<LockHandle>> _heldLocks = <String, List<LockHandle>>{};
  final Map<Object, Set<String>> _waiting = <Object, Set<String>>{};
  int _nextLockId = 1;

  Future<LockHandle> acquire(
    String resource,
    LockMode mode, {
    Object? owner,
  }) async {
    final lockOwner = owner ?? Object();
    LockHandle? existing;
    for (final holder in _heldLocks[resource] ?? const <LockHandle>[]) {
      if (holder.owner == lockOwner) {
        existing = holder;
        break;
      }
    }
    if (existing != null) {
      return existing;
    }

    final lockHandle = LockHandle(
      resource: resource,
      mode: mode,
      id: _nextLockId++,
      owner: lockOwner,
    );

    while (true) {
      _detectDeadlock(lockOwner, resource);
      if (_canAcquire(resource, mode, owner: lockOwner)) {
        _heldLocks.putIfAbsent(resource, () => <LockHandle>[]);
        _heldLocks[resource]!.add(lockHandle);
        _waiting.remove(lockOwner);
        return lockHandle;
      }

      _waiting.putIfAbsent(lockOwner, () => <String>{});
      _waiting[lockOwner]!.add(resource);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<void> release(LockHandle handle) async {
    final current = _heldLocks[handle.resource];
    if (current == null) {
      return;
    }

    current.removeWhere((candidate) => candidate.id == handle.id);
    if (current.isEmpty) {
      _heldLocks.remove(handle.resource);
    }

    final ownerStillHoldsResource = _heldLocks.entries.any(
      (entry) => entry.value.any((candidate) => candidate.owner == handle.owner),
    );
    if (!ownerStillHoldsResource) {
      _waiting.remove(handle.owner);
    }
  }

  bool _canAcquire(
    String resource,
    LockMode mode, {
    required Object owner,
  }) {
    final holders = _heldLocks[resource] ?? const <LockHandle>[];
    if (holders.isEmpty) {
      return true;
    }

    final sameOwnerHolds = holders.any((holder) => holder.owner == owner);
    if (sameOwnerHolds) {
      return true;
    }

    if (mode == LockMode.shared) {
      return holders.every((holder) => holder.mode == LockMode.shared);
    }

    return false;
  }

  void _detectDeadlock(Object owner, String resource) {
    final graph = <Object, Set<Object>>{};
    for (final waitingEntry in _waiting.entries) {
      final waitingOwner = waitingEntry.key;
      final waitingResources = waitingEntry.value;
      if (waitingResources.isEmpty) {
        continue;
      }

      for (final waitingResource in waitingResources) {
        final holders = _heldLocks[waitingResource] ?? const <LockHandle>[];
        for (final holder in holders) {
          if (holder.owner == waitingOwner) {
            continue;
          }
          graph.putIfAbsent(waitingOwner, () => <Object>{});
          graph[waitingOwner]!.add(holder.owner);
        }
      }
    }

    if (graph.isEmpty) {
      return;
    }

    final visited = <Object>{};
    final recursionStack = <Object>{};
    bool hasCycle(Object current) {
      if (recursionStack.contains(current)) {
        return true;
      }
      if (visited.contains(current)) {
        return false;
      }

      visited.add(current);
      recursionStack.add(current);
      final nextNodes = graph[current] ?? const <Object>{};
      for (final next in nextNodes) {
        if (hasCycle(next)) {
          return true;
        }
      }
      recursionStack.remove(current);
      return false;
    }

    if (graph.containsKey(owner) && hasCycle(owner)) {
      throw StateError('Deadlock detected while acquiring "$resource".');
    }
  }
}
