enum WalOperation {
  insert,
  update,
  delete,
}

class WalRecord {
  WalRecord({
    required this.lsn,
    required this.transactionId,
    required this.collection,
    required this.key,
    required this.operation,
    this.beforeImage,
    this.afterImage,
    required this.committed,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().toUtc();

  final int lsn;
  final String transactionId;
  final String collection;
  final String key;
  final WalOperation operation;
  final Map<String, dynamic>? beforeImage;
  final Map<String, dynamic>? afterImage;
  final bool committed;
  final DateTime timestamp;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'lsn': lsn,
      'transactionId': transactionId,
      'collection': collection,
      'key': key,
      'operation': operation.name,
      'beforeImage': beforeImage,
      'afterImage': afterImage,
      'committed': committed,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory WalRecord.fromJson(Map<String, dynamic> json) {
    final operationName = json['operation'];
    final operation = WalOperation.values.firstWhere(
      (value) => value.name == operationName,
      orElse: () => WalOperation.insert,
    );

    return WalRecord(
      lsn: int.parse(json['lsn']?.toString() ?? '0'),
      transactionId: json['transactionId']?.toString() ?? 'unknown',
      collection: json['collection']?.toString() ?? '',
      key: json['key']?.toString() ?? '',
      operation: operation,
      beforeImage: _asMap(json['beforeImage']),
      afterImage: _asMap(json['afterImage']),
      committed: json['committed'] == true,
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '')?.toUtc(),
    );
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }
}
