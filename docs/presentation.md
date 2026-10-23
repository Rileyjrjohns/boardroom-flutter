# Presentation

How the screens are built. The behaviour of each screen (routes, states, actions, test ids) is specified in [`spec/screens.md`](spec/screens.md) and is the same as the React Native app's; this page is the **pattern** every feature follows to implement it in Flutter. The foundations (the shared components, the query layer, the session state, the shell, the router, the composition of the providers) are written; a screen agent writes the screens of a feature and nothing else.

## The stack

| Concern                           | Tool                                                                                                                          |
| --------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| State and dependency injection    | `flutter_riverpod` 3, with `riverpod_annotation` and `riverpod_generator` (`@riverpod`, the `*.g.dart` files are generated)   |
| Navigation                        | `go_router` (`lib/app/router`), with a `redirect` driven by the access state                                                  |
| Texts                             | `gen-l10n` (ARB files `lib/l10n/app_en.arb` and `app_fr.arb`), read through `AppLocalizations.of(context)`                    |
| Server state (queries)            | Riverpod providers that throw a `QueryFailure`; retry, freshness and memory in `lib/core/presentation/query`                 |
| Actions of the user (mutations)   | A `Notifier<ActionState>` that calls `runResultAction`                                                                        |

`dart run build_runner build` writes the providers; `flutter pub get` writes the localizations. Neither output is committed.

## Where things live

```text
lib/core/presentation/
  theme/            tokens.dart (every colour, size and spacing), app_theme.dart
  components/       the shared widgets: AppButton, AppBadge, AppTextField, AppDialog, ErrorState, InlineError, LiveText,
                    LoadingState, Message, StatusBanner, ConnectionBanner, DemoOfflineSwitch, DemoAccounts, PrivacyCover, ContentHost
  errors/           ErrorCatalog: code -> text, and which codes are retryable
  query/            QueryFailure and unwrapResult, RetryPolicy, keepQueryFor (freshness), runResultAction and ActionState
  state/            ui_state.dart: connectivityStateProvider, privacyCoverUpProvider, localDataResetNoticeProvider
  navigation/       routes.dart (AppRoutes, RouteParams), navigate.dart (openMeeting, openDocument, openPendingVotes, pushOnce)
  format/           Formatters (dateTime, fullDateTime, number)
  providers.dart    what the core takes from the outside (clock, error catalog, session end handler, epoch...)
  test_ids.dart     CoreTestIds and demoAccountTestId
lib/features/<feature>/presentation/
  providers.dart    the use cases the screens need, each a provider that throws until overridden
  test_ids.dart     <Feature>TestIds, and the builders
  error_messages.dart  (when the feature has codes of its own) code -> text
  state/            notifiers (access, the actions, the stores of the feature)
  screens/          one file per screen
  components/       the widgets of the feature
lib/app/
  providers/app_overrides.dart   the one place where every provider that throws gets its value
  providers/slot_overrides.dart  the links between features (banner notices, the resolution actions slot)
  router/           app_router.dart (routes, guards, redirect), route_scaffold.dart (header of a route)
  shell/            StartupGate, SessionController, the app lifecycle, the connectivity observer, the failure screen
  error_catalog.dart, test_ids.dart   the registries that put the core and the features together
```

A feature's presentation imports `core`, its own layers (`domain`, `application`, `presentation`) and the **presentation** of the features it depends on in `tool/check_imports.dart` (`meetings` and `documents` and `votes` may use `auth/presentation`, `documents` and `votes` may use `meetings/presentation`): their providers, their components, their test ids. It never imports an `infrastructure` folder, never `lib/app`, and never the presentation of a feature it does not depend on.

## The dependency injection pattern

The React Native app has one services context per feature (`MeetingsServices`...) filled by `AppProviders`. In Riverpod each feature declares its providers and the composition overrides them.

1. **A feature declares what its screens need** in `lib/features/<feature>/presentation/providers.dart`, one provider per use case, throwing until overridden:

   ```dart
   @Riverpod(keepAlive: true)
   ListMeetings listMeetingsUseCase(Ref ref) =>
       throw UnimplementedError('listMeetingsUseCaseProvider');
   ```

   The name is `<useCase>UseCaseProvider` (generated). Only use cases and values (`meetingsPageSizeProvider`) go here, never an adapter.
