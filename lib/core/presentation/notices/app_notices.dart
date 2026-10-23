/// What happened to the data of the device while the app was not running, that
/// the user is owed an explanation of. The composition root reads it while it
/// starts.
abstract interface class AppNotices {
  /// Local data was reset: it could not be read, and the app started on an
  /// empty one. Votes that were waiting to be sent from this device may have
  /// been lost. Told once the app is open.
  bool get localDataReset;

  /// The user has been told: it is forgotten, and they will not be told again.
  /// Never throws.
  Future<void> acknowledgeLocalDataReset();
}

/// The notices of a start that owes the user nothing.
final class NoNotices implements AppNotices {
  /// Creates the empty set of notices.
  const new();

  @override
  bool get localDataReset => false;

  @override
  Future<void> acknowledgeLocalDataReset() async {}
}
