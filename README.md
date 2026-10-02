# ByebyeCJ

Experimental / Research Project

ByebyeCJ is a small embedded storage engine for Dart applications with a page-based file layout, a serializer abstraction, and a clean separation between storage primitives and the public database API. The project is designed to be useful for embedded or local-first workloads while staying intentionally small enough to be understood, tested, and extended incrementally.

## What is ByebyeCJ?

This package aims to provide a realistic database-like core without forcing applications to depend on a heavyweight external engine. The storage layer is built around fixed-size pages, a collection-oriented record model, and explicit persistence boundaries.

## Why another storage engine?

The goal is not to replace SQLite or Hive. The goal is to provide a small, learnable foundation that makes database concepts such as storage layout, page-oriented persistence, corruption checks, and recovery thinking concrete in Dart.

## Architecture

The initial architecture follows a layered design:

```text
ByebyeCJ
├── Public API
├── Record Store
├── File Page Manager
├── Page Model
├── Json Serializer
├── Storage Exceptions
├── Future phases: WAL, recovery, transactions, locking, indexes
└── Query layer
```

This Phase 1 implementation focuses on the core correctness needed to persist collections safely and reopen them later without losing records.

## Features

- Page-based storage file layout
- Fixed page size for deterministic persistence
- Collection records persisted to disk
- Map-based serializer for deterministic encoding
- Corruption checks via checksum validation
- Reopen-safe storage behavior
- Transaction wrapper with commit/rollback semantics
- Basic metrics object for future observability

## Installation

```bash
dart pub add byebyecj
```

## Quick start

```dart
import 'package:byebyecj/byebyecj.dart';

Future<void> main() async {
  final db = await ByebyeCJ.open('app.db');

  await db.put('users', '123', {
    'name': 'Hakan',
    'age': 20,
  });

  final user = await db.get('users', '123');
  print(user);

  await db.close();
}
```

## Transactions

The Phase 1 API exposes a transaction abstraction with commit and rollback semantics for grouped writes:

```dart
await db.transaction((tx) async {
  await tx.put('users', '123', {'name': 'Hakan'});
  await tx.put('accounts', 'a1', {'balance': 100});
});
```

## Limitations

This is not a production-grade database engine yet. Important future work includes:

- WAL-based crash-safe write ordering
- true page allocation and free lists
- multi-page records and larger datasets
- concurrency locks and deadlock detection
- B-tree or ordered index structures
- full query planner and query predicates
- benchmark and example app expansion

## Roadmap

### Phase 1

- package setup
- public API
- storage abstraction
- page manager
- basic serialization
- basic put/get/delete

### Future phases

- buffer pool and page cache
- WAL and crash recovery
- transactions and locking
- indexes and query planning
- benchmarks and Flutter demo app

## Benchmark

A lightweight command-line benchmark is included to measure real insert and lookup throughput on the current engine.

```bash
dart run tool/benchmark.dart -- --operations 2000
dart run tool/benchmark.dart -- --write-operations 2000 --read-operations 2000 --index-operations 250 --full-scan-operations 50 --compaction-runs 2 --output-csv benchmark.csv --output-json benchmark.json
```

This script creates a temporary database, seeds representative records, and reports:

- write throughput
- point-read throughput
- indexed query throughput
- full-scan throughput
- compaction throughput
- relative index-vs-full-scan speedup

The output is formatted as a compact table for quick comparison during tuning and benchmarking, and it can optionally export the same result set as CSV and JSON for reporting or CI pipelines.

## Testing

The current validation suite covers the Phase 1 storage contract:

- put/get/update/delete
- query behavior
- reopen persistence

Run it with:

```bash
dart test
```

## Contributing

Contributions are welcome for the next storage-engine phases, especially for WAL, locking, crash recovery, and indexing.

## License

This project is available under the MIT license unless otherwise noted in the repository.