2. **The composition builds the real objects** (`lib/app/container`: the configuration `dev` or `http`, chosen by `--dart-define=BOARDROOM_ADAPTERS=dev|http`, plus `BOARDROOM_API_BASE_URL`, see `RawSettings.fromEnvironment`) and `lib/app/providers/app_overrides.dart` (`appOverrides(AppContainer)`) overrides every provider. `StartupGate` makes the `ProviderContainer` from them, with the retry policy of the queries.
3. **A test overrides the same providers over fakes**: `TestApp` (see "How to write a widget test").

A provider that throws must be listed in `appOverrides` **and** in the list of `test/app/providers/app_overrides_test.dart`, which fails on one that is missing (it reads the `providers.dart` files).

## Reading data: a query

A screen that reads server data uses a provider that returns the data or **throws a `QueryFailure`**:

```dart
@riverpod
Future<Loaded<Meeting>> meeting(Ref ref, MeetingId id) async {
  ref.keepQueryFor();                       // 60 s fresh, 5 min in memory, dropped when the user leaves the open app
  final result = await ref.read(getMeetingUseCaseProvider).execute(meetingId: id);
  return unwrapResult(result);               // throws QueryFailure(result.error)
}
```

- `ref.keepQueryFor()` is the first line of every query that holds data of the user. It mirrors the stale time (60 s) and the gc time (5 min) of the React Native query client, and drops the data when the epoch of the access moves (the user left the open app).
- A query is retried by the root container's policy (`RetryPolicy`): at most twice, after 0.5 s then 1 s, only for the codes the catalog calls retryable. A non-retryable failure is reported at once. A failure whose code ends the session (`unauthorized`, `notAuthenticated`, `sessionExpired`, `sessionChanged`, `appLocked`) ends the session for the whole app (through `sessionEndHandlerProvider`) before the screen sees it. You write none of that.
- The screen reads `AsyncValue`: `loading`, `error` (`QueryFailure`: use `errorCodeOf(error, catalog)` or `(error as QueryFailure).error.code`), `value`. A failed refresh keeps the previous value next to the error (`hasValue && hasError`): that is the "refresh failed" state, shown with an `InlineError`. **A refusal of the item** (`forbidden`, `notFound`, `itemRefusalCodes`) makes the screen drop the data it held: show the final error, not the old value.
- **A paginated list** is an `AsyncNotifier` that keeps the pages and the cursor; "refresh" restarts from the first page; "next page failed" is a field of its state, not an `AsyncError` (the pages loaded stay).
- The screen **never reads the clock**: the voting state is judged at `loadedAt`.
- `ref.watch(sessionOpenProvider)` is true while the app is open; a query that holds data of the user does not run otherwise.

## Acting: a mutation

A button that does something (sign in, vote, acknowledge, discard) uses a `Notifier<ActionState>` and `runResultAction`, never a bare `await useCase.execute()` in a widget:

```dart
@riverpod
class SignOutAction extends _$SignOutAction {
  @override
  ActionState build() => const ActionState.idle();

  Future<void> run() => runResultAction<void>(
    ref: ref,
    current: () => state,
    emit: (next) => state = next,
    execute: () => ref.read(signOutUseCaseProvider).execute(),
    onSuccess: (_, _) => ref.read(accessControllerProvider.notifier).signedOut(),
    onFailure: (_, startedUnder) => ref.read(accessControllerProvider.notifier).locked(startedUnder),
  );
}
```

`ActionState` is `idle`, `pending` (`isPending`) or `failed` (`failure`, an `AppError`). `runResultAction` ignores a second call while one is under way, never retries, reads a thrown value as `unexpected`, tells a session-ending code to `sessionEndHandlerProvider` for the epoch the action **started under** (the answer of a user who left does not end the session of the one who came after), and keeps the action pending until `onSuccess` settles (a screen that refreshes what the action changed keeps its button busy until the refresh is done). The password and the choice of a vote are arguments of `run`, never kept in the state.

## Errors

