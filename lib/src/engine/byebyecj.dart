import '../buffer/buffer_pool.dart';
import '../exceptions.dart';
import '../index/index_manager.dart';
import '../locking/lock_manager.dart';
import '../query/query_planner.dart';
import '../recovery/recovery_manager.dart';
import '../serialization/json_serializer.dart';
import '../storage/file_page_manager.dart';
import '../storage/page_manager.dart';
import '../storage/record_store.dart';
import '../wal/wal_manager.dart';
import '../wal/wal_record.dart';

class EngineMetrics {
  EngineMetrics();

  int cacheHits = 0;
  int cacheMisses = 0;
  int pagesRead = 0;
  int pagesWritten = 0;
  int transactionsCommitted = 0;
  int transactionsRolledBack = 0;
  int walRecords = 0;
}

abstract interface class Transaction {
  Future<void> put(
    String collection,
    String key,
    Map<String, dynamic> value,
  );

  Future<Map<String, dynamic>?> get(
    String collection,
    String key,
  );

  Future<void> delete(
    String collection,
    String key,
  );

  Future<void> commit();

  Future<void> rollback();

  bool get isActive;
}

class ByebyeCJ {
  ByebyeCJ._({
    required this._pageManager,
    required this._recordStore,
    required this._walManager,
    required this._bufferPool,
    required this._lockManager,
    required this._indexManager,
  });

  final PageManager _pageManager;
  final RecordStore _recordStore;
  final WalManager _walManager;
  final BufferPool _bufferPool;
  final LockManager _lockManager;
  final IndexManager _indexManager;
  final EngineMetrics _metrics = EngineMetrics();

  bool _closed = false;

  EngineMetrics get metrics => _metrics;

  BufferPool get bufferPool => _bufferPool;

  LockManager get lockManager => _lockManager;

  QueryPlanner get queryPlanner => QueryPlanner(_indexManager);

  static Future<ByebyeCJ> open(String path) async {
    final pageManager = FilePageManager(path: path);
    await pageManager.initialize();
    final serializer = const JsonSerializer();
    final recordStore = RecordStore(
      pageManager: pageManager,
      serializer: serializer,
    );
    await recordStore.load();

    final walPath = '$path.wal';
    final walManager = WalManager(path: walPath);
    final recovery = RecoveryManager(
      path: walPath,
      onReplay: (collection, key, value) async {
        if (value == null) {
          await recordStore.delete(collection, key);
        } else {
          await recordStore.put(collection, key, value);
        }
      },
    );
    await recovery.recover();

    final indexManager = IndexManager(path: path);
    await indexManager.load();
    await indexManager.rebuildFrom(recordStore);

    final bufferPool = BufferPool(pageManager: pageManager, maxPages: 64);
    final lockManager = LockManager();

    return ByebyeCJ._(
      pageManager: pageManager,
      recordStore: recordStore,
      walManager: walManager,
      bufferPool: bufferPool,
      lockManager: lockManager,
      indexManager: indexManager,
    );
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    await _indexManager.save();
    await _pageManager.flush();
    await _walManager.close();
    _closed = true;
  }

  Future<void> put(
    String collection,
    String key,
    Map<String, dynamic> value,
  ) async {
    _ensureOpen();
    final lock = await _lockManager.acquire('$collection:$key', LockMode.exclusive);
    try {
      final before = await _recordStore.get(collection, key);
      final record = WalRecord(
        lsn: _metrics.walRecords + 1,
        transactionId: 'direct',
        collection: collection,
        key: key,
        operation: before == null ? WalOperation.insert : WalOperation.update,
        beforeImage: before,
        afterImage: value,
        committed: true,
      );
      await _walManager.append(record);
      _metrics.walRecords += 1;
      await _recordStore.put(collection, key, value);
      _indexManager.recordWritten(collection, key, value);
      _metrics.pagesWritten += 1;
    } finally {
      await _lockManager.release(lock);
    }
  }

  Future<Map<String, dynamic>?> get(
    String collection,
    String key,
  ) async {
    _ensureOpen();
    final lock = await _lockManager.acquire('$collection:$key', LockMode.shared);
    try {
      final value = await _recordStore.get(collection, key);
      if (value == null) {
        _metrics.cacheMisses += 1;
        return null;
      }
      _metrics.cacheHits += 1;
      return value;
    } finally {
      await _lockManager.release(lock);
    }
  }

  Future<void> delete(
    String collection,
    String key,
  ) async {
    _ensureOpen();
    final lock = await _lockManager.acquire('$collection:$key', LockMode.exclusive);
    try {
      final before = await _recordStore.get(collection, key);
      final record = WalRecord(
        lsn: _metrics.walRecords + 1,
        transactionId: 'direct',
        collection: collection,
        key: key,
        operation: WalOperation.delete,
        beforeImage: before,
        afterImage: null,
        committed: true,
      );
      await _walManager.append(record);
      _metrics.walRecords += 1;
      await _recordStore.delete(collection, key);
      if (before != null) {
        _indexManager.recordRemoved(collection, key, before);
      }
      _metrics.pagesWritten += 1;
    } finally {
      await _lockManager.release(lock);
    }
  }

  Future<void> createIndex(String collection, String field) async {
    _ensureOpen();
    await _indexManager.createIndex(_recordStore, collection, field);
  }

  Future<void> compact() async {
    _ensureOpen();
    await _pageManager.compact();
    await _indexManager.rebuildFrom(_recordStore);
  }

  Future<List<Map<String, dynamic>>> query(String collection) async {
    _ensureOpen();
    return _recordStore.query(collection);
  }

