# Use cases

A use case is one operation of the application layer: a small class with one public method, `execute`, built once by the composition root with the ports and the settings it needs. Screens call use cases and never an adapter. A Flutter version implements the same operations with the same names, inputs, outputs, error codes, rules and side effects, in the same order.

The types and the policies are in [domain.md](domain.md), the ports in [ports.md](ports.md), the screens that call the use cases in [screens.md](screens.md). The notation is the one of [README.md](README.md).

## How to read a use case

Each section below has the same parts:

- **Input**: the parameters of `execute` (a record, or nothing). Callbacks are written as function types.
- **Output**: the type of the success value. Every use case that can fail returns `Result<Output, Error>`; none throws or rejects.
- **Errors**: the stable codes it can return, in a line that the conformance test checks (each token must be a real error code).
- **Ports**: the ports it calls, directly or through the shared rules below, in a line that the conformance test checks (each token must be a real port). A use case that calls the session guard also touches `AuthSession`, `Clock`, and, when a session is found expired, `MeetingCache`, `DocumentCache` and `Monitoring`.
- **Rules and side effects**, in the order they happen.

Two pieces of state are shared by several use cases and **must be a single instance** per app: the [`AppLock`](#the-app-lock) and the [`ScreenProtectionCoordinator`](#the-screen-protection-coordinator). Two instances would each be unlocked, or each switch the protection off, on their own say-so.

## Index

| Use case                  | Group        | What it does                                                                                      |
| ------------------------- | ------------ | ------------------------------------------------------------------------------------------------- |
| `RestoreSession`          | Auth         | On a cold start, finds out whether somebody was signed in; locks the app; ends an expired session |
| `SignIn`                  | Auth         | Validates the credentials, signs in, empties the caches, opens the app                            |
| `SignOut`                 | Auth         | Locks the app, empties the caches, forgets the session                                            |
| `UnlockApp`               | Auth         | Asks for a biometric proof and opens the app lock                                                 |
| `EvaluateAppLock`         | Auth         | On return from the background, decides whether the app must be unlocked again                     |
| `GetCurrentUser`          | Auth         | Who is signed in, through the session guard                                                       |
| `ObserveConnectivity`     | Connectivity | Reports the connection status now and each later change                                           |
| `ListMeetings`            | Meetings     | One page of upcoming or past meetings, with the offline policy                                    |
| `GetMeeting`              | Meetings     | A meeting with agenda, documents and participants, with the offline policy                        |
| `OpenDocument`            | Documents    | Opens a document for reading: content location, watermark, screen protection                      |
| `CloseDocument`           | Documents    | Releases a view of a document; turns the protection off when the last view is closed              |
| `ObserveScreenCapture`    | Documents    | Reports screenshots and recordings while a document is shown, and logs them                       |
| `CastVote`                | Votes        | Casts the vote of the signed-in user: eligibility, biometric confirmation, submit or queue        |
| `SyncPendingVotes`        | Votes        | Sends the queued votes, oldest first                                                              |
| `ListPendingVotes`        | Votes        | The pending and rejected votes of the signed-in user, and the count of unreadable entries         |
| `AcknowledgeRejectedVote` | Votes        | Deletes a rejected vote after the user has seen it                                                |
| `DiscardUnreadableVotes`  | Votes        | Deletes the outbox entries of the user that can no longer be read                                 |

## Shared rules

These rules are written once and referenced by name from the use cases.

### The session guard

Every use case that reads, queues or sends something **for the user** goes through the guard before anything else. `requireSession` returns the `Session` or fails, in this order:

1. read the stored session: `storageReadFailed` if it cannot be read;
2. no session: `notAuthenticated`;
3. the session is expired at `clock.now()` (see [session expiry](domain.md#session-expiry)): **both caches are emptied** (best effort: a failure is captured and the caller still gets the error), then `sessionExpired`. A session that ends while the app is running must not leave the content of its user on the device;
4. the app is locked (see [the app lock](#the-app-lock)): `appLocked`.

The session is never returned in a failure. Until the biometric unlock succeeds, no use case returns data to, or acts for, the user.

`requireSameUser(expected)` is the same guard followed by a comparison: if the signed-in user is not `expected`, the error is `sessionChanged`. A use case that started for a user and then waited for something (the network, a biometric prompt, a store) calls it **before it writes or returns anything**, and uses the session it returns, not the one read before the wait.

The error set of the guard, called `SessionRequiredError` in this file, is `notAuthenticated`, `sessionExpired`, `appLocked`, `storageReadFailed`. With `requireSameUser` it also includes `sessionChanged`.

### The session policy

Three rules decide what a failure, or the passing of time, means for the session. They are rules of the application layer: a screen applies them and never defines them, and a client of another kind follows the same ones.

- **The failures that end the session.** A failure that carries one of the codes of [`SESSION_ENDING_CODES`](#session_ending_codes), whichever operation met it (a read, an action of the user, a synchronisation of the votes), says that the session of the user is over. Whoever meets one ends the session for the whole app and drops everything of the previous session that it holds in memory. Four of them come out of the session guard (`notAuthenticated`, `sessionExpired`, `appLocked`, and `sessionChanged` for `requireSameUser`); `unauthorized` is the refusal of the server, which the application layer has already ended on the device (see [ending a refused session](#ending-a-refused-session)). What the screens do about each (where the user goes, which notice is shown) is in [screens.md](screens.md#session-ending-codes).
- **The failures a second try can fix.** A failure that carries one of the codes of [`RETRYABLE_CODES`](#retryable_codes) may not come again: the connection is back, a fault of the server has passed, a store is readable again, the platform manages to protect the screen. Any other code says something that asking again will not change, and is final for whoever met it. A screen offers a retry, and a client tries a read again by itself, only for these codes. How many times and after how long is the tuning of the client, not part of this rule (see [Freshness, retries and refresh](screens.md#freshness-retries-and-refresh-presentation-memory)).
- **How long the data of an expired session may stay on screen.** An app that stays open and in the foreground checks its session every `SESSION_CHECK_INTERVAL_MILLIS` (see [Constants](#constants)), through `GetCurrentUser`, so the data of an idle app does not stay on the screen until a request happens to find out. The longest it can stay after the session expired is this interval plus the time of one check. The timer, and when it runs, are for the screens (see [Session life of the open app](screens.md#session-life-of-the-open-app)).

### The app lock

The app lock is an in-memory flag, shared by the whole app, that the session guard reads. It **starts locked**, and its state dies with the process, so a cold start is always locked.

| Event                                                                   | Effect on the lock                                                                                       |
| ----------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| App started                                                             | Locked                                                                                                   |
| `RestoreSession` (every cold start)                                     | Locks it again, first thing                                                                              |
| `EvaluateAppLock` finds the unlock required, or cannot read the session | Locks it                                                                                                 |
| `UnlockApp` succeeds                                                    | Unlocks it                                                                                               |
| `SignIn` succeeds                                                       | Locked while the caches are emptied, **unlocked** after: typing the credentials is the proof of presence |
| `SignOut`, or a session the server refused                              | Locks it                                                                                                 |

### The offline policy

The offline policy is business logic and lives in the application layer, in one function (`loadWithCacheFallback`), not in an adapter. It is used by `ListMeetings`, `GetMeeting` (through `loadMeeting`), `OpenDocument`, and by `CastVote` (to load the meeting). Its inputs: the owner (the signed-in user), a **source** (a remote read, a cache write, a cache read, a cache removal of this entry, and a "revoke" that removes this entry and what hangs off it), the `maxCacheAge` setting, and the shared dependencies of the session guard.

1. **Remote first.** Call the remote source. Then call `requireSameUser(owner)`: a request can take long, and a sign-out and a sign-in can fall in the middle of it. If it fails (`sessionChanged`, or the session or the lock error), nothing is written, nothing is returned but that error, and, **if the remote call had succeeded** and the error is not `appLocked`, both caches are emptied (what the call may have left on the device, such as the file of a downloaded document, is then removed; for `appLocked` the user is the same and comes back).
2. **Write through.** On success, save the data in the cache with `cachedAt = clock.now()` and return it with `source = fresh`. A cache that cannot be written does not fail the call: the failure is captured (`cacheWriteFailed`), the fresh data is returned, and this entry is removed so that a copy that could not be refreshed does not stay readable as if it were current (a removal that fails is captured, `cacheRemoveFailed`, and falls back on emptying both caches).
3. **Cache only on network loss.** Only `networkUnavailable` reads the cache. A cache that cannot be read is captured (`cacheReadFailed`) and counts as a miss; on a miss the original network error is returned. An entry for which [`isWithinMaxAge`](domain.md#cache-age) is false (older than `maxCacheAge`, or dated in the future) counts as a miss too, and is logged (`cacheEntryDiscarded`). Otherwise the cached value is returned with `source = stale` and `cachedAt`, and `servedFromCache` is logged at info level.
4. **Eviction on refusal.**
   - `unauthorized` means the session is no longer valid, for anything: the session is **ended on the device** (see [ending a refused session](#ending-a-refused-session)).
   - `forbidden` and `notFound` concern one item: it is dropped from the cache **with what hangs off it** (a meeting takes the documents it lists with it, reading the cached meeting first). A removal that fails is captured and falls back on emptying both caches.
   - In every case the error is returned and the cache is not read.
5. **Anything else** (`unexpected`) is returned as is and the cache is left alone.

The result is `Loaded<T>`: `{ data: T, source: DataSource, loadedAt: Instant }`. `source` is `{ freshness: fresh }` or `{ freshness: stale, cachedAt: Instant }`. `loadedAt` is the instant of the clock when the use case answered, for saved data as well as for fresh data: it is the "now" a screen uses to judge what depends on time (is a voting window over?) without reading a clock. For saved data it is not `cachedAt`.

Known limit: the cached pages of a list are not walked. A page that shows the title of a meeting that became forbidden keeps showing it until it is refreshed or expires; opening the meeting is refused, and its detail and documents are gone.

### Ending a refused session

When the server says `unauthorized`, the application layer that met the answer (the offline policy, `CastVote`, `SyncPendingVotes`) ends the session **once**, in one place (`endRefusedSession`):

1. Read the stored session. If it can be read and its user is not the user the request was made for, or nobody is signed in, **do nothing**: `unauthorized` is also what an adapter answers when the token it holds belongs to another user than the request is for, and then the session now open was not refused.
2. Otherwise lock the app, empty both caches, and forget the session (`closeSession`). A session that cannot be forgotten is captured (`signOutFailed`) and the caller still gets `unauthorized`.

The votes in the outbox stay: they wait for the user to come back.

### Purging the caches

`purgeCaches` empties the meeting cache and the document cache (the content of the documents included), **for every owner**. Both are always attempted. A failure is captured (`cachePurgeFailed`, with the resource) and never returned: it must not stop a user from signing out.

### Recording a vote in the cache

After the server has recorded a vote, `recordVoteInCache` updates the cached copy of its meeting with `withVoteRecorded`, so that the copy shows the vote and the voter cannot vote again from it while offline. The copy keeps its `cachedAt`: updating it does not make it younger. A meeting that is not cached needs nothing. A cache that cannot be read or written is captured and fails nothing (the server refuses a second vote anyway). The read and the write are two steps and a sign-out can fall between them, so `requireSameUser(voter)` is called in between and nothing is written unless the same user is still signed in and the app is unlocked.

### The screen protection coordinator

The `ScreenProtection` port is one global switch. The coordinator decides when it is on:

- It keeps the **views** that are open, counted per document: a document opened twice is two views, and closing one leaves the other protected.
- `acquire(documentId)` turns the protection on, and counts the view **only if that worked**. On failure the error is returned, nothing is counted, and the caller must not show the document.
- `release(documentId)` stops counting a view, whatever the platform answers. When the last view of all is closed, it turns the protection off. If that fails, the failure is returned and the coordinator remembers that a `disable` is owed: the next `release` that finds no view open (any document) sends it again. A document with no view is ignored (success), unless a `disable` is owed and no view is open.
- Calls are **serialised**: each starts only when the one before has settled, so the calls reach the platform in the order they were made.
- The state (counts, owed disable, queue) is in memory and dies with the app.

## Auth

### `RestoreSession`

On a cold start, finds out whether somebody was signed in when the app was last used.

- **Input**: none.
- **Output**: `RestoredSession`: `{ status: none }` (nobody is signed in) or `{ status: unlockRequired }` (somebody is, and the app stays locked until `UnlockApp` succeeds). Who the user is (a name, an email) is **not** part of the answer: nothing is disclosed before the unlock.
- **Errors**: `storageReadFailed`
- **Ports**: `AuthSession`, `Clock`, `MeetingCache`, `DocumentCache`, `Monitoring`
- **Rules**, in order:
  1. Lock the app (always, first).
  2. Read the stored session; if it cannot be read, return `storageReadFailed`.
  3. No session: `none`.
  4. A session that is not expired: `unlockRequired`. The biometric unlock is required every time: the app was closed and nothing says how long it has been away.
  5. An expired session is ended: log `sessionExpired` (info), empty both caches, sign out (a failure of the sign-out is captured as `signOutFailed`), and answer `none`.
- On a device where the biometrics cannot be used, `UnlockApp` fails closed every time; the only way forward is to sign out and sign in again.

### `SignIn`

Signs a user in with an email and a password.

- **Input**: `{ email: Text, password: Text }`, exactly as typed.
- **Output**: `Session`.
- **Errors**: `validation`, `invalidCredentials`, `networkUnavailable`, `unexpected`, `storageWriteFailed`
- **Ports**: `AuthSession`, `MeetingCache`, `DocumentCache`, `Monitoring`
- **Rules**, in order:
  1. Build the `Credentials` (see [domain.md](domain.md#value-objects)): a badly formed email, or an empty password, is a `validation` error and **the server is not called**. The email is checked first.
  2. Call `AuthSession.signIn`. A refused sign-in changes nothing: the current session, the caches and the lock stay as they were.
  3. Once accepted, and before anything uses the new session: lock the app, empty both caches, unlock the app. Whoever signed in before (a sign-out that never came, an expired session, a purge that failed) does not leave their content for the new user. A purge that fails is captured and does not stop the sign-in: the caches are kept per owner, so the new user cannot read what is left, and the next sign-in tries again.

### `SignOut`

Signs the current user out.

- **Input**: none.
- **Output**: `Void`. Succeeds when nobody was signed in.
- **Errors**: `storageWriteFailed`
- **Ports**: `AuthSession`, `MeetingCache`, `DocumentCache`, `Monitoring`
- **Rules**, in order: lock the app; empty both caches (the stored content of the documents included); forget the session (`AuthSession.signOut`).
- A cache that cannot be emptied is captured and does not make the sign-out fail. **The vote outbox is not touched**: the votes of this user wait for them to come back. The app stays locked; the next sign-in opens it again.

### `UnlockApp`

Unlocks the app with a biometric proof.

- **Input**: none.
- **Output**: `Void`.
- **Errors**: `biometricUnavailable`, `biometricNotEnrolled`, `biometricCancelled`, `biometricFailed`, `biometricLockedOut`
- **Ports**: `BiometricGate`
- **Rules**, in order: check that the biometrics are available (so that a device without them is reported without ever showing a prompt); authenticate with the reason `unlockApp`; **only on success**, unlock the app lock. It fails closed: when the biometrics cannot be used, or the user is not recognised, the app stays locked and nothing else unlocks it.
- The biometrics prove that a person enrolled on this device is present, not that this person is the user of the session. That is the limit of the lock, and the reason the session itself expires.

### `EvaluateAppLock`

When the app returns from the background, decides whether the user must unlock it again.

- **Input**: `{ backgroundedAt: Instant }`, recorded by the presentation when the app went to the background.
- **Output**: `Bool`: true when the user must unlock.
- **Errors**: `storageReadFailed`
- **Ports**: `AuthSession`, `Clock`
- **Rules**, in order:
  1. Read the stored session. If it cannot be read, **lock the app** and return `storageReadFailed` (fails closed).
  2. `now = clock.now()`; `hasSession` is true when there is a session that is not expired at `now`.
  3. Apply [`isUnlockRequired`](domain.md#app-lock) with the setting `gracePeriod` (30 seconds by default).
  4. When required, lock the app. Return the boolean. The answer is the information for the screen; the lock is the enforcement.

### `GetCurrentUser`

Who is signed in, for a screen that applies a rule to the user.

- **Input**: none.
- **Output**: `User`.
- **Errors**: `notAuthenticated`, `sessionExpired`, `appLocked`, `storageReadFailed`
- **Ports**: `AuthSession`, `Clock`, `MeetingCache`, `DocumentCache`, `Monitoring`
- **Rules**: [the session guard](#the-session-guard), then return `session.user`. Nothing is disclosed before the unlock. The presentation also uses it as its periodic "is my session still good" question.

## Connectivity

### `ObserveConnectivity`

Watches the connectivity of the device.

- **Input**: `onChange: (status: ConnectivityStatus) -> Void`. No session is needed: the sign-in screen is as interested in being offline as the meetings are.
- **Output**: `ConnectivityObservation`: `{ status: ConnectivityStatus, unsubscribe: () -> Void }`. `status` is the status when the observation started, including any change that came while it started.
- **Errors**: none
- **Ports**: `Connectivity`
- **Rules**, in order: subscribe **first**, then read `current()`, so that a change that happens in between is not missed (it replaces the status read, which is older); report only a **change** to `onChange` (a status that repeats is not reported, whatever the adapter does), and nothing during the start; `unsubscribe` is idempotent and stops the subscription.
- The application does not decide what a change means: the presentation shows it and calls `SyncPendingVotes` when the connection comes back.

## Meetings

### `ListMeetings`

One page of the upcoming or the past meetings, for the first load, the pull to refresh and the pagination alike.

- **Input**: `{ period: MeetingPeriod, request: PageRequest }`.
- **Output**: `Loaded<Page<MeetingSummary>>`.
- **Errors**: `notAuthenticated`, `sessionExpired`, `appLocked`, `storageReadFailed`, `sessionChanged`, `networkUnavailable`, `unauthorized`, `unexpected`
- **Ports**: `MeetingRepository`, `MeetingCache`, `AuthSession`, `Clock`, `DocumentCache`, `Monitoring`
- **Rules**, in order:
  1. [Session guard](#the-session-guard). The signed-in user is the owner of the cache.
  2. Build the page key `{ period, cursor?, limit }` from the request (the page size is part of the key, because a cursor only means something with the size that produced it).
  3. Apply [the offline policy](#the-offline-policy) with: remote read `MeetingRepository.list(period, request)`; save, read and remove on the page key; the "revoke" of a page is only removing that page. The server decides which meetings are upcoming and which are past.

### `GetMeeting`

A meeting with its agenda, documents and participants.

- **Input**: `{ meetingId: MeetingId }`.
- **Output**: `Loaded<Meeting>`.
- **Errors**: `notAuthenticated`, `sessionExpired`, `appLocked`, `storageReadFailed`, `sessionChanged`, `networkUnavailable`, `notFound`, `unauthorized`, `forbidden`, `unexpected`
- **Ports**: `MeetingRepository`, `MeetingCache`, `DocumentCache`, `AuthSession`, `Clock`, `Monitoring`
- **Rules**: [session guard](#the-session-guard), then [the offline policy](#the-offline-policy) with remote read `MeetingRepository.get(id)`. When the server refuses the meeting (`forbidden`, `notFound`) the cached copy goes **and so do the documents it lists** from the document cache: a document of a meeting that the user can no longer see must not stay readable offline. The documents are read from the cached copy, so they are removed first, then the meeting.

## Documents

### `OpenDocument`

Opens a document for reading.

- **Input**: `{ documentId: DocumentId }`.
- **Output**: `OpenedDocument`: `{ document: Document, location: DocumentLocation, watermark: Watermark, source: DataSource, screenProtected: Bool }`.
- **Errors**: `notAuthenticated`, `sessionExpired`, `appLocked`, `storageReadFailed`, `sessionChanged`, `networkUnavailable`, `notFound`, `unauthorized`, `forbidden`, `unexpected`, `screenProtectionUnsupported`, `screenProtectionFailed`
- **Ports**: `DocumentRepository`, `DocumentCache`, `ScreenProtection`, `Clock`, `AuthSession`, `MeetingCache`, `Monitoring`
- **Rules**, in order:
  1. [Session guard](#the-session-guard); the user is the owner of the cached copy.
  2. Load with [the offline policy](#the-offline-policy). The remote read is two steps: `DocumentRepository.get(id)` and then `DocumentRepository.fetchContent(id)`, which together give a `ViewableDocument` (metadata and location). **The metadata and the content come together**, from the server or from the cache: if any part came from the cache, the whole is stale. Revoking a document removes its cache entry (and its stored content).
  3. Check again that the user who asked is still the one signed in and the app is unlocked (`requireSameUser`), because the load can take long. Otherwise return `sessionChanged` (or the guard error) and protect nothing: the content of one user must never come back under another's name. The watermark is built from the session of this check.
  4. `screenProtected = isConfidential(document) OR source is stale`. A copy in the cache can be older than the last change of the classification of the document (it may have been public when it was saved), so what the cache says about the level is **not trusted**. When protected, call `ScreenProtectionCoordinator.acquire(document.id)`. **Fail closed**: if the protection cannot be enabled, the document is **not** returned and the screen protection error is.
  5. Log `documentOpened` (info) with the document id, the user id, the confidentiality and the freshness.
  6. Return the document, the location, the watermark `createWatermark(user, clock.now())`, the source and `screenProtected`.
- The screen calls `CloseDocument` with the id of the document when it leaves it, exactly once for each time it was opened.

### `CloseDocument`

Called when the viewer leaves a document.

- **Input**: `{ documentId: DocumentId }`.
- **Output**: `Void`.
- **Errors**: `screenProtectionUnsupported`, `screenProtectionFailed`
- **Ports**: `ScreenProtection`
- **Rules**: `ScreenProtectionCoordinator.release(documentId)`. The protection is turned off only if no other protected document is still open. A document that was not opened by `OpenDocument`, or is already closed, is ignored.

### `ObserveScreenCapture`

Watches for screenshots and screen recordings while a document is shown.

- **Input**: `{ documentId: DocumentId }` and `onCapture: (event: ScreenCaptureEvent) -> Void`.
- **Output**: `Unsubscribe`, the function that stops watching.
- **Errors**: `notAuthenticated`, `sessionExpired`, `appLocked`, `storageReadFailed`
- **Ports**: `ScreenProtection`, `AuthSession`, `Clock`, `MeetingCache`, `DocumentCache`, `Monitoring`
- **Rules**, in order:
  1. [Session guard](#the-session-guard) to start. A failure means no subscription.
  2. Subscribe to `ScreenProtection`. For each event: call `onCapture(event)` **at once**, then log `screenCaptureDetected` (warn) with the capture kind, the document id and the user id.
  3. The user id is read **again at the moment of the event** through the session guard: the subscription can outlive a sign-out and a sign-in, and the capture must not be attributed to the user who started watching. When nobody is signed in, or the session is not usable, the event is logged without a user.
  4. Identifiers only, no name and no email.

## Votes

### `CastVote`

Casts the vote of the signed-in user on a resolution. A cast vote is final.

- **Input**: `{ meetingId: MeetingId, resolutionId: ResolutionId, choice: VoteChoice }`.
- **Output**: `CastVoteOutcome`: `{ status: CastVoteStatus, vote: Vote }` with `status` = `submitted` (the server recorded it) or `queued` (it waits in the outbox).
- **Errors**: `notAuthenticated`, `sessionExpired`, `appLocked`, `storageReadFailed`, `sessionChanged`, `networkUnavailable`, `notFound`, `unauthorized`, `forbidden`, `unexpected`, `storageWriteFailed`, `resolutionNotFound`, `notAParticipant`, `noVotingRights`, `resolutionClosed`, `votingWindowOver`, `alreadyVoted`, `biometricUnavailable`, `biometricNotEnrolled`, `biometricCancelled`, `biometricFailed`, `biometricLockedOut`, `voteInProgress`, `votePreviouslyRejected`
- **Ports**: `MeetingRepository`, `MeetingCache`, `DocumentCache`, `VoteOutbox`, `VoteRepository`, `BiometricGate`, `AuthSession`, `Clock`, `Monitoring`
- **Rules**, in order:
  1. **In-flight guard.** If a vote on the same resolution is being cast by this instance, return `voteInProgress` at once, whatever the choice (the first may be waiting for the biometric prompt). The guard is set before the first suspension point and released whatever happens. It does not cover two instances: there the outbox (one vote per voter and resolution) and the server make the second one fail with `alreadyVoted`.
  2. [Session guard](#the-session-guard); its user is the voter.
  3. Load the meeting with [the offline policy](#the-offline-policy) (`loadMeeting`), so a member can vote from a meeting already seen without a network. Errors propagate.
  4. Read the voter's outbox entries for this resolution (`VoteOutbox.findByResolution`); a storage error is returned.
  5. Check [voting eligibility](domain.md#voting-eligibility) on the loaded meeting with the **pending** entries as queued votes and `now = clock.now()`; the error is returned. The meeting may be a stale copy: the server has the last word.
  6. If a **rejected** entry exists for this resolution and voter, return `votePreviouslyRejected` with its reason: the user acknowledges the rejected vote first.
  7. **Biometric confirmation** (`confirmWithBiometrics`: check availability, then authenticate with the reason `confirmVote`), only now that the vote is allowed, so that nobody is prompted for a vote that cannot be cast. Its errors are returned.
  8. Call `requireSameUser(voter)` again: the prompt can take as long as the user likes. Otherwise return `sessionChanged` (or `appLocked`) and **submit and queue nothing**.
  9. Build the vote with `createVote` using `castAt = clock.now()`, then call `VoteRepository.submit(vote)`:
     - **success**: record the vote in the cached meeting ([recording a vote in the cache](#recording-a-vote-in-the-cache)); log `voteSubmitted`; return `status = submitted`.
     - **`networkUnavailable`** (the vote may or may not have been recorded): queue it.
     - **`unexpected`**: capture `voteSubmitFailed`, then queue it with `attempts = 1` (it counts as an attempt).
     - **a voting error** (a business rejection): log `voteRejected` (warn, with the code), **queue nothing**, return the error.
     - **`unauthorized`**: end the session ([ending a refused session](#ending-a-refused-session)), **queue nothing**, return `unauthorized`. The user signs in again and casts the vote again.
  10. **Queueing**: `VoteOutbox.enqueue(pending)` with a pending vote built at `clock.now()`.
  - a storage error: capture `voteEnqueueFailed`, return it;
  - `enqueued`: log `voteQueued`, return `status = queued`;
  - `alreadyQueued` with a **pending** existing vote: return `alreadyVoted` with `source = queued`; with a **rejected** one: return `votePreviouslyRejected` with its reason;
  - `heldByUnreadable` (an entry nobody can read holds the key; it is never overwritten): capture `voteEnqueueFailed`, return `storageWriteFailed` with the cause `unreadable entry holds the key`. The user can discard the unreadable entries from the pending votes list and cast the vote again.
- The idempotency key makes a later replay of a queued vote safe.

### `SyncPendingVotes`

Sends the votes of the signed-in user that wait in the outbox, oldest first, one at a time. A rejected vote is never sent again.

- **Input**: none. Called by the presentation when connectivity is regained, when the app returns to the foreground, and after a sign-in or an unlock. The application layer does not watch the network.
- **Output**: `SyncReport`, one of:
  - `{ outcome: completed, synced, rejected, remaining }`: the whole queue was gone through;
  - `{ outcome: interrupted, synced, rejected, remaining, interruptedBy }`: the run stopped early on a condition that concerns every vote; the rest is still pending. `interruptedBy` is one of `networkUnavailable`, `unauthorized`, `storageWriteFailed`, the session guard errors, `sessionChanged`;
  - `{ outcome: alreadyRunning }`: another run was in progress on this instance; nothing was done.
    `synced` is the list of resolution ids the server recorded; `rejected` is a list of `{ resolutionId, reason }` moved to the rejected state during the run; `remaining` is the number of pending votes still in the outbox, counted again after the run (it falls back on what the run knows if the outbox cannot be read, and the failure is captured as `outboxReadFailed`). A report names resolutions and reasons only, **never the choice**: a ballot is secret.
- **Errors**: `notAuthenticated`, `sessionExpired`, `appLocked`, `storageReadFailed`
- **Ports**: `VoteOutbox`, `VoteRepository`, `MeetingCache`, `DocumentCache`, `AuthSession`, `Clock`, `Monitoring`
- **Rules**, in order:
  1. If a run is in progress on this instance, return `alreadyRunning` at once. The guard is set before the first suspension point: the composition root must share one instance. Across instances or processes, the idempotency key keeps a double send harmless.
  2. [Session guard](#the-session-guard) (it does not run while the app is locked, and a run that meets the lock stops there). Read the voter's outbox; keep the **pending** entries as the queue.
  3. For each pending vote, in order: check that the same user is still signed in (a fresh session guard; another user or none stops the run with `sessionChanged` or the guard error: the votes of a user are never sent under another session), then send `VoteRepository.submit(vote)` and settle it:
     - **recorded**: remove it from the outbox (a failed removal interrupts the run with that storage error), record the vote in the cached meeting, report it in `synced`;
     - **a voting error**: move it to the rejected state with `VoteOutbox.reject(key, reason, now)` (failure interrupts), log `voteRejected`, report it in `rejected`;
     - **`unexpected`**: capture `voteSubmitFailed`; count an attempt (`markAttempt`; a failure is captured as `voteAttemptNotRecorded`); if the attempts reached `maxAttempts` (5 by default) the vote is moved to the rejected state with the reason `voteUndeliverable` (carrying the attempts) and reported in `rejected`; otherwise it **stays pending** and the run goes on with the next one, so that one bad vote cannot block the others for ever;
     - **`networkUnavailable`**: the run stops at once; this vote and the following stay pending; **no attempt is counted**, so being offline never makes a vote undeliverable;
     - **`unauthorized`**: end the session ([ending a refused session](#ending-a-refused-session)) and stop the run; the votes stay in the outbox for the next time their voter signs in.
  4. After the loop, count the remaining pending votes, log `voteSyncCompleted` (info) or `voteSyncInterrupted` (warn, with the error code), and return the report.

### `ListPendingVotes`

The votes of the signed-in user that wait in the outbox, and the ones that ended rejected.

- **Input**: none.
- **Output**: `OutboxContent`: `{ pending: List<PendingVote>, rejected: List<RejectedVote>, unreadable: Int }`, oldest first. `unreadable` is how many entries of the user are kept but can no longer be read as a vote.
- **Errors**: `notAuthenticated`, `sessionExpired`, `appLocked`, `storageReadFailed`, `sessionChanged`
- **Ports**: `VoteOutbox`, `AuthSession`, `Clock`, `MeetingCache`, `DocumentCache`, `Monitoring`
- **Rules**, in order: [session guard](#the-session-guard); `VoteOutbox.list(voterId)` (the port is scoped by voter: the votes of another user are never read); `requireSameUser(voter)` again, because the read takes time and entries are returned to nobody else than the user they belong to (`sessionChanged`, or `appLocked` if the app locked meanwhile); split the votes into pending and rejected.

### `AcknowledgeRejectedVote`

The user has seen that their vote on a resolution was rejected: deletes it from the outbox.

- **Input**: `{ resolutionId: ResolutionId }`.
- **Output**: `Void`.
- **Errors**: `notAuthenticated`, `sessionExpired`, `appLocked`, `storageReadFailed`, `sessionChanged`, `storageWriteFailed`, `voteNotRejected`
- **Ports**: `VoteOutbox`, `AuthSession`, `Clock`, `MeetingCache`, `DocumentCache`, `Monitoring`
- **Rules**, in order:
  1. [Session guard](#the-session-guard); only the vote of the signed-in user can be acknowledged.
  2. `VoteOutbox.findByResolution(resolutionId, voterId)`.
  3. `requireSameUser(voter)` again: if somebody else is signed in by then, or the app is locked, nothing is deleted.
  4. No entry: success (nothing to do), so a double tap is harmless.
  5. The entry is **pending**: `voteNotRejected`. A pending vote is deleted by being sent, never by acknowledging.
  6. Otherwise remove the entry by its idempotency key.

### `DiscardUnreadableVotes`

The user asks to be rid of the entries of their outbox that can no longer be read as a vote.

- **Input**: none.
- **Output**: `Int`: how many entries were deleted.
- **Errors**: `notAuthenticated`, `sessionExpired`, `appLocked`, `storageReadFailed`, `sessionChanged`, `storageWriteFailed`
- **Ports**: `VoteOutbox`, `AuthSession`, `Clock`, `MeetingCache`, `DocumentCache`, `Monitoring`
- **Rules**, in order:
  1. [Session guard](#the-session-guard); only the entries of the signed-in user are discarded.
  2. `VoteOutbox.discardUnreadable(voterId)`. Nothing else deletes these entries: a read, a vote queued under their key and a synchronisation all leave them where they are, because an entry nobody can read may still be the only trace of a vote.
  3. `requireSameUser(voter)` again: if somebody else is signed in now, or the app is locked, the answer is `sessionChanged` (or `appLocked`) and nothing is logged. The entries of the user who asked are gone either way: they confirmed it.
  4. Log `unreadableVotesDiscarded` (warn) with the count, and return the count. Asking again deletes nothing and says zero.
- The screen says how many entries there are before it asks, and asks for a confirmation.

## Enumerations

Each table lists the exact values of a constant of the application layer (an object, a list or a set of stable strings). The conformance test compares each table with the constant it is named after.

### `SESSION_RESTORE`

| Value            | Meaning                                                                                  |
| ---------------- | ---------------------------------------------------------------------------------------- |
| `none`           | Nobody is signed in: show the sign-in screen                                             |
| `unlockRequired` | Somebody is signed in, but the app stays locked until they unlock it with the biometrics |

### `CAST_VOTE_STATUS`

| Value       | Meaning                                                                                   |
| ----------- | ----------------------------------------------------------------------------------------- |
| `submitted` | The server has recorded the vote                                                          |
| `queued`    | It could not be delivered now: it waits in the outbox and `SyncPendingVotes` will send it |

### `SYNC_OUTCOME`

| Value            | Meaning                                                                                    |
| ---------------- | ------------------------------------------------------------------------------------------ |
| `completed`      | The whole queue was gone through. Votes that failed unexpectedly may remain, to be retried |
| `interrupted`    | The run stopped early on a condition that concerns every vote; the rest is still pending   |
| `alreadyRunning` | Another run of the same use case was in progress: nothing was done                         |

### `FRESHNESS`

| Value   | Meaning                                                         |
| ------- | --------------------------------------------------------------- |
| `fresh` | The data comes straight from the remote source                  |
| `stale` | The data comes from the local cache; it says when it was cached |

### `CACHE_RESOURCE`

What is being cached, for the logs.

| Value         | Meaning                                     |
| ------------- | ------------------------------------------- |
| `meetingPage` | A page of a list of meetings                |
| `meeting`     | A meeting with its detail                   |
| `document`    | A document with the location of its content |

### `SESSION_ENDING_CODES`

The failures that end the session (see [the session policy](#the-session-policy)).

| Value              | Meaning                                                     |
| ------------------ | ----------------------------------------------------------- |
| `unauthorized`     | The server refused the session                              |
| `notAuthenticated` | Nobody is signed in                                         |
| `sessionExpired`   | The expiry of the session has passed                        |
| `sessionChanged`   | Somebody else is signed in now                              |
| `appLocked`        | The session is good, but the app is locked until the unlock |

### `RETRYABLE_CODES`

The failures that asking again can fix (see [the session policy](#the-session-policy)).

| Value                    | Meaning                                                     |
| ------------------------ | ----------------------------------------------------------- |
| `networkUnavailable`     | The connection may be back                                  |
| `unexpected`             | A fault of the server may have passed                       |
| `storageReadFailed`      | A store may be readable again                               |
| `screenProtectionFailed` | The platform may manage to protect the screen the next time |

## Settings

Configuration is set once by the composition root and passed to the use cases. The values below are the defaults of the app (`src/di/config.ts`); the conformance test compares each value and unit with the code. Durations are in milliseconds.

| Setting                          | Value     | Meaning                                                                                                                      |
| -------------------------------- | --------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `MAX_CACHE_AGE`                  | 604800000 | `maxCacheAge`: seven days. How old a cached entry may be and still be served as stale data; an older entry counts as a miss  |
| `MAX_VOTE_DELIVERY_ATTEMPTS`     | 5         | `maxAttempts`: after this many unexpected failures a vote is given up (rejected as `voteUndeliverable`)                      |
| `APP_LOCK_GRACE_PERIOD`          | 30000     | `gracePeriod`: 30 seconds. How long the app may stay in the background without asking for the biometrics again               |
| `MEETINGS_PAGE_SIZE`             | 10        | The page size the app asks for                                                                                               |
| `HTTP_REQUEST_TIMEOUT`           | 15000     | How long a request to the API may take, the answer included, before it counts as `networkUnavailable`                        |
| `DOCUMENT_DOWNLOAD_TIMEOUT`      | 60000     | The same for the download of the content of a document                                                                       |
| `MIN_HTTP_REQUEST_TIMEOUT`       | 1000      | The smallest request timeout the configuration accepts                                                                       |
| `MAX_HTTP_REQUEST_TIMEOUT`       | 60000     | The largest request timeout the configuration accepts                                                                        |
| `ALLOW_DEVICE_PASSCODE_FALLBACK` | false     | Whether the passcode of the device is accepted when the biometrics do not recognise the user. No: a vote is secret and final |
| `MOCK_SESSION_LIFETIME`          | 28800000  | Mock configuration only: the lifetime of a simulated session, eight hours                                                    |

## Constants

A fixed number of the application layer, which no configuration changes. The conformance test compares each value with the exported constant of that name in `src/application/shared`. Durations are in milliseconds.

| Constant                        | Value | Meaning                                                                                                                                                                                           |
| ------------------------------- | ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `SESSION_CHECK_INTERVAL_MILLIS` | 30000 | How often an app that stays open and in the foreground checks its session: thirty seconds. The check is local (the guard reads the stored session and the clock), so a short period costs nothing |