- A failure is a **code** (`AppError.code`). `ErrorCatalog` (`errorCatalogProvider`) turns a code into a text and says whether it is retryable. The core declares its codes (`coreErrorMessages`), `auth` the session's (`sessionErrorMessages`), and `lib/app/error_catalog.dart` puts them together. A feature whose codes other screens can meet adds its map there; codes only its screen tells (the document screen, the vote failures) stay in a map of the feature (`error_messages.dart`, see `auth` for the shape: a `Map<String, ErrorMessage>` and a total function with the `unexpected` fallback). A test must check that every code of the family has an entry in both languages (`test/features/auth/presentation/error_messages_test.dart`).
- `ErrorState(code:, onRetry:)` replaces content that could not be loaded; `InlineError(code:, onRetry:)` sits next to content that is still there. The retry button (`CoreTestIds.retryButton`) is shown only for a retryable code **and** when `onRetry` is given.
- Final versus inline: a retryable error with content on screen is inline; a non-retryable one replaces the content.

## Screens

- A screen is a `ConsumerWidget` (or `ConsumerStatefulWidget` for a form). **It has no `Scaffold` and no `AppBar`**: the route frame (`RouteScaffold` in `lib/app/router`) gives the header and the title. A screen's root widget carries the screen's test id as its key.
- **Every state of `docs/spec/screens.md` is a branch of the build**: loading (`LoadingState` with the spec's label), empty (`Message(centered: true)`), error (`ErrorState`), inline error, content, stale (`StatusBanner(staleSince:)`), offline (`StatusBanner` reads the connectivity itself), not found (`Message`), locked / session ended (the router does it). A screen with a route parameter parses it with the domain (`parseMeetingId`) and shows "not found" for one it refuses, without asking the server.
- The banner area at the top of the screens of the open app is `StatusBanner(staleSince:)`; the sign-in and lock screens use `ConnectionBanner`. The demo switch is `DemoOfflineSwitch` (renders nothing outside the dev configuration).
- Dialogs: `showAppDialog(context, builder: (_) => AppDialog(...))`. The privacy cover is drawn over the navigator, so it covers dialogs too. A dialog whose action is under way passes `onDismiss: null` (the back gesture does nothing) and disables Cancel.
- Navigation: `openMeeting(context, id)`, `openDocument(context, id)`, `openPendingVotes(context)` (a `push` that does not stack the screen already on top). Never `Navigator.push`.
- Dates and numbers: `Formatters.of(context)` (`dateTime`, `fullDateTime`, `number`), never `DateFormat` in a screen.
- Accessibility: use `LiveText` for what appears while the user looks elsewhere (errors, banners), `AppButton(hint:)` where the action is not obvious, touch targets of at least 44 (the shared widgets already do), `Semantics(header: true)` on titles.
- Colours, spacings, sizes: only `tokens.dart` (`AppColors`, `AppSpacing`, `AppFontSizes`, `AppRadii`, `AppSizes`). The reference screens are `SignInScreen` (a form with an action, the fields' errors, the session notice, the demo helpers) and the shell (`SessionController`).

## Test ids

The ids of `docs/spec/screens.md` are strings; the widgets set them as `Key(id)`:

```dart
KeyedSubtree(key: const Key(AuthTestIds.signInError), child: LiveText(...))
AppButton(key: const Key(AuthTestIds.signInSubmit), ...)
```

- Core ids: `CoreTestIds` (`lib/core/presentation/test_ids.dart`). Each feature: `<Feature>TestIds` in `lib/features/<feature>/presentation/test_ids.dart` (**already written from the spec, with the builders**: `meetingRowTestId(id)`, `voteChoiceTestId(resolutionId, choice)`...). They are pure Dart on purpose: the conformance test reads them. The builders take strings (`choice.value`, `period.value`).
- `lib/app/test_ids.dart` assembles the registry (`testIds`, by constant name) and re-exports the builders. `test/tool/spec_conformance_test.dart` compares the registry, the builders and the routes with `screens.md` in both directions. If you need an id that is not in the spec, it is a change of the spec: do not add it.
- Put the key on the element that the spec says (the root container, the button, the text), so that `find.byKey(const Key(...))` finds the same thing a Maestro flow finds.

## Texts (i18n)

- All user-facing text is in `lib/l10n/app_en.arb` (the template) and `app_fr.arb`, read with `AppLocalizations.of(context)`. **No literal in the presentation or `lib/app`**: `test/tool/presentation_literals_test.dart` parses the code and fails on a string in a `Text`, or in `title`, `label`, `hint`, `message`, `tooltip`, `semanticsLabel`... `test/tool/arb_test.dart` keeps the two files in step (same keys, same parameters, a description for every key, French typography).
- **The keys of the React Native app are already ported, all of them, in both languages** (`docs/spec/screens.md` names the key of every text: `signIn.title`). The mapping is mechanical: `<owner prefix>` + the RN key in PascalCase, with the prefix not doubled:

  | Owner       | RN namespaces                                                                                                       | ARB prefix   | Example                                              |
  | ----------- | ------------------------------------------------------------------------------------------------------------------- | ------------ | ---------------------------------------------------- |
  | `core`      | `app`, `common`, `navigation`, `states`, `errors`, `startup`, `banner` (offline, dismiss, localDataReset), `demo`, `privacy` | `core`       | `errors.notFound` -> `coreErrorsNotFound`            |
  | `auth`      | `signIn`, `lock`, `unlockErrors`, `signOut`, `biometric`                                                            | `auth`       | `signIn.title` -> `authSignInTitle`                  |
  | `meetings`  | `meetings`, `meeting`, `participantRole`, `votingState`, `confidentiality`                                          | `meetings`   | `meetings.empty.upcoming` -> `meetingsEmptyUpcoming`, `meeting.agenda` -> `meetingsMeetingAgenda` |
  | `documents` | `document`                                                                                                          | `documents`  | `document.capture.screenshot` -> `documentsDocumentCaptureScreenshot` |
  | `votes`     | `voting`, `voteChoice`, `voteBiometric`, `pendingVotes`, `banner.sent`, `banner.rejected`                           | `votes`      | `voting.queued` -> `votesVotingQueued`, `banner.sent` -> `votesBannerSent` |

  Parameters keep their name (`{date}`, `{choice}`, `{name}`...): the generated method takes them in the order of the ARB `placeholders`, e.g. `l10n.coreStatesStaleData(date)`. Plurals are ICU (`{count, plural, one{...} other{...}}`): the method takes the **int** `count` and formats it with the locale (`l10n.votesBannerSent(3)`). Dates are formatted by `Formatters` and passed as strings.
- **Add a key** only when the spec needs a text the port lacks: add it at the end of `app_en.arb` (with its `@key` description and `placeholders`) and of `app_fr.arb`, with the right prefix, in one edit of each file, then run `flutter gen-l10n`. The agents work in parallel: do not rewrite or reformat the files, only append.
- A text that depends on a code goes through a map of the feature (`error_messages.dart`), not a `switch` in a widget.

## Routes and the router

`AppRoutes` (`lib/core/presentation/navigation/routes.dart`) holds the six paths of the spec and their names: `meetings` (`/`), `signIn` (`/sign-in`), `lock` (`/lock`), `pendingVotes` (`/pending-votes`), `meetingDetail` (`/meetings/:meetingId`), `document` (`/documents/:documentId`), plus `screenProtectionDemo` (`/screen-protection-demo`, development only, outside the spec). `lib/app/router/app_router.dart` mounts them, each in a `RouteScaffold` (title from `coreNavigation*`):

| Route name (`AppRoutes.x.name`) | Screen widget (constructor)                                             | File to write / replace                                                   |
| ------------------------------- | ----------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| `signIn`                        | `SignInScreen()` (done)                                                 | `features/auth/presentation/screens/sign_in_screen.dart`                  |
| `lock`                          | `LockScreen()` (placeholder)                                            | `features/auth/presentation/screens/lock_screen.dart`                     |
| `meetings`                      | `MeetingsListScreen()` (placeholder)                                    | `features/meetings/presentation/screens/meetings_list_screen.dart`        |
| `meetingDetail`                 | `MeetingDetailScreen({required String meetingId})` (placeholder)       | `features/meetings/presentation/screens/meeting_detail_screen.dart`       |
| `document`                      | `DocumentScreen({required String documentId})` (placeholder)           | `features/documents/presentation/screens/document_screen.dart`            |
| `pendingVotes`                  | `PendingVotesScreen()` (placeholder)                                    | `features/votes/presentation/screens/pending_votes_screen.dart`           |

A placeholder is a file with the agreed class name and constructor: replace its body, **keep the class name and the constructor**, so that the router needs no change. The route parameter arrives raw (a `String`); parse it in the screen.

**Guards.** `redirectOf` (pure, tested) decides from the access state: `signedOut` has only `/sign-in`, `locked` only `/lock`, `unlocked` the other four; a route that does not exist for the access sends the user to the home of that access, and the stack starts anew there (so no deep link reaches a protected route, the back stack never returns to one, and the link is not remembered). A link longer than 2048 characters or badly percent-encoded is dropped. `starting` shows the loading state and mounts no route. The router listens to `accessProvider` (`refreshListenable`).

## The session (auth)

`lib/features/auth/presentation/state/access.dart`: `Access { starting, signedOut, locked, unlocked }`, `AccessState {access, epoch, sessionEndedBy}` and `AccessController` (`accessControllerProvider`) with the guarded transitions of the spec: `sessionRestored`, `signedIn`, `unlocked`, `locked(epoch)`, `signedOut`, `endSession(code, epoch)`. Selectors: `accessProvider`, `sessionOpenProvider`. The epoch goes up on every change; whatever starts under one access hands the epoch back with its result (`sessionEpochProvider` for the core, `AccessState.epoch`).

| Mechanism (spec "Session life of the open app") | Where                                                                                      |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------ |
| Restore at start                                | `RestoreSessionController` (`session/restore_session_controller.dart`)                     |
| Session check                                   | `sessionCheckProvider` (`session/session_check.dart`)                                      |
| Session watch (every `sessionCheckIntervalMillis`) | `sessionWatchProvider` (`session/session_watch.dart`)                                   |
| A session a failure ended is forgotten on the device | `signOutEndedSessionProvider` (`session/session_ended.dart`)                          |
| Background / return, privacy cover, lock        | `AppLifecycleHandler` (`lib/app/shell/app_lifecycle.dart`), driven by `AppLifecycleListener` in `SessionController` |
| Connectivity                                    | `connectivityObserverProvider` (`lib/app/shell/connectivity_observer.dart`)                |
| Vote synchronisation trigger                    | `requestVoteSyncProvider` (`features/votes/presentation/state/vote_sync.dart`): **a placeholder the votes agent fills** |

`SessionController` mounts all of them above the navigator. The actions: `SignInAction`, `SignOutAction`, `UnlockAction` (`state/*_action.dart`).

## Links between features

No feature imports `lib/app`. Two links are made in `lib/app/providers/slot_overrides.dart` (empty today):

- **The banner notices**: the core declares `BannerNotices` and `bannerNoticesProvider` (`status_banner.dart`); the votes implement it (the sync summary: `hasNotices` is a provider of bool, `builder` builds the lines) and the override `bannerNoticesProvider.overrideWithValue(...)` goes in `slotOverrides()`.
- **The resolution actions slot**: the meetings declare it (`features/meetings/presentation/slots/resolution_actions.dart`: a provider of a builder that gets the meeting, the resolution and the loaded-at instant; the default builds nothing); the votes implement it (the voting block of a resolution); the override goes in `slotOverrides()`.

The header actions of the list (pending votes with its count, sign out) are `lib/app/shell/header_actions.dart`, a placeholder (`SizedBox.shrink`) that the integration step writes once `pendingVotesProvider` and `SignOutDialog` exist.

## How to write a widget test

`test/support/presentation/test_app.dart` is the whole harness. The use cases are the **real ones wired over the fakes** (`createFakes()`), the providers are overridden exactly as the app does it (`appOverrides`), the retry has no wait, the screen is mounted in a `MaterialApp` with the localizations.

```dart
testWidgets('signs in and opens the app', (tester) async {
  final app = TestApp();                                  // fakes: app.fakes.auth, .meetings, .outbox, .clock...
  final providers = await pumpScreen(
    tester, const SignInScreen(),
    app: app, access: Access.signedOut,                   // where the user stands; default Access.unlocked
    locale: const Locale('fr'),                           // default en
  );
  final en = l10nOf();                                    // the texts, no literal in a test either

  await tester.enterText(byTestId(AuthTestIds.signInEmail), 'alice@example.com');
  await tester.tap(byTestId(AuthTestIds.signInSubmit));
  await tester.pumpAndSettle();

  expect(providers.read(accessProvider), Access.unlocked);   // the provider container, to read any state
  expect(find.text(en.authSignInTitle), findsNothing);
});
```

- `TestApp({fakes, demoControls, notices, startsLocked, adaptPorts})`: `adaptPorts` replaces a port (to hold an answer with a `Completer`, to see the busy state). `app.useCases`, `app.container`, `app.overrides` are there if needed. `app.providers(access:, extra:)` gives the container without a widget (for a notifier test, under `fakeAsync` if there are timers).
- `extra: [someProvider.overrideWithValue(...)]` overrides one more provider (e.g. `requestVoteSyncProvider`, `bannerNoticesProvider`).
- Seed data on the fakes before pumping (`app.fakes.meetings.addMeeting(aMeeting())`, `app.fakes.auth.session = null`); the builders are in `test/support/builders`.
- After a change of a provider that nothing in the tree watches, the container refreshes lazily: keep a widget that watches it in the tree (the screens do), or read the provider.
- A test that starts a timer (the session watch) must dispose the container before it ends: pump `SizedBox.shrink()` and call `providers.dispose()`.
- Where tests live (the CI runs them): `test/features/<feature>/presentation/` for the screens and notifiers of a feature, `test/core/presentation/` for the shared parts, `test/app/` for the shell, the router and the composition.
- A test of a screen covers **every state of the spec table of that screen** (loading, empty, error, inline error, stale, offline, not found...), in English, and one in French for the texts that differ.

## What each feature agent ports

| Feature       | From the React Native app                                                                                                                                                                                                           | Fills / uses                                                                                                                                                       |
| ------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `auth`        | `LockScreen`, `SignOutDialog` (+ its use from the lock screen and the header), `SessionNotice` (done), the tests of the sign-in (done as the reference)                                                                              | `UnlockAction`, `SignOutAction` (done), `unlockErrorMessage` (done), `AuthTestIds` (done)                                                                          |
| `meetings`    | `MeetingsListScreen` (period control, pagination, pull to refresh, every state), `MeetingDetailScreen` (agenda, documents, participants, `ResolutionView`, `DocumentRow`, `ParticipantRow`), the **ResolutionActions slot**, the period state (kept while a meeting is open) | `listMeetingsUseCaseProvider`, `getMeetingUseCaseProvider`, `meetingsPageSizeProvider`, `MeetingsTestIds`, `StatusBanner`, `ErrorState`, `openMeeting`/`openDocument`   |
| `documents`   | `DocumentScreen` (lifecycle open/close tied to the screen having focus and the access, PDF viewer (add the PDF package then), watermark, `SecureContent` (exists), capture notice, `DocumentErrorState`), the demo screen (exists)     | `openDocumentUseCaseProvider`, `closeDocumentUseCaseProvider`, `observeScreenCaptureUseCaseProvider`, `DocumentsTestIds`, `sessionOpenProvider`, `privacyCoverUpProvider` |
| `votes`       | `VoteDialog`, `ResolutionVoting` / the resolution actions (implements the meetings slot), `PendingVotesScreen`, `OutboxVoteRow`, `AcknowledgeButton`, `UnreadableVotesNotice`, `SyncSummaryNotice` (implements `BannerNotices`), the vote sync trigger (**`requestVoteSyncProvider`**), `HeaderActions` count | `castVoteUseCaseProvider` and the four others, `VotesTestIds`, `slotOverrides()`, `votesBannerSent`/`votesBannerRejected`                                           |

## Checks

`dart run tool/check_imports.dart` (the layers, the feature graph, presentation imports), `dart test test/tool` (the specification, the literals, the ARB files), `flutter analyze --fatal-infos --fatal-warnings`, `dart format`, `flutter test`. See the README for the commands in order.