  Future<List<Map<String, dynamic>>> queryBy(
    String collection,
    String field,
    Object? value,
  ) async {
    _ensureOpen();
    final plan = queryPlanner.plan(collection, field, value);

    if (plan.usesIndex) {
      final keys = _indexManager.lookup(collection, field, value);
      final snapshot = _recordStore.snapshot(collection);
      final recordList = <Map<String, dynamic>>[];
      for (final key in keys) {
        final record = snapshot[key];
        if (record != null) {
          recordList.add(Map<String, dynamic>.from(record));
        }
      }
      return recordList;
    }

    final rows = await _recordStore.query(collection);
    return rows
        .where((row) => row[field] == value)
        .toList(growable: false);
  }

  Future<T> transaction<T>(
    Future<T> Function(Transaction tx) action,
  ) async {
    _ensureOpen();
    final tx = _DbTransaction(this);
    try {
      final result = await action(tx);
      await tx.commit();
      _metrics.transactionsCommitted += 1;
      return result;
    } catch (error) {
      await tx.rollback();
      _metrics.transactionsRolledBack += 1;
      rethrow;
    }
  }

  void _ensureOpen() {
    if (_closed) {
      throw const ByebyeCJException('Database is closed.');
    }
  }
}

class _DbTransaction implements Transaction {
  _DbTransaction(this._database)
      : _owner = Object();

  final ByebyeCJ _database;
  final Object _owner;
  final Map<String, Map<String, dynamic>> _writes = <String, Map<String, dynamic>>{};
  final Map<String, Set<String>> _deletes = <String, Set<String>>{};
  final Map<String, LockHandle> _resourceLocks = <String, LockHandle>{};
  bool _active = true;

  @override
  bool get isActive => _active;

  Future<LockHandle> _acquireLock(String resource, LockMode mode) async {
    final lock = _resourceLocks[resource];
    if (lock != null) {
      return lock;
    }

    final acquired = await _database._lockManager.acquire(
      resource,
      mode,
      owner: _owner,
    );
    _resourceLocks[resource] = acquired;
    return acquired;
  }

  @override
  Future<void> put(
    String collection,
    String key,
    Map<String, dynamic> value,
  ) async {
    _assertActive();
    await _acquireLock('$collection:$key', LockMode.exclusive);
    _writes.putIfAbsent(collection, () => <String, dynamic>{});
    _writes[collection]![key] = Map<String, dynamic>.from(value);
    _deletes[collection]?.remove(key);
  }

  @override
  Future<Map<String, dynamic>?> get(
    String collection,
    String key,
  ) async {
    _assertActive();
    await _acquireLock('$collection:$key', LockMode.shared);
    if (_deletes[collection]?.contains(key) ?? false) {
      return null;
    }
    if (_writes[collection] != null && _writes[collection]!.containsKey(key)) {
      return Map<String, dynamic>.from(_writes[collection]![key] as Map);
    }
    return await _database._recordStore.get(collection, key);
  }

  @override
  Future<void> delete(
    String collection,
    String key,
  ) async {
    _assertActive();
    await _acquireLock('$collection:$key', LockMode.exclusive);
    _writes[collection]?.remove(key);
    _deletes.putIfAbsent(collection, () => <String>{});
    _deletes[collection]!.add(key);
  }

  @override
  Future<void> commit() async {
    if (!_active) {
      throw const ByebyeCJException('Transaction is no longer active.');
    }

    try {
      for (final entry in _deletes.entries) {
        for (final key in entry.value) {
          final before = await _database._recordStore.get(entry.key, key);
          final record = WalRecord(
            lsn: _database._metrics.walRecords + 1,
            transactionId: 'tx-${_owner.hashCode}',
            collection: entry.key,
            key: key,
            operation: WalOperation.delete,
            beforeImage: before,
            afterImage: null,
            committed: true,
          );
          await _database._walManager.append(record);
          _database._metrics.walRecords += 1;
          await _database._recordStore.delete(entry.key, key);
          if (before != null) {
            _database._indexManager.recordRemoved(entry.key, key, before);
          }
          _database._metrics.pagesWritten += 1;
        }
      }

      for (final entry in _writes.entries) {
        for (final record in entry.value.entries) {
          final value = record.value as Map<String, dynamic>;
          final before = await _database._recordStore.get(entry.key, record.key);
          final walRecord = WalRecord(
            lsn: _database._metrics.walRecords + 1,
            transactionId: 'tx-${_owner.hashCode}',
            collection: entry.key,
            key: record.key,
            operation: before == null ? WalOperation.insert : WalOperation.update,
            beforeImage: before,
            afterImage: value,
            committed: true,
          );
          await _database._walManager.append(walRecord);
          _database._metrics.walRecords += 1;
          await _database._recordStore.put(entry.key, record.key, value);
          _database._indexManager.recordWritten(entry.key, record.key, value);
          _database._metrics.pagesWritten += 1;
        }
      }
    } finally {
      _active = false;
      for (final lock in _resourceLocks.values) {
        await _database._lockManager.release(lock);
      }
      _resourceLocks.clear();
    }
  }

  @override
  Future<void> rollback() async {
    _writes.clear();
    _deletes.clear();
    _active = false;
    for (final lock in _resourceLocks.values) {
      await _database._lockManager.release(lock);
    }
    _resourceLocks.clear();
  }

  void _assertActive() {
    if (!_active) {
      throw const ByebyeCJException('Transaction is not active.');
    }
  }
}
