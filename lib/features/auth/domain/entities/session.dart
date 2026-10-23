import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/features/auth/domain/entities/user.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'session.freezed.dart';

/// A signed-in user and the instant their session ends. Holds no secret: the
/// tokens belong to the adapter that implements `AuthSession`.
///
/// [expiresAt] is on the device clock, the same time base as the `Clock` port:
/// the adapter computes it at sign-in as `clock.now()` plus the lifetime the
/// server grants, and never copies a timestamp of the server. It is therefore
/// only as reliable as the device clock: a clock set back extends the session
/// locally, a clock set forward ends it early. The server enforces its own
/// expiry on every call, so the local value only decides when the app stops
/// offering the session.
@freezed
abstract class Session with _$Session {
  /// Creates a session. Use [createSession].
  const factory({required User user, required Instant expiresAt}) = _Session;
}

/// Builds a session. It cannot fail: the user and the instant are already
/// validated.
Session createSession({required User user, required Instant expiresAt}) =>
    Session(user: user, expiresAt: expiresAt);
