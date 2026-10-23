import 'dart:io';

import 'package:boardroom/core/infrastructure/files/create_device_file_store.dart';
import 'package:boardroom/core/infrastructure/persistence/sqlite3_opener.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/infrastructure/test_files.dart';

// The folders of the device are found with `path_provider`. Every other test
// hands a folder of its own to the functions that look for them, so this is the
// only one that runs the step in between: the channel of the plugin is
// answered with a different folder for each kind, and what is checked is which
// kind the documents and the database go to. The ones the system backs up (the
// documents folder, the library folder) and the temporary one must never be it.

/// The channel of the plugin.
const MethodChannel _channel = MethodChannel(
  'plugins.flutter.io/path_provider',
);

/// The calls of the plugin, and the name of the folder each one answers.
const String _cacheCall = 'getApplicationCacheDirectory';
const String _supportCall = 'getApplicationSupportDirectory';
const String _documentsCall = 'getApplicationDocumentsDirectory';
const String _libraryCall = 'getLibraryDirectory';
const String _temporaryCall = 'getTemporaryDirectory';

const List<String> _folderCalls = [
  _cacheCall,
  _supportCall,
  _documentsCall,
  _libraryCall,
  _temporaryCall,
];

void main() {
  final parent = temporaryDirectory();
  late Map<String, Directory> folders;
  late List<String> asked;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    final root = freshDirectory(parent);
    folders = {
      for (final call in _folderCalls)
        call: Directory('${root.path}/$call')..createSync(),
    };
    asked = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          asked.add(call.method);
          return folders[call.method]?.path;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  group('createDeviceFileStore', () {
    test('asks the system for the caches folder on iOS, and for no other '
        'folder', () async {
      final store = await createDeviceFileStore(isIos: true);

      expect(
        store.uriOf('a.pdf'),
        endsWith('/$_cacheCall/$documentDirectoryName/a.pdf'),
      );
      expect(asked, equals([_cacheCall]));
    });

    test('asks the system for the private folder of the app on Android, '
        'and for no other folder', () async {
      final store = await createDeviceFileStore(isIos: false);

      expect(
        store.uriOf('a.pdf'),
        endsWith('/$_supportCall/$documentDirectoryName/a.pdf'),
      );
      expect(asked, equals([_supportCall]));
    });

    test('writes the document in the folder it said', () async {
      final store = await createDeviceFileStore(isIos: false);

      await store.write('a.pdf', Uint8List.fromList([1, 2, 3]));

      expect(
        File('${folders[_supportCall]!.path}/$documentDirectoryName/a.pdf')
            .readAsBytesSync(),
        equals([1, 2, 3]),
      );
      expect(
        Directory(folders[_documentsCall]!.path).listSync(),
        isEmpty,
        reason: 'the documents folder is part of the backups of iOS',
      );
    });
  });

  group('createDeviceDatabaseOpener', () {
    test('asks the system for the private folder of the app, and for no '
        'other folder', () async {
      final opener = await createDeviceDatabaseOpener();
      await (await opener.open('device.db')).close();

      expect(asked, equals([_supportCall]));
      expect(
        File('${folders[_supportCall]!.path}/$databaseDirectoryName/device.db')
            .existsSync(),
        isTrue,
      );
      for (final call in _folderCalls.where((call) => call != _supportCall)) {
        expect(
          folders[call]!.listSync(),
          isEmpty,
          reason: 'nothing of the database in the folder of $call',
        );
      }
    });
  });
}
