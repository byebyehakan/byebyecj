class ByebyeCJException implements Exception {
  const ByebyeCJException(this.message);

  final String message;

  @override
  String toString() => 'ByebyeCJException: $message';
}

class StorageCorruptionException extends ByebyeCJException {
  const StorageCorruptionException(super.message);
}

class StorageLimitExceededException extends ByebyeCJException {
  const StorageLimitExceededException(super.message);
}

class RecordNotFoundException extends ByebyeCJException {
  const RecordNotFoundException(super.message);
}
