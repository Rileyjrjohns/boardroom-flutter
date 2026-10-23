import 'dart:io';

import 'package:boardroom/core/infrastructure/files/file_store.dart';
import 'package:boardroom/core/infrastructure/files/io_file_volume.dart';
import 'package:test/test.dart';

// Test support, not production code: the files of the tests. Calling
// [temporaryDirectory] makes the directory they live in exist, and removes it
// when the test file is done, so a file that uses it calls it at the top of
// `main` (a hook cannot be registered from inside a test).

/// A directory of the machine for the test file that calls this, removed when
/// the file is done.
Directory temporaryDirectory() {
  final directory = Directory.systemTemp.createTempSync('boardroom-test-');
  tearDownAll(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });
  return directory;
}

/// A new, empty directory inside [parent], to give each test its own.
Directory freshDirectory(Directory parent) => parent.createTempSync('case-');

/// A file store in a directory of its own, in [parent], over the file system of
/// the machine. [rootUri] makes the files say they are somewhere else.
FileStore testFileStore(
  Directory parent, {
  String? rootUri,
  int timeoutMillis = defaultFileTimeoutMillis,
}) => createFileStore(
  IoFileVolume(
    Directory('${freshDirectory(parent).path}/documents'),
    rootUri: rootUri,
  ),
  timeoutMillis: timeoutMillis,
);
