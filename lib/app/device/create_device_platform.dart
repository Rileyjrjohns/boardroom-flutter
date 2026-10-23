import 'dart:io';

import 'package:boardroom/app/device/device_platform.dart';
import 'package:boardroom/core/infrastructure/connectivity/connectivity_plus_network_state.dart';
import 'package:boardroom/core/infrastructure/persistence/random_key.dart';
import 'package:boardroom/core/infrastructure/persistence/sqlite3_opener.dart';
import 'package:boardroom/core/infrastructure/secure_storage/device_secure_storage.dart';
import 'package:boardroom/features/auth/infrastructure/biometrics/device_local_authentication.dart';

/// The device of a phone: SQLite3MultipleCiphers (`sqlite3`) in the private
/// storage of the app, `flutter_secure_storage` (the Keychain and the
/// Keystore), the secure random generator of the platform, `local_auth` and
/// `connectivity_plus`. [locate] stands for the private storage in tests.
///
/// It is a `Future` where the React Native function is not, because the folder
/// of the databases is asked of the platform, which answers asynchronously
/// (`getApplicationSupportDirectory`).
///
/// The wrappers are made here and call their plugins only when they are used,
/// so a plugin that is missing from the build fails the first call that needs
/// it, which each adapter turns into the failure its port promises (a storage
/// error, `biometricUnavailable`, an `online` status); a failure when the
/// wrappers are made is caught by the composition root.
Future<DevicePlatform> createDevicePlatform({
  Future<Directory> Function()? locate,
}) async => DevicePlatform(
  databaseOpener: await createDeviceDatabaseOpener(locate: locate),
  // Not const on purpose: a platform shares nothing with another one.
  // ignore: prefer_const_constructors
  secureStorage: DeviceSecureStorage(),
  randomBytes: secureRandomBytes,
  localAuthentication: DeviceLocalAuthentication(),
  networkState: ConnectivityPlusNetworkState(),
);
