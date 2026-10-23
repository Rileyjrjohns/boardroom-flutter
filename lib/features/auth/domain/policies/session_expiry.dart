import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/features/auth/domain/entities/session.dart';

/// A session is expired at its expiry instant and after it.
bool isSessionExpired(Session session, Instant now) =>
    isAtOrAfter(now, session.expiresAt);
