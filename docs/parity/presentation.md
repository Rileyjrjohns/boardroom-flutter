# Parity of the presentation

How the presentation tests of the React Native app (`src/core/presentation`, `src/features/*/presentation`, `src/composition/shell`, at the commit of [`RN_COMMIT`](RN_COMMIT)) map to the Dart tests (`test/core/presentation`, `test/features/*/presentation`, `test/app`). The pattern of the screens is in [`../presentation.md`](../presentation.md); the behaviour of each screen is in [`../spec/screens.md`](../spec/screens.md) and is the same in both apps.

`tool/scenario_parity.dart` reads the `domain` and `application` folders only, so this table is kept by hand. The names of the scenarios are kept wherever the scenario exists in Dart (the screens' tests are written from the React Native ones, one scenario per test), but the structure differs on purpose, for these reasons:

- **No services contexts.** React Native fills one context per feature (`MeetingsServices`...) from `AppProviders`; Riverpod declares one provider per use case in each feature's `providers.dart`, which `appOverrides` fills. The `*Services.test.tsx` files have one Dart counterpart for all of them: `test/app/providers/app_overrides_test.dart`.
- **No query keys.** React Native names its queries with key factories (`meetingsQueryKeys`...) and invalidates by key; a Riverpod provider is its own key (`meetingQueryProvider(id)`), invalidated with `ref.invalidate`. The `*QueryKeys.test.ts` files have nothing to port.
- **No query client.** The `staleTime` and `gcTime` of the client are `keepQueryFor` (`lib/core/presentation/query/query_lifetime.dart`); the clearing of the cache when a session ends is the registry of the queries, which the container empties when the epoch of the access moves (`dropQueriesWhenSessionMoves`). The tests of both are in `query_lifetime_test.dart`, with the one that proves a second user is never handed the first one's data.
- **The slot has no `notice` and no `loadedAt`.** The React Native `MeetingActions` returns a `notice` node and `renderResolutionActions`, and the hook is given `now`. The Dart slot (`resolutionActionsProvider`) is only a builder for the actions of one resolution, given the meeting and the resolution. The votes' implementation reads the instant the meeting was loaded at from `meetingQueryProvider(id)` (falling back on the clock when the meeting is not in the query), and it tells the failure to read the votes once, as an `InlineError` in the block of the first resolution, instead of a notice at the top of the meeting.
- **Texts and hints are read from the generated localizations**, never from literals, in tests too (`l10nOf()`); the language tests loop over `en` and `fr`.
- **A Dart test that ends a screen with timers** empties the tree and disposes the container (`finish`, `endApp`): the queries keep their stale and gc timers, and `flutter_test` refuses a test that ends with a timer pending.

## Core

| React Native test | Dart test | Note |
| --- | --- | --- |
| `core/presentation/components/Button.test.tsx`, `Dialog.test.tsx`, `DialogHost.test.tsx`, `ErrorState.test.tsx`, `InlineError.test.tsx`, `PrivacyCover.test.tsx`, `StatusBanner.test.tsx`, `TextField.test.tsx`, `DemoControls.test.tsx`, `accessibility.test.tsx` | `core/presentation/components/components_test.dart` | One file, one group per component. `DialogHost` is `showAppDialog`; the touch-target and label scenarios of `accessibility.test.tsx` are inside each component's group |
| `core/presentation/components/SegmentedControl.test.tsx`, `AppStatusBar.test.tsx` | (none) | Not ported as files of their own: the period control (`PeriodControl`) is tested through the meetings list screen; the status bar has no logic |
| `core/presentation/accessibility/useAnnounce.test.tsx` | `core/presentation/components/components_test.dart` (`small components`) | `LiveText` and `announceOnIos` |
| `core/presentation/errors/ErrorCatalog.test.tsx` | `core/presentation/errors/error_catalog_test.dart` | |
| `core/presentation/format/formatters.test.ts` | `core/presentation/format/formatters_test.dart` | Zone fixed to UTC |
| `core/presentation/i18n/*.test.ts` (7 files) | `test/tool/arb_test.dart` (same keys, same parameters, French typography) and the generated `AppLocalizations` | Not ported: the i18n machinery (`createI18n`, plural fallback, language resolution) is `gen-l10n` and `intl`, tested by their authors |
| `core/presentation/navigation/useIsScreenFocused.test.tsx` | `core/presentation/navigation/navigation_test.dart` (`pushOnce`) and `documents/presentation/screens/document_screen_test.dart` (focus) | Focus is `TickerMode`/route visibility in the document screen |
| `core/presentation/query/retryPolicy.test.ts`, `createQueryClient.test.ts` | `core/presentation/query/retry_policy_test.dart`, `query_lifetime_test.dart` | |
| `core/presentation/query/errorCode.test.ts`, `QueryFailure.test.tsx` | `core/presentation/query/query_failure_test.dart` | |
| `core/presentation/query/useResultMutation.test.tsx`, `state/actionEpoch.test.tsx` | `core/presentation/query/result_action_test.dart` | `runResultAction` |
| `core/presentation/state/uiStore.test.tsx` | `core/presentation/state/ui_state_test.dart` | |
| `core/presentation/services/CoreServices.test.tsx` | `app/providers/app_overrides_test.dart` | See "No services contexts" |
| `core/presentation/theme/tokens.test.ts` | (none) | Not ported: the tokens are constants with no logic |
| (none) | `test/tool/presentation_literals_test.dart` | Replaces the lint rule that forbids a literal in the JSX |

## Auth

| React Native test | Dart test | Note |
| --- | --- | --- |
| `auth/presentation/screens/SignInScreen.test.tsx` | `auth/presentation/sign_in_screen_test.dart` | The reference test of a screen |
| `auth/presentation/screens/LockScreen.test.tsx` | `auth/presentation/lock_screen_test.dart` | |
| `auth/presentation/components/SignOutDialog.test.tsx` | `auth/presentation/sign_out_dialog_test.dart` | |
| `auth/presentation/state/accessStore.test.tsx` | `auth/presentation/access_test.dart` | |
| `auth/presentation/i18n/authMessageKeys.test.ts` | `auth/presentation/error_messages_test.dart` | Exhaustive over the codes, in both languages |
| `auth/presentation/query/sessionQueryKeys.test.ts`, `services/AuthServices.test.tsx` | (none) | See "No query keys" and "No services contexts" |
| (none) | `auth/presentation/actions_test.dart`, `session_test.dart` | The actions and the session life (restore, check, watch) are tested apart in Dart; in React Native they are covered through `SessionController.test.tsx` and the screens |

## Meetings

| React Native test | Dart test | Note |
| --- | --- | --- |
| `meetings/presentation/screens/MeetingsListScreen.test.tsx` | `meetings/presentation/meetings_list_screen_test.dart` | `TestApp(meetingsPageSize: testPageSize)` for the small pages |
| `meetings/presentation/screens/MeetingDetailScreen.test.tsx`, `.voting.test.tsx`, `.slot.test.tsx` | `meetings/presentation/meeting_detail_screen_test.dart` | The voting and the slot scenarios that need the votes are in `votes/presentation/vote_resolution_actions_test.dart`; the ones that do not are in `slots/resolution_actions_test.dart` |
| `meetings/presentation/screens/failures.test.tsx` | `meetings/presentation/failures_test.dart` | The screens are mounted without the router, so the test removes the screen the way the router does and checks that the query is gone from memory |
| `meetings/presentation/screens/listCache.test.tsx` | `meetings/presentation/list_cache_test.dart` | |
| `meetings/presentation/components/DocumentRow.test.tsx`, `ResolutionView.test.tsx`, `ResolutionVoteLine.test.tsx` | `meetings/presentation/components/document_row_test.dart`, `resolution_view_test.dart`, `resolution_vote_line_test.dart` | |
| `meetings/presentation/slots/resolutionActions.test.tsx` | `meetings/presentation/slots/resolution_actions_test.dart` | See "The slot" |
| `meetings/presentation/state/meetingsStore.test.tsx` | `meetings/presentation/state/selected_meetings_period_test.dart` | |
| `meetings/presentation/i18n/meetingMessageKeys.test.ts` | `meetings/presentation/messages_test.dart` | Exhaustiveness of each `switch` is checked by the analyzer |
| `meetings/presentation/hooks/meetingPages.test.ts`, `hooks/useMeetingsList.test.tsx` | `meetings/presentation/meetings_list_screen_test.dart`, `failures_test.dart` | The pages are the state of the `MeetingsList` notifier, tested through the screen |
| `meetings/presentation/query/meetingsQueryKeys.test.ts`, `services/MeetingsServices.test.tsx` | (none) | See above |

## Documents

| React Native test | Dart test | Note |
| --- | --- | --- |
| `documents/presentation/screens/DocumentScreen.test.tsx` | `documents/presentation/screens/document_screen_test.dart` | The PDF view is the fake of `fake_pdf_views.dart`, driven by hand |
| `documents/presentation/components/PdfViewer.test.tsx` | `documents/presentation/components/pdf_view_test.dart` | Only the conversation with `pdfrx` is tested (what is left off, how it reports back); the engine needs a device. The text selection is off in the viewer, so there is nothing to clear (see `../native-module.md`) |
| `documents/presentation/components/SecureContent.test.tsx` | `documents/presentation/components/secure_content_test.dart` | |
| `documents/presentation/components/DocumentWatermark.test.tsx` | `documents/presentation/components/document_watermark_test.dart` | |
| (none: part of `DocumentScreen.test.tsx`) | `documents/presentation/components/capture_notice_test.dart` | The notice is a component of its own in Dart |
| `documents/presentation/i18n/documentMessageKeys.test.ts` | `documents/presentation/error_messages_test.dart` | |
| `documents/presentation/services/DocumentsServices.test.tsx` | (none) | See "No services contexts" |
| (none) | `documents/presentation/screen_protection_demo_screen_test.dart` | The demo screen has no React Native test |

## Votes

| React Native test | Dart test | Note |
| --- | --- | --- |
| `votes/presentation/screens/PendingVotesScreen.test.tsx` | `votes/presentation/pending_votes_screen_test.dart` | |
| `votes/presentation/slots/voteResolutionActions.test.tsx` | `votes/presentation/vote_resolution_actions_test.dart`, `vote_dialog_test.dart` | The confirmation dialog has its own file in Dart |
| `votes/presentation/hooks/resolutionVote.test.ts` | `votes/presentation/resolution_vote_test.dart` | |
| `votes/presentation/session/useVoteSync.test.tsx`, `state/voteSyncStore.test.tsx` | `votes/presentation/vote_sync_test.dart` | The trigger (`requestVoteSyncProvider`) |
| `votes/presentation/components/SyncSummaryNotice.test.tsx` | `votes/presentation/sync_summary_notice_test.dart`, `sync_summary_test.dart` | The notice is `syncSummaryNotices` (the `BannerNotices` of the core); the state is tested apart. The rejected-sync line of the banner is `coreBannerRejected` |
| `votes/presentation/i18n/voteMessageKeys.test.ts`, `voteMessages.test.ts` | `votes/presentation/error_messages_test.dart` | |
| `votes/presentation/query/votesQueryKeys.test.ts`, `services/VotesServices.test.tsx` | (none) | See above |

## Shell (`src/composition/shell`, `lib/app`)

| React Native test | Dart test | Note |
| --- | --- | --- |
| `shell/components/HeaderActions.test.tsx` | `app/shell/header_actions_test.dart` | Same scenario names; the "opens the pending votes" scenario is added |
| `shell/session/SessionController.test.tsx`, `useAppLifecycle.test.tsx`, `useConnectivityStatus.test.tsx` | `app/shell/shell_test.dart` | `AppLifecycleHandler`, `connectivityObserver`, the session controller |
| `shell/services/StartupGate.test.tsx`, `screens/StartupFailureScreen.test.tsx` | `app/shell/shell_test.dart` (`the app`, `the start fails`) | |
| `shell/services/AppProviders.test.tsx`, `AppServices.test.tsx` | `app/providers/app_overrides_test.dart` | |
| `shell/navigation/rootLayout*.test.tsx`, `sessionNavigation.test.tsx`, `documentNavigation.test.tsx`, `systemLinks.test.ts` | `app/router/app_router_test.dart` | The guards (`redirectOf`) and the deep links; the redirects replace the layout effects of expo-router |
| `shell/navigation/offlineScenario.test.tsx` | `votes/presentation/vote_sync_test.dart`, `meetings/presentation/list_cache_test.dart` | Offline is a scenario of the screens in Dart |
| `shell/navigation/AppErrorBoundary.test.tsx` | (none) | Not ported: Flutter has `FlutterError.onError` in `main`, with no widget to test |
| `shell/errorCatalog.test.ts` | `core/presentation/errors/error_catalog_test.dart` | |
| `shell/queryKeys.test.ts` | (none) | See "No query keys" |
| `shell/testIds.test.ts` | `test/tool/spec_conformance_test.dart` | The ids, the builders and the routes against `screens.md`, in both directions |
