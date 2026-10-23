import 'dart:async';
import 'dart:io';

import 'package:boardroom/infrastructure/persistence/database_opener.dart';
import 'package:boardroom/infrastructure/persistence/unlock_database.dart';
// Drift has a `DatabaseOpener` of its own, for lazily opened databases.
import 'package:drift/drift.dart' hide DatabaseOpener;

// Test support, not production code: the engine of the device (SQLite3
// MultipleCiphers, which really encrypts), watched. React Native had no cipher
// on the machine that ran the tests, and simulated the answers of SQLCipher
// (`SimulatedCipherOpener`); here the files are encrypted for real, and this
// wrapper only adds what a test needs to see and to break: the keys that were
// used, the files that were removed, the connections that were opened and
// closed, a file that stops being a database, an engine that cannot encrypt, an
// open that fails or never answers.

final RegExp _setKey = RegExp(r'''^PRAGMA key = "x'([0-9a-f]+)'"$''');

/// The first read of the file an unlock does.
const String _readSchema = 'SELECT count(*) FROM sqlite_master';

/// What is written over a file to make it something that is no database.
final List<int> _garbage = List.generate(
  4096,
  (index) => (index * 7 + 13) % 256,
);

/// What the open that was told to fail throws.
final class OpenFailure implements Exception {
  /// Creates the failure.
  const new();

  @override
  String toString() => 'unable to open database file';
}

/// An opener that forwards to another and watches it.
final class WatchedOpener implements DatabaseOpener {
  /// Creates an opener over [_inner], whose files are in [_directory]. The
  /// opens are written to [log], when there is one, as `open <name>`.
  new(this._inner, this._directory, [this.log]);

  final DatabaseOpener _inner;
  final Directory _directory;

  /// Where the opens are written, to see them in order with other events.
  final List<String>? log;

  bool _cipher = true;
  bool _opensHang = false;
  bool _removalsFail = false;
  bool _closesFail = false;
  Pattern? _failingStatements;
  Pattern? _hangingStatements;
  int _opensToFail = 0;
  final Set<int> _opensNumberedToFail = {};
  final Set<String> _unlocked = {};

  /// Every key the files were unlocked with, in order, to see what was used.
  final List<String> keysUsed = [];

  /// Every file name that was removed, in order.
  final List<String> removed = [];

  /// How many times a file was asked to be opened, failed opens included.
  int opens = 0;

  /// How many connections were opened.
  int opened = 0;

  /// How many connections were closed again (the connection itself, or the
  /// database that took it over).
  int closed = 0;

  /// Whether the engine can encrypt. Without it, a connection answers no
  /// cipher.
  // ignore: use_setters_to_change_properties, a switch of the test.
  void setCipher({required bool available}) {
    _cipher = available;
  }

  /// The next [count] opens of a file throw, like a disk that is full.
  // ignore: use_setters_to_change_properties, a switch of the test.
  void failNextOpens([int count = 1]) {
    _opensToFail = count;
  }

  /// The open that is the [number]th one of this opener (the first is 1)
  /// throws.
  void failOpenNumber(int number) {
    _opensNumberedToFail.add(number);
  }

  /// While set, no open ever answers.
  // A switch of the test, like `hang` of the other helpers.
  // ignore: avoid_positional_boolean_parameters, use_setters_to_change_properties
  void hangOpens(bool hanging) {
    _opensHang = hanging;
  }

  /// While set, removing a file throws.
  // A switch of the test.
  // ignore: avoid_positional_boolean_parameters, use_setters_to_change_properties
  void failRemovals(bool failing) {
    _removalsFail = failing;
  }

  /// While set to a pattern, the statements that match it (sent with `exec`)
  /// throw. `null` lets them all work again.
  // A switch of the test.
  // ignore: use_setters_to_change_properties
  void failStatementsMatching(Pattern? pattern) {
    _failingStatements = pattern;
  }

  /// While set to a pattern, the statements that match it (sent with `exec`)
  /// never answer. `null` lets them all work again.
  // A switch of the test.
  // ignore: use_setters_to_change_properties
  void hangStatementsMatching(Pattern? pattern) {
    _hangingStatements = pattern;
  }

  /// While set, closing a connection throws, once the connection is closed.
  // A switch of the test.
  // ignore: avoid_positional_boolean_parameters, use_setters_to_change_properties
  void failCloses(bool failing) {
    _closesFail = failing;
  }

  File _fileOf(String name) => File('${_directory.path}/$name');

  /// Whether a file of this name has been unlocked at least once and not
  /// removed.
  bool has(String name) => _unlocked.contains(name);

  /// Whether the file of this name is on the disk, to see what a reset left
  /// behind.
  bool exists(String name) => _fileOf(name).existsSync();

  /// The file is no longer a database: it is not one for any key.
  void corrupt(String name) {
    _directory.createSync(recursive: true);
    _fileOf(name).writeAsBytesSync(_garbage);
  }

  @override
  Future<EngineConnection> open(String name) async {
    log?.add('open $name');
    opens += 1;
    if (_opensHang) {
      return await Completer<EngineConnection>().future;
    }
    if (_opensToFail > 0) {
      _opensToFail -= 1;
      throw const OpenFailure();
    }
    if (_opensNumberedToFail.contains(opens)) {
      throw const OpenFailure();
    }
    opened += 1;
    return _WatchedConnection(await _inner.open(name), name, this);
  }

  @override
  Future<void> remove(String name) async {
    if (_removalsFail) {
      throw const FileSystemException('locked');
    }
    removed.add(name);
    _unlocked.remove(name);
    await _inner.remove(name);
  }
}

final class _WatchedConnection implements EngineConnection {
  const new(this._inner, this._name, this._opener);

  final EngineConnection _inner;
  final String _name;
  final WatchedOpener _opener;

  @override
  Future<void> exec(String sql) async {
    final hanging = _opener._hangingStatements;
    if (hanging != null && sql.contains(hanging)) {
      await Completer<void>().future;
    }
    final failing = _opener._failingStatements;
    if (failing != null && sql.contains(failing)) {
      throw const OpenFailure();
    }
    final key = _setKey.firstMatch(sql)?.group(1);
    if (key != null) {
      _opener.keysUsed.add(key);
    }
    await _inner.exec(sql);
  }

  @override
  Future<List<Map<String, Object?>>> all(String sql) async {
    if (sql == cipherProbe && !_opener._cipher) {
      return [];
    }
    final rows = await _inner.all(sql);
    if (sql == _readSchema) {
      _opener._unlocked.add(_name);
    }
    return rows;
  }

  @override
  Future<void> close() async {
    _opener.closed += 1;
    await _inner.close();
    if (_opener._closesFail) {
      throw const OpenFailure();
    }
  }

  @override
  QueryExecutor toExecutor() => _inner.toExecutor().interceptWith(
    _ClosesCounter(() => _opener.closed += 1),
  );
}

/// Counts the closes of the database that took a connection over.
final class _ClosesCounter extends QueryInterceptor {
  new(this._onClose);

  final void Function() _onClose;

  @override
  Future<void> close(QueryExecutor inner) {
    _onClose();
    return super.close(inner);
  }
}
