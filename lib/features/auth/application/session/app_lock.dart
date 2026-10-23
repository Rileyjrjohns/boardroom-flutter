/// Whether the app is locked, in memory. The biometric lock used to be a flag
/// that a use case returned and nothing enforced; this is the state that
/// `requireSession` reads, so that no use case returns, queues or sends
/// anything for the user while it is closed.
///
/// - It starts locked, and `RestoreSession` locks it again on every cold start:
///   a process that has not yet proven anything fails closed.
/// - `EvaluateAppLock` locks it when the grace period in the background is over
///   (or cannot be judged), and `UnlockApp` opens it once the biometrics
///   succeed.
/// - A successful `SignIn` leaves it open (the user has just typed their
///   credentials) and `SignOut` closes it.
///
/// One instance must be shared by every use case that reads or changes it: the
/// composition root creates it once and injects it, like the
/// `ScreenProtectionCoordinator`. Two instances would each be unlocked on their
/// own, and the lock would guard nothing. The state dies with the process,
/// which is the point: a cold start is always locked.
final class AppLock {
  /// Creates a lock. [locked] is whether it starts closed. It does by default:
  /// nobody has proven they are there yet.
  new({bool locked = true}) : this._(locked);

  new _(this._locked);

  bool _locked;

  /// Whether the app is locked.
  bool isLocked() => _locked;

  /// Closes the lock. Locking a locked app changes nothing.
  void lock() {
    _locked = true;
  }

  /// Opens the lock. Unlocking an unlocked app changes nothing.
  void unlock() {
    _locked = false;
  }
}
