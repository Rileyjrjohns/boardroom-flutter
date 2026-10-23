import 'package:boardroom/core/application/ports/types/session_refusal.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';

/// What the offline policy (`loadWithCacheFallback`) needs to know about the
/// session, and nothing more. The policy is shared by every feature that reads
/// remote data into a cache, so it is in `core`; the session is the business of
/// `auth`, which implements this port (`AuthSessionGate`) and is the only one
/// to know what a session is. `core` imports no feature, and a feature that
/// loads data hands the policy a gate through its deps.
abstract interface class SessionGate {
  /// Succeeds with the user who is signed in, when it is [expected] and the app
  /// is unlocked. Otherwise the [SessionRefusal] says why: nobody is signed in,
  /// the session has expired, somebody else is signed in, or the app is locked.
  Future<Result<UserId, SessionRefusal>> requireSameUser(UserId expected);

  /// Ends the session of [user], which the server refused: the app is locked,
  /// what the session left on the device is emptied, and the session is
  /// forgotten. Never fails, nothing is reported to the caller, which has the
  /// refusal to return.
  Future<void> endRefusedSession(UserId user);

  /// Empties what a session leaves on the device, for every owner. Best effort:
  /// a failure is reported by the implementation and never returned.
  Future<void> purgeSessionData();
}
