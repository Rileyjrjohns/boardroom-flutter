import 'package:boardroom/core/infrastructure/secure_storage/secure_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The service the items are filed under in the keychain: the app, not the
/// module's default.
const String keychainService = 'boardroom';

/// Where a secret may be read and by whom. On iOS and macOS: only while the
/// device is unlocked, and only on this device, so it is neither synchronised
/// through iCloud Keychain nor restored from a backup onto another device.
/// Android has no such option: its items are encrypted with a key of the
/// Android Keystore, in the private storage of the app, and the backups are off
/// for the app (`android:allowBackup` is `false`).
///
/// On Android, nothing is deleted when the Keystore cannot be read
/// (`resetOnError` is `false`). The plugin would otherwise delete the item it
/// failed to read, or all of them, and answer as if it had never been there:
/// the key of the database would be lost with no error, and the votes waiting
/// in the outbox with it. A read that fails is an error here, as it is in React
/// Native, and the callers turn it into `keyStorage` or `storageReadFailed`
/// without touching anything.
const FlutterSecureStorage deviceKeychain = FlutterSecureStorage(
  iOptions: IOSOptions(
    accountName: keychainService,
    accessibility: KeychainAccessibility.unlocked_this_device,
  ),
  aOptions: AndroidOptions(resetOnError: false),
  mOptions: MacOsOptions(
    accountName: keychainService,
    accessibility: KeychainAccessibility.unlocked_this_device,
  ),
);

/// The secure storage of the device, over `flutter_secure_storage`. As thin as
/// it can be: it renames the calls. Its logic is none, so its tests only check
/// which options it passes and that the values go through, and the keychain
/// itself has been run on no device.
final class DeviceSecureStorage implements SecureStorage {
  /// Creates the storage of the device, over [storage] (the keychain of the app
  /// by default).
  const new([FlutterSecureStorage storage = deviceKeychain])
    : _storage = storage;

  final FlutterSecureStorage _storage;

  @override
  Future<String?> get(String key) => _storage.read(key: key);

  @override
  Future<void> set(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> remove(String key) => _storage.delete(key: key);
}
