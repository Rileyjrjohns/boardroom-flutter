import 'dart:io';

import 'package:boardroom/infrastructure/files/file_store.dart';
import 'package:boardroom/infrastructure/files/io_file_volume.dart';
import 'package:path_provider/path_provider.dart';

/// The directory of the documents, in the storage of the app. Part of what is
/// on
/// the device.
const String documentDirectoryName = 'boardroom-documents';

/// Where on the device the directory of the store lives. Both are private to
/// the
/// app and out of the backups; they differ in what the system may do to them.
enum DeviceStorage {
  /// The caches directory. The system may empty it when the device runs low on
  /// storage, so a file can be gone without the app having deleted it, which
  /// the
  /// document cache reads as a miss. On iOS this is the right place: the
  /// documents folder is part of the iCloud and iTunes backups.
  cache,

  /// The private storage of the app (the files directory on Android). The
  /// system
  /// leaves it alone, and the backups of Android are off for the app
  /// (`android:allowBackup` is `false`), so nothing leaves the device from it.
  private,
}

/// The storage used on a platform: the caches directory on iOS, the private
/// storage of the app on Android.
DeviceStorage deviceStorageOf({required bool isIos}) =>
    isIos ? DeviceStorage.cache : DeviceStorage.private;

/// Where on the device the content of the documents lives: the caches directory
/// on iOS, the private storage of the app on Android (see [DeviceStorage] for
/// why they differ). The folders of the platform are found with
/// `path_provider`, or with [locate] when a test gives its own.
Future<FileStore> createDeviceFileStore({
  bool? isIos,
  Future<Directory> Function(DeviceStorage storage)? locate,
}) async {
  final storage = deviceStorageOf(isIos: isIos ?? Platform.isIOS);
  final parent = await (locate ?? _locate)(storage);
  final directory = Directory(
    '${parent.path}${Platform.pathSeparator}$documentDirectoryName',
  );
  return createFileStore(IoFileVolume(directory));
}

Future<Directory> _locate(DeviceStorage storage) => switch (storage) {
  DeviceStorage.cache => getApplicationCacheDirectory(),
  DeviceStorage.private => getApplicationSupportDirectory(),
};
