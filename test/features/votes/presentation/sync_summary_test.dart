// Each step of these tests is a call of its own on a notifier or a container;
// a cascade would hide the order.
// ignore_for_file: cascade_invocations

import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:boardroom/features/votes/presentation/state/sync_summary.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/presentation/test_app.dart';

// The summary of the synchronisation, until the user has read it, and what the
// session leaves to tell.

ProviderContainer _anOpenApp({Access access = Access.unlocked}) {
  final providers = TestApp().providers(access: access);
  providers.listen(syncSummaryStateProvider, (_, _) {});
  return providers;
}

int _epochOf(ProviderContainer providers) =>
    providers.read(accessControllerProvider).epoch;

SyncSummary? _summaryOf(ProviderContainer providers) =>
    providers.read(syncSummaryStateProvider);

SyncSummaryState _summaries(ProviderContainer providers) =>
    providers.read(syncSummaryStateProvider.notifier);

void main() {
  group('the summary of the synchronisation', () {
    test('starts with nothing to tell', () {
      expect(_summaryOf(_anOpenApp()), isNull);
    });

    test('adds up the runs until the user dismisses it, '
        'instead of keeping the last one', () {
      final providers = _anOpenApp();
      final epoch = _epochOf(providers);

      _summaries(providers)
          .show(const SyncSummary(synced: 2, rejected: 0), epoch);
      _summaries(providers)
          .show(const SyncSummary(synced: 1, rejected: 1), epoch);

      expect(_summaryOf(providers), const SyncSummary(synced: 3, rejected: 1));

      _summaries(providers).dismiss();
      _summaries(providers)
          .show(const SyncSummary(synced: 1, rejected: 0), epoch);

      expect(_summaryOf(providers), const SyncSummary(synced: 1, rejected: 0));
    });

    test('does not show a result of the synchronisation to '
        'a user who has left the open app', () {
      final providers = _anOpenApp(access: Access.locked);

      _summaries(providers)
          .show(const SyncSummary(synced: 1, rejected: 0), _epochOf(providers));

      expect(_summaryOf(providers), isNull);
    });

    test('notifies its subscribers of a change', () {
      final providers = _anOpenApp();
      final seen = <SyncSummary?>[];
      providers.listen(syncSummaryStateProvider, (_, next) => seen.add(next));

      _summaries(providers)
          .show(const SyncSummary(synced: 1, rejected: 0), _epochOf(providers));

      expect(seen, [const SyncSummary(synced: 1, rejected: 0)]);
    });
  });

  group('what the session left to tell', () {
    test(
      'is forgotten when the user locks the app, and when they sign out',
      () {
        final providers = _anOpenApp();
        final access = providers.read(accessControllerProvider.notifier);
        _summaries(
          providers,
        ).show(const SyncSummary(synced: 1, rejected: 0), _epochOf(providers));

        access.locked(_epochOf(providers));
        expect(_summaryOf(providers), isNull);

        access.unlocked();
        _summaries(
          providers,
        ).show(const SyncSummary(synced: 2, rejected: 1), _epochOf(providers));
        access.signedOut();
        expect(_summaryOf(providers), isNull);
      },
    );

    for (final code in [
      'unauthorized',
      AuthenticationErrorCode.notAuthenticated.value,
      AuthenticationErrorCode.sessionExpired.value,
      AuthenticationErrorCode.sessionChanged.value,
      AuthenticationErrorCode.appLocked.value,
    ]) {
      test('is forgotten when $code ends the session', () {
        final providers = _anOpenApp();
        _summaries(
          providers,
        ).show(const SyncSummary(synced: 1, rejected: 0), _epochOf(providers));

        providers
            .read(accessControllerProvider.notifier)
            .endSession(code, _epochOf(providers));

        expect(_summaryOf(providers), isNull);
      });
    }

    test('drops a result of a run that started for the user who '
        'left, then somebody else signed in', () {
      final providers = _anOpenApp();
      final first = _epochOf(providers);
      final access = providers.read(accessControllerProvider.notifier);
      access.signedOut();
      access.signedIn();

      _summaries(providers)
          .show(const SyncSummary(synced: 3, rejected: 1), first);

      expect(_summaryOf(providers), isNull);
    });

    test('applies a result of the access it started under', () {
      final providers = _anOpenApp();
      final epoch = _epochOf(providers);

      _summaries(providers)
          .show(const SyncSummary(synced: 1, rejected: 0), epoch);

      expect(_summaryOf(providers), const SyncSummary(synced: 1, rejected: 0));
    });
  });
}
