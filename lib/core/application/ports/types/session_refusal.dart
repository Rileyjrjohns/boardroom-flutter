import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:meta/meta.dart';

/// Why the `SessionGate` refused to say that the user who asked is still the
/// one signed in.
@immutable
final class SessionRefusal {
  /// Creates a refusal, with the [error] to return and whether the session is
  /// [sessionKept].
  const new({required this.error, required this.sessionKept});

  /// The error the caller returns: nobody is signed in, the session has
  /// expired, somebody else is signed in now, or the app is locked.
  final AppError error;

  /// Whether the session is still the one that asked and only waits for the app
  /// to be unlocked. What the device holds for that user is then still theirs,
  /// and is left alone; any other refusal means the user is gone.
  final bool sessionKept;

  @override
  bool operator ==(Object other) =>
      other is SessionRefusal &&
      other.error == error &&
      other.sessionKept == sessionKept;

  @override
  int get hashCode => Object.hash(error, sessionKept);

  @override
  String toString() =>
      'SessionRefusal(error: $error, sessionKept: $sessionKept)';
}
