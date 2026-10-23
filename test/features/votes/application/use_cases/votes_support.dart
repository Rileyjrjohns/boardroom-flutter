import 'package:boardroom/core/application/ports/clock.dart';
import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/application/ports/session_gate.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/duration.dart';
import 'package:boardroom/features/auth/application/ports/auth_session.dart';
import 'package:boardroom/features/auth/application/ports/biometric_gate.dart';
import 'package:boardroom/features/auth/application/ports/session_data_purger.dart';
import 'package:boardroom/features/auth/application/session/app_lock.dart';
import 'package:boardroom/features/meetings/application/ports/meeting_cache.dart';
import 'package:boardroom/features/meetings/application/ports/meeting_document_evictor.dart';
import 'package:boardroom/features/meetings/application/ports/meeting_repository.dart';
import 'package:boardroom/features/votes/application/ports/recorded_vote_sink.dart';
import 'package:boardroom/features/votes/application/ports/vote_outbox.dart';
import 'package:boardroom/features/votes/application/ports/vote_repository.dart';
import 'package:boardroom/features/votes/application/use_cases/acknowledge_rejected_vote.dart';
import 'package:boardroom/features/votes/application/use_cases/cast_vote.dart';
import 'package:boardroom/features/votes/application/use_cases/discard_unreadable_votes.dart';
import 'package:boardroom/features/votes/application/use_cases/list_pending_votes.dart';
import 'package:boardroom/features/votes/application/use_cases/sync_pending_votes.dart';

import '../../../../support/fakes/create_fakes.dart';

/// The fakes, as the deps of the five use cases of the votes, with the outbox
/// or the biometric prompt replaced by something that is not the fake of
/// `createFakes`: the Dart counterpart of `{ ...fakes, outbox }`. A value
/// replaced by another one of the same type goes through `Fakes.copyWith`.
final class VotesDeps
    implements
        CastVoteDeps,
        SyncPendingVotesDeps,
        ListPendingVotesDeps,
        AcknowledgeRejectedVoteDeps,
        DiscardUnreadableVotesDeps {
  /// Wraps [_fakes]; [outbox] and [biometricGate] replace the ones of the
  /// fakes.
  new(this._fakes, {VoteOutbox? outbox, BiometricGate? biometricGate})
    : outbox = outbox ?? _fakes.outbox,
      biometricGate = biometricGate ?? _fakes.biometricGate;

  final Fakes _fakes;

  @override
  final VoteOutbox outbox;

  @override
  final BiometricGate biometricGate;

  @override
  int get maxAttempts => _fakes.maxAttempts;

  @override
  VoteRepository get votes => _fakes.votes;

  @override
  MeetingRepository get meetings => _fakes.meetings;

  @override
  DurationMillis get maxCacheAge => _fakes.maxCacheAge;

  @override
  Clock get clock => _fakes.clock;

  @override
  AuthSession get auth => _fakes.auth;

  @override
  AppLock get appLock => _fakes.appLock;

  @override
  MeetingCache get meetingCache => _fakes.meetingCache;

  @override
  SessionGate get sessionGate => _fakes.sessionGate;

  @override
  RecordedVoteSink get recordedVoteSink => _fakes.recordedVoteSink;

  @override
  List<SessionDataPurger> get sessionDataPurgers => _fakes.sessionDataPurgers;

  @override
  MeetingDocumentEvictor get documentEvictor => _fakes.documentEvictor;

  @override
  Monitoring get monitoring => _fakes.monitoring;
}

/// The value of a success, `null` for a failure: the Dart counterpart of
/// `result.ok && result.value`.
T? valueOf<T, E>(Result<T, E> result) => switch (result) {
  Ok(:final value) => value,
  Err() => null,
};
