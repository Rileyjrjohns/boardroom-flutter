import 'package:boardroom/domain/shared/constants.dart';

/// A small key-value store for secrets (a session token, the key of the
/// database). On a device it is the keychain (iOS) or the keystore (Android).
/// It
/// is the seam between the logic that decides what to keep and the native
/// module
/// that keeps it, so the logic is tested against an in-memory one. The methods
/// may throw: the callers turn that into the errors of their ports.
abstract interface class SecureStorage {
  /// The value stored under the key, or `null`.
  Future<String?> get(String key);

  /// Stores the value, replacing what the key held.
  Future<void> set(String key, String value);

  /// Forgets the key. Forgetting a key that is not there succeeds.
  Future<void> remove(String key);
}

/// The keys of the secure storage. Letters, digits, dots, dashes and
/// underscores
/// only: that is what both platforms accept.
enum SecureStorageKey implements StableValue {
  /// The session and its token.
  session('boardroom.session'),

  /// The key of the local database and which file it opens (see
  /// `database_key.dart`).
  databaseKey('boardroom.database-key'),

  /// The key the database file that was set aside had, kept so that the file is
  /// not lost for good if its being unreadable turns out to be a problem of the
  /// keychain and not of the file.
  databaseKeyPrevious('boardroom.database-key.previous'),

  /// Present from the moment local data was reset until the user has been told
  /// (see `local_data_reset.dart`).
  localDataReset('boardroom.local-data-reset');

  new(this.value);

  @override
  final String value;
}
