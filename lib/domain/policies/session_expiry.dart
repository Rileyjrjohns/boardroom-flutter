import 'package:boardroom/domain/entities/session.dart';
import 'package:boardroom/domain/value_objects/instant.dart';

/// A session is expired at its expiry instant and after it.
bool isSessionExpired(Session session, Instant now) =>
    isAtOrAfter(now, session.expiresAt);
