import 'package:boardroom/app/container/app_container.dart';
import 'package:boardroom/app/error_catalog.dart';
import 'package:boardroom/app/providers/slot_overrides.dart';
import 'package:boardroom/core/presentation/providers.dart';
import 'package:boardroom/features/auth/application/session/session_policy.dart';
import 'package:boardroom/features/auth/presentation/providers.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:boardroom/features/documents/presentation/providers.dart';
import 'package:boardroom/features/meetings/presentation/providers.dart';
import 'package:boardroom/features/votes/presentation/providers.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// The overrides of the root provider container: the composition root builds
/// the real objects (`AppContainer`) and this is where every provider that a
/// feature declares and throws on gets its value. It is the Riverpod
/// counterpart of the `AppProviders` of the React Native app: the features read
/// their use cases from their own providers and never import this.
///
/// A new provider that throws until overridden is added here, with its
/// feature's: a test (`test/app/providers/app_overrides_test.dart`) reads every
/// provider of the app and fails on one that still throws.
List<Override> appOverrides(AppContainer container) {
  final useCases = container.useCases;
  return [
    // The core.
    clockProvider.overrideWithValue(container.clock),
    observeConnectivityUseCaseProvider.overrideWithValue(
      useCases.observeConnectivity,
    ),
    errorCatalogProvider.overrideWithValue(createAppErrorCatalog()),
    demoControlsProvider.overrideWithValue(container.demoControls),
    appNoticesProvider.overrideWithValue(container.notices),
    // The access is `auth`'s: a failure that ends the session tells it why, and
    // its epoch is what the queries and the actions are tied to.
    sessionEndHandlerProvider.overrideWith(
      (ref) => (code, startedUnder) {
        if (!isSessionEndingCode(code)) {
          return;
        }
        ref
            .read(accessControllerProvider.notifier)
            .endSession(
              code,
              startedUnder ?? ref.read(accessControllerProvider).epoch,
            );
      },
    ),
    sessionEpochProvider.overrideWith(
      (ref) => ref.watch(accessControllerProvider).epoch,
    ),
    // Auth.
    restoreSessionUseCaseProvider.overrideWithValue(useCases.restoreSession),
    signInUseCaseProvider.overrideWithValue(useCases.signIn),
    signOutUseCaseProvider.overrideWithValue(useCases.signOut),
    evaluateAppLockUseCaseProvider.overrideWithValue(useCases.evaluateAppLock),
    unlockAppUseCaseProvider.overrideWithValue(useCases.unlockApp),
    getCurrentUserUseCaseProvider.overrideWithValue(useCases.getCurrentUser),
    // Meetings.
    listMeetingsUseCaseProvider.overrideWithValue(useCases.listMeetings),
    getMeetingUseCaseProvider.overrideWithValue(useCases.getMeeting),
    meetingsPageSizeProvider.overrideWithValue(
      container.settings.meetingsPageSize,
    ),
    // Documents.
    openDocumentUseCaseProvider.overrideWithValue(useCases.openDocument),
    closeDocumentUseCaseProvider.overrideWithValue(useCases.closeDocument),
    observeScreenCaptureUseCaseProvider.overrideWithValue(
      useCases.observeScreenCapture,
    ),
    screenProtectionProvider.overrideWithValue(container.screenProtection),
    // Votes.
    castVoteUseCaseProvider.overrideWithValue(useCases.castVote),
    syncPendingVotesUseCaseProvider.overrideWithValue(
      useCases.syncPendingVotes,
    ),
    listPendingVotesUseCaseProvider.overrideWithValue(
      useCases.listPendingVotes,
    ),
    acknowledgeRejectedVoteUseCaseProvider.overrideWithValue(
      useCases.acknowledgeRejectedVote,
    ),
    discardUnreadableVotesUseCaseProvider.overrideWithValue(
      useCases.discardUnreadableVotes,
    ),
    // The links between features, plugged here because no feature may make
    // them.
    ...slotOverrides(),
  ];
}
