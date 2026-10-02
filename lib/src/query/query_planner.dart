import '../index/index_manager.dart';

class QueryPlan {
  const QueryPlan({
    required this.collection,
    this.field,
    this.value,
    required this.usesIndex,
    required this.estimatedCost,
  });

  final String collection;
  final String? field;
  final Object? value;
  final bool usesIndex;
  final int estimatedCost;
}

class QueryPlanner {
  const QueryPlanner(this._indexManager);

  final IndexManager _indexManager;

  QueryPlan plan(
    String collection, [
    String? field,
    Object? value,
  ]) {
    if (field != null && _indexManager.hasIndex(collection, field)) {
      final matches = value == null ? const <String>[] : _indexManager.lookup(collection, field, value);
      final selective = value != null && matches.length <= 2;
      if (selective) {
        return QueryPlan(
          collection: collection,
          field: field,
          value: value,
          usesIndex: true,
          estimatedCost: 25 + matches.length * 5,
        );
      }

      return QueryPlan(
        collection: collection,
        field: field,
        value: value,
        usesIndex: false,
        estimatedCost: 150 + matches.length * 25,
      );
    }

    return QueryPlan(
      collection: collection,
      field: field,
      value: value,
      usesIndex: false,
      estimatedCost: 10000,
    );
  }
}
