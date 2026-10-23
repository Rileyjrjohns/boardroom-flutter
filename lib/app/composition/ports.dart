import 'package:boardroom/core/application/ports/clock.dart';
import 'package:boardroom/core/application/ports/connectivity.dart';
import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/domain/value_objects/duration.dart';
import 'package:boardroom/features/auth/application/ports/auth_session.dart';
import 'package:boardroom/features/auth/application/ports/biometric_gate.dart';
import 'package:boardroom/features/documents/application/ports/document_cache.dart';
import 'package:boardroom/features/documents/application/ports/document_repository.dart';
import 'package:boardroom/features/documents/application/ports/screen_protection.dart';
import 'package:boardroom/features/meetings/application/ports/meeting_cache.dart';
import 'package:boardroom/features/meetings/application/ports/meeting_repository.dart';
import 'package:boardroom/features/votes/application/ports/vote_outbox.dart';
import 'package:boardroom/features/votes/application/ports/vote_repository.dart';
import 'package:meta/meta.dart';

/// An adapter for every port the use cases need. A configuration builds one of
/// these; the use cases are wired from it, the same way whatever the adapters
/// are.
@immutable
final class Ports {
  /// Creates the set of ports of a configuration.
  const new({
    required this.clock,
    required this.monitoring,
    required this.auth,
    required this.biometricGate,
    required this.connectivity,
    required this.screenProtection,
    required this.meetings,
    required this.meetingCache,
    required this.documents,
    required this.documentCache,
    required this.votes,
    required this.outbox,
  });

  /// The time.
  final Clock clock;

  /// Where the events and the errors are reported.
  final Monitoring monitoring;

  /// The sign-in and the stored session.
  final AuthSession auth;

  /// The biometrics of the device.
  final BiometricGate biometricGate;

  /// The connectivity status of the device.
  final Connectivity connectivity;

  /// The screen protection of the device.
  final ScreenProtection screenProtection;

  /// The remote meetings.
  final MeetingRepository meetings;

  /// The local cache of meetings.
  final MeetingCache meetingCache;

  /// The remote documents.
  final DocumentRepository documents;

  /// The local cache of documents.
  final DocumentCache documentCache;

  /// The server that records votes.
  final VoteRepository votes;

  /// The local queue of votes.
  final VoteOutbox outbox;
}

/// The configuration values the use cases take in their `deps` (see
/// `settings.dart`).
@immutable
final class UseCaseSettings {
  /// Creates the settings of the use cases.
  const new({
    required this.maxCacheAge,
    required this.maxAttempts,
    required this.gracePeriod,
    required this.startsLocked,
  });

  /// How old a cached copy may be and still be served as stale data.
  final DurationMillis maxCacheAge;

  /// How many unexpected failures a vote may have before it is given up.
  final int maxAttempts;

  /// How long the app may stay in the background without asking for the
  /// biometrics again.
  final DurationMillis gracePeriod;

  /// Whether the app is locked when it is built. A real cold start is (the
  /// session that is restored must be unlocked with the biometrics); a
  /// configuration that opens a session by itself, as if the user had just
  /// signed in, is not.
  final bool startsLocked;
}
