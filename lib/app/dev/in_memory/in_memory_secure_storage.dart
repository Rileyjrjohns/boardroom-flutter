import 'package:boardroom/core/infrastructure/secure_storage/secure_storage.dart';

/// The secure storage of the development configuration: a map in memory. The
/// session of the simulated server is kept here, by the same `SessionVault` the
/// real configuration puts over the keychain, and it is forgotten when the app
/// stops, like the caches of that configuration. It protects nothing, and does
/// not need to: nothing it holds is real.
final class InMemorySecureStorage implements SecureStorage {
  final Map<String, String> _items = {};

  @override
  Future<String?> get(String key) async => _items[key];

  @override
  Future<void> set(String key, String value) async {
    _items[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _items.remove(key);
  }
}
