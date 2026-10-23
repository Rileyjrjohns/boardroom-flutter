import 'dart:async';

import 'package:boardroom/core/infrastructure/secure_storage/secure_storage.dart';

// Test support, not production code: the secure storage of the tests, in
// memory. It can be made to fail, to hang, and to show what it holds, so that
// the logic that sits on top of it is tested.

/// A secure storage in memory.
class MemorySecureStorage implements SecureStorage {
  final Map<String, String> _items = {};
  final List<Completer<void>> _pending = [];
  int _failures = 0;
  bool _hanging = false;

  /// How many times each call was made, failed ones included.
  int getCalls = 0;

  /// How many times `set` was called.
  int setCalls = 0;

  /// How many times `remove` was called.
  int removeCalls = 0;

  /// The next [count] calls fail, then it works again.
  // ignore: use_setters_to_change_properties, a switch of the test.
  void failNext([int count = 1]) {
    _failures = count;
  }

  /// Every call waits for ever while set.
  // A switch of the test, like `hang` of the JavaScript helper.
  // ignore: avoid_positional_boolean_parameters, use_setters_to_change_properties
  void hang([bool hanging = true]) {
    _hanging = hanging;
  }

  /// The next call is held: it neither takes effect nor answers until the
  /// function returned is called, like a call to a keychain that is slow. A
  /// call that the caller gave up on, because it took too long, then lands
  /// late, which is what an operation that timed out can do.
  void Function() holdNext() {
    final released = Completer<void>();
    _pending.add(released);
    return released.complete;
  }

  /// What it holds, to see what was and was not stored.
  Map<String, String> snapshot() => Map.of(_items);

  /// Puts a value in without going through the interface.
  void seed(String key, String value) {
    _items[key] = value;
  }

  @override
  Future<String?> get(String key) {
    getCalls += 1;
    return _run(() => _items[key]);
  }

  @override
  Future<void> set(String key, String value) {
    setCalls += 1;
    return _run(() {
      _items[key] = value;
    });
  }

  @override
  Future<void> remove(String key) {
    removeCalls += 1;
    return _run(() {
      _items.remove(key);
    });
  }

  Future<T> _run<T>(T Function() operation) {
    if (_pending.isNotEmpty) {
      final gate = _pending.removeAt(0);
      return gate.future.then((_) => operation());
    }
    if (_hanging) {
      return Completer<T>().future;
    }
    if (_failures > 0) {
      _failures -= 1;
      return Future.error(StateError('the secure storage is unavailable'));
    }
    return Future.value(operation());
  }
}
