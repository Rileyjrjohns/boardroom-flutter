import 'dart:async';

import 'package:drift/drift.dart';

// Test support, not production code: a wrapper of the executor of drift that
// fails when the test says so, to check that the adapters turn a storage
// failure into the error of their port and leave the data as it was.

/// A statement that adds data: what a full disk refuses, while it can still
/// free space.
final RegExp _addsData = RegExp(
  r'^\s*(INSERT|UPDATE|REPLACE)\b',
  caseSensitive: false,
);

/// The failure of a statement the test asked to fail.
final class DatabaseFailure implements Exception {
  /// Creates the failure, described by [message].
  const new(this.message);

  /// What went wrong, for the test log.
  final String message;

  @override
  String toString() => 'DatabaseFailure($message)';
}

/// Makes the statements of a database fail or hang. Install it with
/// `executor.interceptWith(faults)`: every statement and every start of a
/// transaction goes through it. What the migrations send when the database
/// opens does not (the faults are for the adapters).
final class DatabaseFaults extends QueryInterceptor {
  int _failures = 0;
  int _rollbackFailures = 0;
  bool _addingDataFails = false;
  RegExp? _failingStatements;
  bool _hanging = false;

  /// How many statements were sent, failed ones included.
  int statements = 0;

  /// How many times the database was closed.
  int closes = 0;

  /// The next [count] statements fail, whatever they are, then it works again.
  // ignore: use_setters_to_change_properties, a switch of the test.
  void failNext([int count = 1]) {
    _failures = count;
  }

  /// The next [count] rollbacks fail.
  // ignore: use_setters_to_change_properties, a switch of the test.
  void failNextRollback([int count = 1]) {
    _rollbackFailures = count;
  }

  /// While set, the statements that add data (insert, update, replace) fail,
  /// and the others work: a full disk.
  // A switch of the test, like `failWhileAddingData` of the JavaScript helper.
  // ignore: avoid_positional_boolean_parameters, use_setters_to_change_properties
  void failWhileAddingData(bool failing) {
    _addingDataFails = failing;
  }

  /// While set to a pattern, the statements that match it fail and the others
  /// work. `null` lets them all work again.
  // A switch of the test.
  // ignore: use_setters_to_change_properties
  void failWhileMatching(RegExp? pattern) {
    _failingStatements = pattern;
  }

  /// While set, no statement ever answers.
  // A switch of the test, like `hang` of the JavaScript helper.
  // ignore: avoid_positional_boolean_parameters, use_setters_to_change_properties
  void hang(bool hanging) {
    _hanging = hanging;
  }

  Future<T> _guard<T>(String sql, Future<T> Function() send) {
    statements += 1;
    if (_hanging) {
      return Completer<T>().future;
    }
    if (_failures > 0) {
      _failures -= 1;
      return Future<T>.error(const DatabaseFailure('the database failed'));
    }
    if (_addingDataFails && _addsData.hasMatch(sql)) {
      return Future<T>.error(const DatabaseFailure('the disk is full'));
    }
    if (_failingStatements?.hasMatch(sql) ?? false) {
      return Future<T>.error(const DatabaseFailure('the statement is refused'));
    }
    return send();
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _guard(statement, () => super.runSelect(executor, statement, args));

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _guard(statement, () => super.runInsert(executor, statement, args));

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _guard(statement, () => super.runUpdate(executor, statement, args));

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _guard(statement, () => super.runDelete(executor, statement, args));

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _guard(statement, () => super.runCustom(executor, statement, args));

  /// The start of a transaction is the `BEGIN` it sends: it counts as a
  /// statement.
  @override
  Future<bool> ensureOpen(QueryExecutor executor, QueryExecutorUser user) {
    if (executor is TransactionExecutor) {
      return _guard('BEGIN', () => super.ensureOpen(executor, user));
    }
    return super.ensureOpen(executor, user);
  }

  /// The `COMMIT` is a statement too.
  @override
  Future<void> commitTransaction(TransactionExecutor inner) =>
      _guard('COMMIT', () => super.commitTransaction(inner));

  @override
  Future<void> rollbackTransaction(TransactionExecutor inner) {
    if (_rollbackFailures > 0) {
      _rollbackFailures -= 1;
      return Future<void>.error(const DatabaseFailure('the rollback failed'));
    }
    return super.rollbackTransaction(inner);
  }

  @override
  Future<void> close(QueryExecutor inner) {
    closes += 1;
    return super.close(inner);
  }
}
