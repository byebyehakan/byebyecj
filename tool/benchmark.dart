import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:byebyecj/byebyecj.dart';

class BenchmarkResult {
  const BenchmarkResult({
    required this.scenario,
    required this.operations,
    required this.elapsedMs,
    required this.opsPerSecond,
    this.note,
  });

  final String scenario;
  final int operations;
  final int elapsedMs;
  final double opsPerSecond;
  final String? note;

  @override
  String toString() {
    final details = note == null ? '' : ' | $note';
    return '$scenario: $operations ops in ${elapsedMs}ms (${opsPerSecond.toStringAsFixed(2)} ops/s)$details';
  }
}

class BenchmarkOptions {
  const BenchmarkOptions({
    required this.writeOperations,
    required this.readOperations,
    required this.indexOperations,
    required this.fullScanOperations,
    required this.compactionRuns,
    required this.outputCsv,
    required this.outputJson,
  });

  final int writeOperations;
  final int readOperations;
  final int indexOperations;
  final int fullScanOperations;
  final int compactionRuns;
  final String? outputCsv;
  final String? outputJson;
}

BenchmarkOptions _parseOptions(List<String> args) {
  var writeOperations = 2000;
  var readOperations = 2000;
  var indexOperations = 250;
  var fullScanOperations = 50;
  var compactionRuns = 1;
  String? outputCsv;
  String? outputJson;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    final next = i + 1 < args.length ? args[i + 1] : null;

    if (arg == '--operations' && next != null) {
      final value = int.tryParse(next) ?? writeOperations;
      writeOperations = value;
      readOperations = value;
      indexOperations = max(1, value ~/ 8);
      fullScanOperations = max(1, value ~/ 40);
      i++;
      continue;
    }

    if (arg == '--write-operations' && next != null) {
      writeOperations = int.tryParse(next) ?? writeOperations;
      i++;
      continue;
    }

    if (arg == '--read-operations' && next != null) {
      readOperations = int.tryParse(next) ?? readOperations;
      i++;
      continue;
    }

    if (arg == '--index-operations' && next != null) {
      indexOperations = int.tryParse(next) ?? indexOperations;
      i++;
      continue;
    }

    if (arg == '--full-scan-operations' && next != null) {
      fullScanOperations = int.tryParse(next) ?? fullScanOperations;
      i++;
      continue;
    }

    if (arg == '--compaction-runs' && next != null) {
      compactionRuns = int.tryParse(next) ?? compactionRuns;
      i++;
      continue;
    }

    if (arg == '--output-csv' && next != null) {
      outputCsv = next;
      i++;
      continue;
    }

    if (arg == '--output-json' && next != null) {
      outputJson = next;
      i++;
      continue;
    }

    if (arg == '--help' || arg == '-h') {
      stdout.writeln(
        'Usage: dart run tool/benchmark.dart '
        '[--operations N] [--write-operations N] [--read-operations N] '
        '[--index-operations N] [--full-scan-operations N] [--compaction-runs N] '
        '[--output-csv path] [--output-json path]',
      );
      exit(0);
    }
  }

  return BenchmarkOptions(
    writeOperations: writeOperations,
    readOperations: readOperations,
    indexOperations: indexOperations,
    fullScanOperations: fullScanOperations,
    compactionRuns: compactionRuns,
    outputCsv: outputCsv,
    outputJson: outputJson,
  );
}

Future<void> _seedDataset(ByebyeCJ db, int operations) async {
  for (var i = 0; i < operations; i++) {
    await db.put('users', i.toString(), {
      'id': i,
      'role': i % 10 == 0 ? 'admin' : 'user',
      'name': 'user_$i',
      'email': 'user_$i@example.com',
      'active': i % 2 == 0,
    });
  }
}

Future<BenchmarkResult> _measureWriteThroughput(ByebyeCJ db, int operations) async {
  final stopwatch = Stopwatch()..start();

  for (var i = 0; i < operations; i++) {
    await db.put('bench_write', i.toString(), {
      'id': i,
      'role': i % 7 == 0 ? 'admin' : 'user',
      'name': 'bench_user_$i',
    });
  }

  stopwatch.stop();
  final elapsedMs = stopwatch.elapsedMilliseconds;
  final opsPerSecond = elapsedMs == 0 ? 0.0 : operations / (elapsedMs / 1000);

  return BenchmarkResult(
    scenario: 'write',
    operations: operations,
    elapsedMs: elapsedMs,
    opsPerSecond: opsPerSecond,
    note: 'insert workload',
  );
}

Future<BenchmarkResult> _measureReadThroughput(ByebyeCJ db, int operations) async {
  final stopwatch = Stopwatch()..start();

  for (var i = 0; i < operations; i++) {
    await db.get('users', (i % operations).toString());
  }

  stopwatch.stop();
  final elapsedMs = stopwatch.elapsedMilliseconds;
  final opsPerSecond = elapsedMs == 0 ? 0.0 : operations / (elapsedMs / 1000);

  return BenchmarkResult(
    scenario: 'read',
    operations: operations,
    elapsedMs: elapsedMs,
    opsPerSecond: opsPerSecond,
    note: 'point lookup',
  );
}

