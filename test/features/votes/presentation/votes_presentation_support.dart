import 'dart:async';

import 'package:boardroom/app/composition/ports.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/core/presentation/theme/app_theme.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:boardroom/features/votes/application/ports/vote_outbox.dart';
import 'package:boardroom/features/votes/application/ports/vote_repository.dart';
import 'package:boardroom/features/votes/domain/entities/outbox_vote.dart';
import 'package:boardroom/features/votes/domain/entities/vote.dart';
import 'package:boardroom/features/votes/domain/errors/vote_errors.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../support/presentation/test_app.dart';

// Test support of the presentation of the votes, not production code.

/// The ports of [ports] with [votes] as the vote repository.
Ports withVotes(Ports ports, VoteRepository votes) => Ports(
  clock: ports.clock,
  monitoring: ports.monitoring,
  auth: ports.auth,
  biometricGate: ports.biometricGate,
  connectivity: ports.connectivity,
  screenProtection: ports.screenProtection,
  meetings: ports.meetings,
  meetingCache: ports.meetingCache,
  documents: ports.documents,
  documentCache: ports.documentCache,
  votes: votes,
  outbox: ports.outbox,
);

/// A vote repository that holds the answer of the server to every vote until
/// the test lets it go, and notes whether two submissions ever overlapped: the
/// Dart counterpart of the `holdServer` of the React Native tests.
final class HoldingVotes implements VoteRepository {
  /// Wraps [_inner], the repository of the fakes.
  new(this._inner);

  final VoteRepository _inner;
  final Completer<void> _gate = Completer<void>();
  int _running = 0;
  bool _overlapped = false;

  /// How many submissions reached the server.
  int calls = 0;

  /// Whether two submissions were ever under way at the same time.
  bool get overlapped => _overlapped;

  /// Lets the held answers go.
  void release() {
    if (!_gate.isCompleted) {
      _gate.complete();
    }
  }

  @override
  Future<Result<void, VoteSubmissionError>> submit(Vote vote) async {
    calls += 1;
    _running += 1;
    _overlapped = _overlapped || _running > 1;
    await _gate.future;
    final answer = await _inner.submit(vote);
    _running -= 1;
    return answer;
  }
}

/// The ports of [ports] with [outbox] as the vote outbox.
Ports withOutbox(Ports ports, VoteOutbox outbox) => Ports(
  clock: ports.clock,
  monitoring: ports.monitoring,
  auth: ports.auth,
  biometricGate: ports.biometricGate,
  connectivity: ports.connectivity,
  screenProtection: ports.screenProtection,
  meetings: ports.meetings,
  meetingCache: ports.meetingCache,
  documents: ports.documents,
  documentCache: ports.documentCache,
  votes: ports.votes,
  outbox: outbox,
);

/// An outbox that counts the removals it is asked for, and does the rest as
/// [_inner] does.
final class CountingOutbox implements VoteOutbox {
  /// Wraps [_inner], the outbox of the fakes.
  new(this._inner);

  final VoteOutbox _inner;

  /// How many times a vote was removed.
  int removeCalls = 0;

  @override
  Future<Result<EnqueueResult, StorageWriteFailedError>> enqueue(
    PendingVote pending,
  ) => _inner.enqueue(pending);

  @override
  Future<Result<OutboxListing, StorageReadFailedError>> list(UserId voterId) =>
      _inner.list(voterId);

  @override
  Future<Result<int, StorageWriteFailedError>> discardUnreadable(
    UserId voterId,
  ) => _inner.discardUnreadable(voterId);

  @override
  Future<Result<List<OutboxVote>, StorageReadFailedError>> findByResolution(
    ResolutionId resolutionId,
    UserId voterId,
  ) => _inner.findByResolution(resolutionId, voterId);

  @override
  Future<Result<void, StorageWriteFailedError>> markAttempt(
    IdempotencyKey key,
  ) => _inner.markAttempt(key);

  @override
  Future<Result<void, StorageWriteFailedError>> reject(
    IdempotencyKey key,
    RejectionReason reason,
    Instant rejectedAt,
  ) => _inner.reject(key, reason, rejectedAt);

  @override
  Future<Result<void, StorageWriteFailedError>> remove(IdempotencyKey key) {
    removeCalls += 1;
    return _inner.remove(key);
  }
}

/// The key of the marker the router shows for the meeting [id]: the screen
/// the "open meeting" buttons lead to.
Key openedMeetingKey(String id) => Key('opened-meeting-$id');

/// Mounts [screen] in an app with a router, so that the buttons that open a
/// meeting have somewhere to go: the meeting route shows a marker keyed by
/// [openedMeetingKey]. Returns the provider container.
Future<ProviderContainer> pumpRouted(
  WidgetTester tester,
  Widget screen, {
  TestApp? app,
  Access access = Access.unlocked,
  Locale locale = const Locale('en'),
}) async {
  final providers = (app ?? TestApp()).providers(access: access);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: screen),
      ),
      GoRoute(
        path: '/meetings/:meetingId',
        builder: (_, state) =>
            SizedBox(key: openedMeetingKey(state.pathParameters['meetingId']!)),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: providers,
      child: MaterialApp.router(
        locale: locale,
        theme: buildAppTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  return providers;
}

/// Ends a widget test that started timers (the queries keep theirs): the tree
/// is emptied and the provider container disposed.
Future<void> endApp(WidgetTester tester, ProviderContainer providers) async {
  await tester.pumpWidget(const SizedBox.shrink());
  providers.dispose();
}
