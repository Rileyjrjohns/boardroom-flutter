import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:test/test.dart';

// Support of the contract suites, which are test code: they run against the
// fakes of the application and against the real adapters, and they only use
// the public surface of the ports.

/// Expects that [change], an attempt to change a value in place, is refused.
///
/// A careless caller could change the list of a meeting, of a page or of a
/// listing it was given or handed back. The values of the domain are
/// immutable and the lists they hold are unmodifiable, so the change throws
/// and a store that holds the value cannot be harmed through it. The
/// no-aliasing checks use it to prove that nothing a caller does to a value
/// reaches what the store keeps.
void expectRefused(void Function() change) {
  expect(change, throwsUnsupportedError);
}

/// What a successful result holds, for a test that cannot go on without it.
T valueOf<T, E>(Result<T, E> result) => switch (result) {
  Ok(:final value) => value,
  Err(:final error) => throw StateError('Expected a success, got $error'),
};

/// Identifiers that break a key built by joining the parts with a separator, or
/// by normalising them: separators, quotes, a backslash, other case,
/// surrounding spaces, and the same letter written as one code point or as two.
/// The pairs are chosen so that joining two of them with a separator gives the
/// same text for two different pairs (`a|b` + `c`, and `a` + `b|c`), including
/// the pairs that swallow the name of a period: `a|upcoming|b` + `c` and `a` +
/// `b|upcoming|c`.
const List<String> trickyIds = [
  'a',
  'b',
  'a:b',
  'a|b',
  'b|c',
  'a/b',
  'a,b',
  'c',
  'b:c',
  'b/c',
  'b,c',
  'a|upcoming|b',
  'b|upcoming|c',
  '"',
  r'\',
  'a","b',
  'A',
  ' a',
  'a ',
  'café',
  'café',
];

/// What a store (a cache, the outbox) can be asked in its contract suite beyond
/// what any store can. A suite that cannot run a group because the
/// implementation has nothing to fail or nothing to reopen shows it as skipped,
/// not as passed.
base class StoreContractOptions {
  /// Creates the options.
  const new({required this.failsStatements, required this.survivesReopen});

  /// Whether the store sends statements to a storage that can fail (a
  /// database), and the harness can make the next one fail
  /// (`failNextStatement`). A store in memory has no storage to fail.
  final bool failsStatements;

  /// Whether what was stored survives the store being closed and opened again
  /// on the same storage (`reopen`). A store in memory has nothing to reopen.
  final bool survivesReopen;
}

/// A store in memory: it has no storage that can fail, and nothing that
/// survives being closed.
const StoreContractOptions inMemoryStore = StoreContractOptions(
  failsStatements: false,
  survivesReopen: false,
);

/// The code of the error a result failed with, or `null` for a success.
String? errorCodeOf<T>(Result<T, AppError> result) => switch (result) {
  Ok() => null,
  Err(:final error) => error.code,
};