Future<BenchmarkResult> _measureIndexQuery(ByebyeCJ db, int operations) async {
  final stopwatch = Stopwatch()..start();

  for (var i = 0; i < operations; i++) {
    await db.queryBy('users', 'role', 'admin');
  }

  stopwatch.stop();
  final elapsedMs = stopwatch.elapsedMilliseconds;
  final opsPerSecond = elapsedMs == 0 ? 0.0 : operations / (elapsedMs / 1000);

  return BenchmarkResult(
    scenario: 'indexed-query',
    operations: operations,
    elapsedMs: elapsedMs,
    opsPerSecond: opsPerSecond,
    note: 'field index lookup',
  );
}

Future<BenchmarkResult> _measureFullScan(ByebyeCJ db, int operations) async {
  final stopwatch = Stopwatch()..start();

  for (var i = 0; i < operations; i++) {
    final rows = await db.query('users');
    final filtered = rows.where((row) => row['role'] == 'admin').toList();
    if (filtered.isEmpty) {
      throw StateError('benchmark data is missing admin records');
    }
  }

  stopwatch.stop();
  final elapsedMs = stopwatch.elapsedMilliseconds;
  final opsPerSecond = elapsedMs == 0 ? 0.0 : operations / (elapsedMs / 1000);

  return BenchmarkResult(
    scenario: 'full-scan',
    operations: operations,
    elapsedMs: elapsedMs,
    opsPerSecond: opsPerSecond,
    note: 'sequential scan + filter',
  );
}

Future<BenchmarkResult> _measureCompaction(ByebyeCJ db, int runs) async {
  final stopwatch = Stopwatch()..start();

  for (var i = 0; i < runs; i++) {
    await db.compact();
  }

  stopwatch.stop();
  final elapsedMs = stopwatch.elapsedMilliseconds;
  final opsPerSecond = elapsedMs == 0 ? 0.0 : runs / (elapsedMs / 1000);

  return BenchmarkResult(
    scenario: 'compaction',
    operations: runs,
    elapsedMs: elapsedMs,
    opsPerSecond: opsPerSecond,
    note: 'page free-list cleanup',
  );
}

void _printHeader() {
  stdout.writeln('=== ByebyeCJ benchmark report ===');
  stdout.writeln('scenario | operations | elapsed_ms | ops_per_sec | note');
}

void _printResult(BenchmarkResult result) {
  stdout.writeln(
    '${result.scenario.padRight(16)} | '
    '${result.operations.toString().padLeft(10)} | '
    '${result.elapsedMs.toString().padLeft(10)} | '
    '${result.opsPerSecond.toStringAsFixed(2).padLeft(11)} | '
    '${result.note ?? ''}',
  );
}

String _csvRow(BenchmarkResult result) {
  final values = <String>[
    result.scenario,
    result.operations.toString(),
    result.elapsedMs.toString(),
    result.opsPerSecond.toStringAsFixed(2),
    result.note ?? '',
  ];
  return values.map((value) => '"${value.replaceAll('"', '""')}"').join(',');
}

Future<void> _writeCsvReport(String path, List<BenchmarkResult> results) async {
  final file = File(path);
  await file.parent.create(recursive: true);

  final buffer = StringBuffer();
  buffer.writeln('scenario,operations,elapsed_ms,ops_per_sec,note');
  for (final result in results) {
    buffer.writeln(_csvRow(result));
  }

  await file.writeAsString(buffer.toString());
}

Future<void> _writeJsonReport(String path, List<BenchmarkResult> results) async {
  final file = File(path);
  await file.parent.create(recursive: true);

  final payload = <String, dynamic>{
    'results': [
      for (final result in results)
        {
          'scenario': result.scenario,
          'operations': result.operations,
          'elapsed_ms': result.elapsedMs,
          'ops_per_sec': result.opsPerSecond,
          'note': result.note ?? '',
        },
    ],
  };

  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
}

Future<void> main(List<String> args) async {
  final options = _parseOptions(args);
  final tempDir = await Directory.systemTemp.createTemp('byebyecj_bench_');
  final dbPath = '${tempDir.path}${Platform.pathSeparator}bench.db';

  try {
    final db = await ByebyeCJ.open(dbPath);

    await db.createIndex('users', 'role');
    await _seedDataset(db, max(options.writeOperations, options.readOperations));

    _printHeader();

    final writeResult = await _measureWriteThroughput(db, options.writeOperations);
    final readResult = await _measureReadThroughput(db, options.readOperations);
    final indexResult = await _measureIndexQuery(db, options.indexOperations);
    final fullScanResult = await _measureFullScan(db, options.fullScanOperations);
    final compactionResult = await _measureCompaction(db, options.compactionRuns);
    final results = <BenchmarkResult>[
      writeResult,
      readResult,
      indexResult,
      fullScanResult,
      compactionResult,
    ];

    for (final result in results) {
      _printResult(result);
    }

    final indexVsScanRatio = fullScanResult.opsPerSecond == 0
        ? 0.0
        : indexResult.opsPerSecond / fullScanResult.opsPerSecond;
    stdout.writeln('');
    stdout.writeln('index_vs_full_scan_speedup: ${indexVsScanRatio.toStringAsFixed(2)}x');

    if (options.outputCsv != null) {
      await _writeCsvReport(options.outputCsv!, results);
      stdout.writeln('');
      stdout.writeln('CSV report written to: ${options.outputCsv}');
    }

    if (options.outputJson != null) {
      await _writeJsonReport(options.outputJson!, results);
      stdout.writeln('JSON report written to: ${options.outputJson}');
    }

    await db.close();
  } finally {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  }
}
