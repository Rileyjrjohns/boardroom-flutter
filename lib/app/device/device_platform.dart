import 'package:boardroom/core/infrastructure/connectivity/device_connectivity.dart';
import 'package:boardroom/core/infrastructure/persistence/database_opener.dart';
import 'package:boardroom/core/infrastructure/persistence/random_key.dart';
import 'package:boardroom/core/infrastructure/secure_storage/secure_storage.dart';
import 'package:boardroom/features/auth/infrastructure/biometrics/device_biometric_gate.dart';
import 'package:meta/meta.dart';

/// What the app needs from the device, as the seams the adapters are written
/// against: the engine of the local database, the secure storage, the secure
/// random generator, the biometric prompt and the state of the network. The
/// composition root asks for it once; a test hands over another one, made of a
/// database engine over a temporary directory, a storage in memory, chosen
/// random bytes and scripted platform answers, and runs the same wiring on it.
///
/// The native module that protects the screen is a seam of the same kind; the
/// part of the step that defines it adds it here (see
/// `docs/parity/open-questions.md`).
@immutable
final class DevicePlatform {
  /// Creates the description of a device.
  const new({
    required this.databaseOpener,
    required this.secureStorage,
    required this.randomBytes,
    required this.localAuthentication,
    required this.networkState,
  });

  /// The engine of the local database.
  final DatabaseOpener databaseOpener;

  /// The keychain of the device.
  final SecureStorage secureStorage;

  /// Where the key of the database comes from.
  final RandomBytes randomBytes;

  /// The biometric prompt.
  final LocalAuthenticationApi localAuthentication;

  /// The state of the network.
  final NetworkStateApi networkState;
}
