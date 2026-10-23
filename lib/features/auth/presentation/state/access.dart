import 'package:boardroom/core/domain/shared/constants.dart';
import 'package:boardroom/features/auth/application/use_cases/restore_session.dart';
import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'access.g.dart';

/// Where the user stands, which decides the screens they can reach (see the
/// router). The application layer holds the truth about the lock (`AppLock`)
/// and the session, but no use case reports it, and the router has to know it
/// to show the right screen: this is the presentation's mirror of it, moved by
/// the outcome of the use cases and by the failures that end a session
/// (docs/spec/screens.md, `ACCESS`).
enum Access implements StableValue {
  /// `RestoreSession` has not answered yet: nothing is shown but the loading
  /// state.
  starting('starting'),

  /// Nobody is signed in. The sign-in screen.
  signedOut('signedOut'),

  /// Somebody is signed in and the app is locked. The lock screen.
  locked('locked'),

  /// The app is open: the meetings, the votes.
  unlocked('unlocked');

  new(this.value);

  @override
  final String value;
}

/// The state of access of the interface, which is `auth`'s: the other features
/// and the shared components read it (the screens of the open app only run
/// while it is [Access.unlocked]) and none writes it but through the
/// transitions of [AccessController]. It never holds a name, an email or a
/// vote.
@immutable
final class AccessState {
  /// Creates a state.
  const new({required this.access, this.epoch = 0, this.sessionEndedBy});

  /// Where the user stands.
  final Access access;

  /// Goes up every time [access] changes. Whatever starts under one access and
  /// answers later (a synchronisation, a check of the session, a request) reads
  /// the epoch when it starts and hands it back with its result, and the result
  /// is applied only if it is still the current one: the answer of a run for
  /// the user who left is not the business of the user who came after.
  final int epoch;

  /// The code of the failure that sent the user to the sign-in or lock screen,
  /// if one did, so that the screen can explain it. The query that saw the
  /// failure has just been dropped and the screen that showed it has just been
  /// left, so only this remembers. It is forgotten when the user leaves the
  /// open app for another reason, or comes back.
  final String? sessionEndedBy;

  @override
  bool operator ==(Object other) =>
      other is AccessState &&
      other.access == access &&
      other.epoch == epoch &&
      other.sessionEndedBy == sessionEndedBy;

  @override
  int get hashCode => Object.hash(access, epoch, sessionEndedBy);
}

/// The transitions of the access (docs/spec/screens.md "Navigation map"). Each
/// one starts from the access it makes sense from and does nothing from any
/// other.
@Riverpod(keepAlive: true)
class AccessController extends _$AccessController {
  @override
  AccessState build() => const AccessState(access: Access.starting);

  /// The initial access of a test that renders a screen of the open app.

  void startAt(Access access) => state = AccessState(access: access);

  void _moveTo(Access access, {String? sessionEndedBy}) {
    state = AccessState(
      access: access,
      epoch: state.epoch + 1,
      sessionEndedBy: sessionEndedBy,
    );
  }

  bool _isCurrentOpenApp(int epoch) =>
      state.access == Access.unlocked && state.epoch == epoch;

  /// `RestoreSession` answered: somebody is signed in (locked), or nobody is.
  /// Only from [Access.starting].
  void sessionRestored(SessionRestore status) {
    if (state.access != Access.starting) {
      return;
    }
    _moveTo(status == SessionRestore.none ? Access.signedOut : Access.locked);
  }

  /// A sign-in succeeded: the app is open (the credentials just typed prove
  /// presence). Only from [Access.signedOut].
  void signedIn() {
    if (state.access == Access.signedOut) {
      _moveTo(Access.unlocked);
    }
  }

  /// The biometric unlock succeeded. Only from [Access.locked].
  void unlocked() {
    if (state.access == Access.locked) {
      _moveTo(Access.unlocked);
    }
  }

  /// The app has to be locked: the lock was evaluated on the way back and is
  /// required, or a sign-out failed after the use case had locked the app. Only
  /// from [Access.unlocked], and only for the epoch the check started under: a
  /// late check never puts a lock screen back for a session that has ended.
  void locked(int epoch) {
    if (_isCurrentOpenApp(epoch)) {
      _moveTo(Access.locked);
    }
  }

  /// The user signed out, or chose to forget a session that could not be read.
  /// Not from [Access.signedOut].
  void signedOut() {
    if (state.access != Access.signedOut) {
      _moveTo(Access.signedOut);
    }
  }

  /// A failure said the session is over. `appLocked` sends the user to the lock
  /// screen, every other code to the sign-in screen, with the reason. Only an
  /// open app has a session to end, and only for the epoch the failing request
  /// started under: a failure that arrives after the user left it, or for a
  /// user who has been replaced since, is ignored.
  void endSession(String code, int epoch) {
    if (!_isCurrentOpenApp(epoch)) {
      return;
    }
    _moveTo(
      code == AuthenticationErrorCode.appLocked.value
          ? Access.locked
          : Access.signedOut,
      sessionEndedBy: code,
    );
  }
}

/// Where the user stands.
@Riverpod(keepAlive: true)
Access access(Ref ref) => ref.watch(accessControllerProvider).access;

/// Whether the app is open: signed in and unlocked. The queries that hold the
/// data of a user run only then.
@Riverpod(keepAlive: true)
bool sessionOpen(Ref ref) => ref.watch(accessProvider) == Access.unlocked;
