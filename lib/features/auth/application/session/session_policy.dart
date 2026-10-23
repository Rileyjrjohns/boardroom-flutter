import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';

/// The failures that say the session of the user is over, whatever the
/// operation was doing: the server refused the session, there is none, it has
/// expired or is another one, or the app is locked. Whoever meets one ends the
/// session for the whole app, and nothing of the previous session may stay on
/// the screen or in memory.
final List<String> sessionEndingCodes = List.unmodifiable([
  RepositoryErrorCode.unauthorized.value,
  AuthenticationErrorCode.notAuthenticated.value,
  AuthenticationErrorCode.sessionExpired.value,
  AuthenticationErrorCode.sessionChanged.value,
  AuthenticationErrorCode.appLocked.value,
]);

/// One of the [sessionEndingCodes]. TypeScript narrows a `string` to this
/// union with a type guard; Dart has no such narrowing, so it is the string
/// itself.
typedef SessionEndingCode = String;

final Set<String> _sessionEndingSet = Set.unmodifiable(sessionEndingCodes);

/// Any code, not only those of the meetings: a synchronisation and an action
/// meet them too.
bool isSessionEndingCode(String code) => _sessionEndingSet.contains(code);

/// How often an app that stays open and in the foreground asks whether its
/// session is still good, in milliseconds. A session that expires while the
/// user looks at the screen must not leave the data on it until the next
/// request happens to find out: the longest it can stay is this, plus the time
/// of a check. The check is local (the session guard reads the stored session
/// and the clock), so a short period costs nothing; it is long enough not to be
/// a loop.
const int sessionCheckIntervalMillis = 30000;
