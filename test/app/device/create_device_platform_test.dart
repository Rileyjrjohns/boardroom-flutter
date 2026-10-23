import 'dart:io';

import 'package:boardroom/app/device/create_device_platform.dart';
import 'package:boardroom/core/infrastructure/connectivity/connectivity_plus_network_state.dart';
import 'package:boardroom/core/infrastructure/persistence/random_key.dart';
import 'package:boardroom/core/infrastructure/persistence/sqlite3_opener.dart';
import 'package:boardroom/core/infrastructure/secure_storage/device_secure_storage.dart';
import 'package:boardroom/features/auth/infrastructure/biometrics/device_local_authentication.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/infrastructure/test_files.dart';

// The plugins are only called when a wrapper is used, so all there is to check
// is that the platform is made of the wrappers over them. The private storage
// of the app is a directory of the machine here.
void main() {
  final parent = temporaryDirectory();
  Future<Directory> locate() async => parent;

  group('createDevicePlatform', () {
    test('is made of the wrappers over the four native modules', () async {
      final platform = await createDevicePlatform(locate: locate);

      expect(platform.databaseOpener, isA<Sqlite3Opener>());
      expect(platform.secureStorage, isA<DeviceSecureStorage>());
      expect(platform.randomBytes, same(secureRandomBytes));
      expect(platform.localAuthentication, isA<DeviceLocalAuthentication>());
      expect(platform.networkState, isA<ConnectivityPlusNetworkState>());
    });

    test(
      'makes a platform each time, with nothing shared between two',
      () async {
        final first = await createDevicePlatform(locate: locate);
        final second = await createDevicePlatform(locate: locate);

        expect(first.secureStorage, isNot(same(second.secureStorage)));
        expect(first.databaseOpener, isNot(same(second.databaseOpener)));
      },
    );

    test('keeps the databases in a folder of the private storage', () async {
      final platform = await createDevicePlatform(locate: locate);

      expect(
        (platform.databaseOpener as Sqlite3Opener).directory.path,
        equals('${parent.path}/$databaseDirectoryName'),
      );
    });
  });
}
