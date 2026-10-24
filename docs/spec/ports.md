# Ports

A port is an interface owned by the application layer. The use cases (see [use-cases.md](use-cases.md)) call ports and never an adapter; an adapter implements a port against a technology (HTTP, SQLite, the secure storage of the device, a simulated server). The React Native app and a Flutter version of it implement the same ports with the same contracts: this file is that contract. Types such as `Meeting`, `Vote` or `UserId`, and the error codes, are defined in [domain.md](domain.md). The notation is the one of [README.md](README.md): `Text`, `Int`, `Bool`, `Void`, `Instant`, `Duration`, `List<T>`, `Page<T>`, `T?` for an optional or absent value, `Result<T, E>` for a success value or a coded error, and records written `{ field: Type, field?: Type }`.

Operations are asynchronous unless a row says otherwise (`Clock.now`, and the two `subscribe` operations return at once). Parameter names are the ones of the code and are checked by the conformance test (`tooling/spec.test.ts`).

## Rules shared by every port

These rules hold for every operation of every port. Each port repeats only what it adds.

1. **Nothing throws and nothing rejects.** A failure is an error `Result`, never an exception. An unexpected fault inside an adapter is turned into the error the contract names (`unexpected`, `storageReadFailed`, `storageWriteFailed`).
2. **Every operation settles in bounded time.** A request that times out is `networkUnavailable`; a store that does not answer in time is a storage error. The only waits that belong to the user are the biometric prompt (`BiometricGate.authenticate`), which always ends with a result, `biometricCancelled` included.
3. **Errors carry codes, not text.** The `code` is a stable string (see domain.md). An optional `cause` is a technical diagnostic, a status code or a kind of failure, and never holds personal data, a credential, a token, a path, a URL, the location or title of a document, a name, an email, an identifier taken from a query, or the choice of a vote.
4. **Caches are scoped by owner.** Every entry of `MeetingCache` and `DocumentCache` belongs to an `owner` (the user whose session fetched it) and every operation takes the owner. Reading as another owner finds nothing, by construction.
5. **Storage keys are injective.** Owners, identifiers, cursors and periods are free text. A key is built by encoding (JSON, length prefixes, separate columns), never by concatenating with a separator, and never normalised (no trimming, no case folding, no Unicode normalisation). Two different (owner, id) pairs never share an entry, whatever characters they contain.
6. **Copies, not references.** What is given to a `save` and what a read returns are copies, never shared with the store.
7. **A miss is a value, not an error.** A read that finds nothing succeeds with an absent value.
8. **Idempotent writes.** `save`, `remove`, `purge`, `enable`, `disable`, `signOut` and the unsubscribe functions can be repeated without a different effect; the exceptions are named in the port (`markAttempt` counts every call).

## Port index

| Port                 | Role                                                              | Adapters                                                                                                                      |
| -------------------- | ----------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `AuthSession`        | Signs in, remembers who is signed in, signs out                   | `HttpAuthSession` (http), `InMemoryAuthSession` (mock)                                                                        |
| `BiometricGate`      | The biometric check of the device                                 | `DeviceBiometricGate` (http), `DeviceBiometricGate` or, with none enrolled, `InMemoryBiometricGate` (mock)                    |
| `Clock`              | The only way to read the time                                     | `SystemClock` (both)                                                                                                          |
| `Connectivity`       | What the device says about its connection                         | `ExpoConnectivity` (http), `SimulatedConnectivity` (mock)                                                                     |
| `DocumentCache`      | Local copy of documents already viewed, per owner                 | `SqliteDocumentCache` (http), `InMemoryDocumentCache` (mock)                                                                  |
| `DocumentRepository` | Remote source of truth for documents, read only                   | `HttpDocumentRepository` (http), `InMemoryDocumentRepository` (mock)                                                          |
| `MeetingCache`       | Local copy of meeting pages and meetings already seen, per owner  | `SqliteMeetingCache` (http), `InMemoryMeetingCache` (mock)                                                                    |
| `MeetingRepository`  | Remote source of truth for meetings, read only                    | `HttpMeetingRepository` (http), `InMemoryMeetingRepository` (mock)                                                            |
| `Monitoring`         | Structured logs and error reports, fire and forget                | `ConsoleMonitoring` (default), `SentryMonitoring` (when a crash reporter address is configured)                               |
| `ScreenProtection`   | Blocks screenshots and recording, reports capture attempts        | `NativeScreenProtection` (http, and mock when the native module exists), `InMemoryScreenProtection` (mock without the module) |
| `VoteOutbox`         | Durable local queue of votes not yet delivered, and rejected ones | `SqliteVoteOutbox` (http), `InMemoryVoteOutbox` (mock)                                                                        |
| `VoteRepository`     | Remote source that records votes                                  | `HttpVoteRepository` (http), `InMemoryVoteRepository` (mock)                                                                  |

### Configurations

The composition root builds one adapter for each port, in one of two configurations selected by the setting `adapters` (`mock` or `http`). A Flutter version needs the same two wirings, or any equivalent pair of a real one and a simulated one.

| Configuration | Remote ports                                                                                                                                                                    | Local ports                                                                                                                                                                                                                                |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `http`        | The three repositories and the sign-in talk to the API ([../api.md](../api.md)) through one HTTP client that reads the token of the signed-in user when it creates each request | Caches and outbox in one local database, encrypted with a key held only by the secure storage; document content in app-private files; biometrics, connectivity and screen protection of the device                                         |
| `mock`        | The three repositories are windows on one simulated server with the seed of [fixtures/](fixtures/) and one simulated network that can be cut                                    | Caches and outbox in memory (lost when the app stops); document content in app-private files; biometrics are the device's where a finger or a face is enrolled, else they always succeed; connectivity is the one of the simulated network |

The simulated server and the HTTP server must answer the same way: the same rules, the same data. The `Clock` and the `Monitoring` are the same in both configurations.

## Types used by the ports

These are the records and aliases that appear in the signatures below. They are not ports and are not checked as such.

| Type                  | Definition                                                                                                                                                                                                                                         |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Session`             | `{ user: User, expiresAt: Instant }`. Holds no secret. `expiresAt` is on the device clock (see AuthSession)                                                                                                                                        |
| `Credentials`         | `{ email: EmailAddress, password: Text }`. Built by the domain; the password is kept exactly as typed                                                                                                                                              |
| `CacheEntry<T>`       | `{ value: T, cachedAt: Instant }`. `cachedAt` is the instant given to the `save` that stored the value; the cache never reads a clock itself. The application compares it with the clock to refuse an entry that is too old or dated in the future |
| `MeetingPageKey`      | `{ period: MeetingPeriod, cursor?: PageCursor, limit: Int }`. Identifies a cached page. The first page has no cursor. The page size is part of the key because a cursor only means something with the size that produced it                        |
| `ViewableDocument`    | `{ document: Document, location: DocumentLocation }`. A document that can be shown: its metadata and where its content is                                                                                                                          |
| `PendingVote`         | `{ status: "pending", vote: Vote, enqueuedAt: Instant, attempts: Int }`. `attempts` counts failures that said nothing about the vote itself                                                                                                        |
| `RejectedVote`        | `{ status: "rejected", vote: Vote, enqueuedAt: Instant, attempts: Int, reason: RejectionReason, rejectedAt: Instant }`. Kept by the outbox, never sent again, until the user acknowledges it                                                       |
| `OutboxVote`          | `PendingVote` or `RejectedVote`, told apart by `status`. A rejected vote always has a reason; a pending one never has                                                                                                                              |
| `RejectionReason`     | A voting error (see domain.md), or `voteUndeliverable` with `attempts: Int` (the app gave up after that many unexpected failures)                                                                                                                  |
| `EnqueueResult`       | One of `{ outcome: "enqueued" }`, `{ outcome: "alreadyQueued", existing: OutboxVote }`, `{ outcome: "heldByUnreadable" }`                                                                                                                          |
| `OutboxListing`       | `{ votes: List<OutboxVote>, unreadable: Int }`. Votes are oldest first                                                                                                                                                                             |
| `ScreenCaptureEvent`  | `{ kind: ScreenCaptureKind }`                                                                                                                                                                                                                      |
| `Unsubscribe`         | A function with no parameter and no result that stops a subscription. Calling it again does nothing                                                                                                                                                |
| `SignInFailure`       | `invalidCredentials`, `networkUnavailable`, `unexpected`, `storageWriteFailed`                                                                                                                                                                     |
| `VoteSubmissionError` | A gateway error or a voting error: the six voting codes plus `networkUnavailable`, `unauthorized`, `unexpected`                                                                                                                                    |
| `LogAttributes`       | A map from a name of `LOG_ATTRIBUTE` to a `Text`, a number or a `Bool`. Optional entries only                                                                                                                                                      |

The idempotency key of a vote is `<length of the resolution id>.<resolution id>.<voter id>` (see domain.md). Every `IdempotencyKey` in a signature below is that value.

### Error sets

The `Errors` column below names codes. These sets are used as shorthand in the `Result` column.

| Set                          | Codes                                                                                                             |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `GatewayError`               | `networkUnavailable`, `unauthorized`, `unexpected`                                                                |
| `RepositoryError`            | the gateway codes, plus `notFound`, `forbidden`                                                                   |
| `StorageError`               | `storageReadFailed`, `storageWriteFailed`                                                                         |
| `BiometricAvailabilityError` | `biometricUnavailable`, `biometricNotEnrolled`                                                                    |
| `BiometricError`             | the availability codes, plus `biometricCancelled`, `biometricFailed`, `biometricLockedOut`                        |
| `ScreenProtectionError`      | `screenProtectionUnsupported`, `screenProtectionFailed`                                                           |
| `VotingError`                | `resolutionNotFound`, `notAParticipant`, `noVotingRights`, `resolutionClosed`, `votingWindowOver`, `alreadyVoted` |

## Ports

The ports are in alphabetical order. For each one, the table lists its operations; the notes under it are its contract. Each table row is checked against the code: the port, its operations, and the parameter names must be those of the interface.

### `AuthSession`

Signs the user in, remembers who is signed in, and signs them out. The tokens that prove it stay inside the adapter (in the secure storage of the device): the application only sees a `Session`.

| Operation | Parameters                 | Result                                     | Errors                                                                         |
| --------- | -------------------------- | ------------------------------------------ | ------------------------------------------------------------------------------ |
| `signIn`  | `credentials: Credentials` | `Result<Session, SignInFailure>`           | `invalidCredentials`, `networkUnavailable`, `unexpected`, `storageWriteFailed` |
| `current` | -                          | `Result<Session?, StorageReadFailedError>` | `storageReadFailed`                                                            |
| `signOut` | -                          | `Result<Void, StorageWriteFailedError>`    | `storageWriteFailed`                                                           |

Contract:

- `signIn` checks the credentials with the server and, when they are accepted, stores and returns the new session. It replaces any session that exists **atomically**: there is no instant at which the adapter holds the tokens of two users, or none while a sign-in succeeds. A refused sign-in leaves the current session as it was.
- `expiresAt` is computed on the **device clock** at sign-in, as `Clock.now()` plus the lifetime the server grants. The adapter never copies a timestamp of the server. The server enforces its own expiry on every call; the local value only decides when the app stops offering the session.
- Every request made by the adapters of the remote ports carries the identity that was read **when the request was created**, never that of a user who signs in later.
- `current` returns the stored session as stored, **even when its expiry has passed**; deciding that is the job of the application, with the clock. It succeeds with an absent value when nobody is signed in.
- `signOut` forgets the session and its tokens. Signing out when nobody is signed in succeeds. The device only forgets the token; there is no revocation call.
- A refusal of the sign-in because the email or the password is wrong is `invalidCredentials`; an unknown email and a wrong password are not told apart.

### `BiometricGate`

The biometric check of the device (fingerprint, face). It proves that **a person enrolled on this device** is present. It does not prove that this person is the user of the session: a device may hold several fingerprints.

| Operation           | Parameters                | Result                                     | Errors                                                                                                        |
| ------------------- | ------------------------- | ------------------------------------------ | ------------------------------------------------------------------------------------------------------------- |
| `checkAvailability` | -                         | `Result<Void, BiometricAvailabilityError>` | `biometricUnavailable`, `biometricNotEnrolled`                                                                |
| `authenticate`      | `reason: BiometricReason` | `Result<Void, BiometricError>`             | `biometricUnavailable`, `biometricNotEnrolled`, `biometricCancelled`, `biometricFailed`, `biometricLockedOut` |

Contract:

- `checkAvailability` succeeds when biometrics can be used right now: the hardware is present and at least one fingerprint or face is enrolled. It settles in bounded time.
- `authenticate` shows the system prompt for a reason and succeeds only when the user is recognised. A refusal of the user is an error `Result`, not an exception. The prompt waits for the user, so its duration is theirs, but it **always ends with a result**, `biometricCancelled` included.
- No text travels through the port: the application names a reason (`unlockApp`, `confirmVote`) and the adapter or the presentation turns it into the text of the system prompt, in the language of the user.
- Whether the device passcode is accepted when the biometrics fail is a setting of the adapter, chosen at the composition root (`false` today: a passcode can be seen being typed, a face or a fingerprint cannot). Nothing in the port or in the application depends on the choice.
- The application always calls `checkAvailability` before `authenticate`, so a device without biometrics is reported without ever showing a prompt.

### `Clock`

The only way the domain and the application read the time. Business code never reads the system time directly, so every rule that depends on time can be tested with a clock set by hand.

| Operation | Parameters | Result                                | Errors |
| --------- | ---------- | ------------------------------------- | ------ |
| `now`     | -          | `Instant` (synchronous, not a Result) | -      |

Contract:

- Returns the current instant on the clock of the device. Never fails.
- The device clock is not trustworthy (the user can set it). The rules built on it account for that and fail closed: see the app lock and the cache age in domain.md.

### `Connectivity`

What the device says about its connection. It is a **hint, never the truth**: the answer of a remote call is. A device that reports `online` may still fail to reach the server, and one that reports `offline` may be about to recover, so the offline policy goes by the error of the call and not by this port. The port exists to tell the presentation when to show that the device is offline, and when to trigger `SyncPendingVotes`: the application layer does not watch the network by itself.

| Operation   | Parameters                                       | Result                                            | Errors |
| ----------- | ------------------------------------------------ | ------------------------------------------------- | ------ |
| `current`   | -                                                | `ConnectivityStatus` (asynchronous, not a Result) | -      |
| `subscribe` | `listener: (status: ConnectivityStatus) => Void` | `Unsubscribe` (synchronous, not a Result)         | -      |

Contract:

- No operation throws or rejects, and `current` settles in bounded time.
- When the platform cannot say, the status is `online`: the calls then answer for themselves, and an app that wrongly says `offline` for ever would be worse than one that tries and fails.
- `subscribe` does **not** call the listener when it subscribes (ask `current` for the starting point). It then calls it for each change of the status, **never twice in a row with the same status**, until the returned function is called.
- Calling the returned function again does nothing, and it does not affect the other subscribers. A listener must not throw; an adapter that meets one that does reports it (`connectivityListenerFailed`) and tells the others all the same.

### `DocumentCache`

The local store that lets documents already viewed be opened offline. It keeps the metadata and the location of the content; the content itself stays where the location points, in storage the adapter owns.

| Operation | Parameters                                                     | Result                                                          | Errors               |
| --------- | -------------------------------------------------------------- | --------------------------------------------------------------- | -------------------- |
| `save`    | `owner: UserId, viewable: ViewableDocument, cachedAt: Instant` | `Result<Void, StorageWriteFailedError>`                         | `storageWriteFailed` |
| `read`    | `owner: UserId, id: DocumentId`                                | `Result<CacheEntry<ViewableDocument>?, StorageReadFailedError>` | `storageReadFailed`  |
| `remove`  | `owner: UserId, id: DocumentId`                                | `Result<Void, StorageWriteFailedError>`                         | `storageWriteFailed` |
| `purge`   | -                                                              | `Result<Void, StorageWriteFailedError>`                         | `storageWriteFailed` |

Contract (in addition to the shared rules):

- **Scoping.** Every entry belongs to an owner; the storage key is injective in (owner, document id).
- A read that finds nothing succeeds with an absent value. It is **also a miss when the entry is there but the stored content is gone** (the file was deleted, the storage was cleared): a location that points nowhere is never returned.
- `save` replaces what is stored for the same owner and document. `remove` of an absent entry succeeds. Both are idempotent.
- `remove` and `purge` also delete the stored **content**, not only the entry: a confidential file must not outlive its entry. `purge` removes every entry of every owner. The content is deleted first, then the entry: if the content cannot be deleted, the call returns `storageWriteFailed` and reports nothing as deleted (the entry stays, so the call can be repeated). An entry is never dropped while its file is left behind with nothing pointing at it.
- Files that no entry points at (a download whose entry was never saved, a deletion that was interrupted) are swept when the cache starts.
- Several entries may point at the same location (two owners, one file). The file is deleted only when the last entry that points at it is dropped. Adapters count the references, or keep one file per owner.
- A `save` that fails must not leave an older entry readable as if it were current.
- The content lives in app-private storage excluded from backups (no cloud backup). It is protected by the sandbox and the data protection of the platform; the app does not encrypt it. The system may empty a caches directory: a file that is gone makes the entry a miss.

### `DocumentRepository`

The remote source of truth for documents. Read only.

| Operation      | Parameters       | Result                                      | Errors                                                                      |
| -------------- | ---------------- | ------------------------------------------- | --------------------------------------------------------------------------- |
| `get`          | `id: DocumentId` | `Result<Document, RepositoryError>`         | `networkUnavailable`, `unauthorized`, `unexpected`, `notFound`, `forbidden` |
| `fetchContent` | `id: DocumentId` | `Result<DocumentLocation, RepositoryError>` | `networkUnavailable`, `unauthorized`, `unexpected`, `notFound`, `forbidden` |

Contract:

- Failures are the ones described for `MeetingRepository`, with the same rule for the `cause` of `unexpected`. `unauthorized` means the session is no longer valid; `forbidden` means this user may not have this document.
- `fetchContent` makes the content of the document readable on the device and says where. The adapter downloads it to app-private storage (out of the backups), **written whole or not at all**, so the location stays valid offline. Calling it twice for the same document is safe: the content is fetched again and replaces the file.
- The download has a budget of its own, longer than a request for metadata (a minute today, against 15 seconds), since a file takes longer than a page of JSON. Past it the failure is `networkUnavailable` and nothing is stored.
- **A download may be reused only for the same signed-in user and the same version of the document.** The location is never the same for two users, and a new version of a document (its content or its classification changed on the server) is downloaded again. Reusing a file for another user would show them content they may not have; reusing it across versions would show content that has been withdrawn.
- The location is opaque to the domain and the application: they carry it from the adapter to the viewer and never read it.

### `MeetingCache`

The local store that lets meetings already seen be read offline. Pages of the two lists and full meetings are stored separately.

| Operation       | Parameters                                                                          | Result                                                              | Errors               |
| --------------- | ----------------------------------------------------------------------------------- | ------------------------------------------------------------------- | -------------------- |
| `savePage`      | `owner: UserId, key: MeetingPageKey, page: Page<MeetingSummary>, cachedAt: Instant` | `Result<Void, StorageWriteFailedError>`                             | `storageWriteFailed` |
| `readPage`      | `owner: UserId, key: MeetingPageKey`                                                | `Result<CacheEntry<Page<MeetingSummary>>?, StorageReadFailedError>` | `storageReadFailed`  |
| `removePage`    | `owner: UserId, key: MeetingPageKey`                                                | `Result<Void, StorageWriteFailedError>`                             | `storageWriteFailed` |
| `saveMeeting`   | `owner: UserId, meeting: Meeting, cachedAt: Instant`                                | `Result<Void, StorageWriteFailedError>`                             | `storageWriteFailed` |
| `readMeeting`   | `owner: UserId, id: MeetingId`                                                      | `Result<CacheEntry<Meeting>?, StorageReadFailedError>`              | `storageReadFailed`  |
| `removeMeeting` | `owner: UserId, id: MeetingId`                                                      | `Result<Void, StorageWriteFailedError>`                             | `storageWriteFailed` |
| `purge`         | -                                                                                   | `Result<Void, StorageWriteFailedError>`                             | `storageWriteFailed` |

Contract (in addition to the shared rules):

- **Scoping.** An entry is stored under its owner and found under it only, so a device shared by two users never shows the data of one to the other. The data of an owner is removed when they sign out (`purge`).
- A read that finds nothing succeeds with an absent value (a miss).
- `save*` replaces what is stored under the same owner and key. `remove*` of an absent entry succeeds. Both are idempotent. `purge` removes every entry of every owner and succeeds when there is none.
- **A `save` that fails must not leave an older entry readable as if it were current**: the older entry is removed (or never left in place) before the error is returned, so the next read is a miss. The application also removes the entry itself after a failed write, and empties the caches when it cannot; the rule is for the adapter, which must not depend on that.
- The storage key is injective in (owner, id), and the same goes for the parts of a page key (period, cursor, page size).
- The data is at rest on the device: it lives in app-private storage, excluded from backups.
- The `cachedAt` of an entry is the instant given to the `save` call. Recording a vote on a cached meeting (`saveMeeting` with the old `cachedAt`) does not make the copy younger.

### `MeetingRepository`

The remote source of truth for meetings. Read only.

| Operation | Parameters                                    | Result                                       | Errors                                                                      |
| --------- | --------------------------------------------- | -------------------------------------------- | --------------------------------------------------------------------------- |
| `list`    | `period: MeetingPeriod, request: PageRequest` | `Result<Page<MeetingSummary>, GatewayError>` | `networkUnavailable`, `unauthorized`, `unexpected`                          |
| `get`     | `id: MeetingId`                               | `Result<Meeting, RepositoryError>`           | `networkUnavailable`, `unauthorized`, `unexpected`, `notFound`, `forbidden` |

Contract:

- `list` returns one page of the meetings of a period: **upcoming ones soonest first, past ones latest first**. Which meetings are upcoming is decided by the server against its own clock. A listing addresses no particular item, so it cannot be `notFound` or `forbidden`.
- `get` returns a meeting with its agenda (sorted by position), documents and participants. Its resolutions carry the vote of the user who asks, as the server recorded it, and nobody else's.
- Failure meanings:
  - `networkUnavailable`: the server cannot be reached (a request that times out included). The only error the offline policy recovers from.
  - `unauthorized`: the **session** is no longer valid (expired, revoked, signed out elsewhere). It concerns everything the caller holds, and the application empties both caches.
  - `forbidden`: the session is valid but this user may not see **this item** (removed from the meeting). The application drops it, and what hangs off it, from the caches. A server that prefers not to reveal that an item exists answers `notFound` instead, and the application treats the two the same way.
  - `notFound`: the item does not exist.
  - `unexpected`: anything else. Its free-text `cause` is a status code or a kind of failure and nothing else.
- A request carries the identity read when it was created (the token of the user who was signed in then): a request in flight is answered for that user, never for one who signed in while it was on its way. The application checks again, when the answer arrives, that the same user is still signed in.
- The wire format of the HTTP adapter is in [../api.md](../api.md).

### `Monitoring`

Structured logs and error reports, sent to whatever tool the adapter wraps. **Fire and forget.**

| Operation      | Parameters                                                            | Result                             | Errors |
| -------------- | --------------------------------------------------------------------- | ---------------------------------- | ------ |
| `log`          | `level: LogLevel, event: MonitoringEvent, attributes?: LogAttributes` | `Void` (synchronous, not a Result) | -      |
| `captureError` | `event: MonitoringEvent, error: AppError, attributes?: LogAttributes` | `Void` (synchronous, not a Result) | -      |

Contract:

- Both operations return nothing, return at once, wait for nothing and never throw, whatever happens to the tool behind them. Monitoring must not decide whether the app runs.
- A call site names one of the events of `MONITORING_EVENT`, never a free text, so events can be counted, alerted on and searched for.
- Attributes are named by `LOG_ATTRIBUTE`. They hold **identifiers, codes and counts only**: never a name, an email, a password, the content of a document, a file path, a URL, the location or title of a document, nor the choice of a vote (the ballot is secret). The `cause` of an error that reaches the tool follows the same rule.
- Convention in the use cases: an error that is **returned** to the caller is the caller's to report; an error that a use case **swallows** (a cache that cannot be written, say) is captured here, so that it does not vanish.
- Expected behaviour is logged at level `info` (a copy served from the cache), a problem at `warn`.
- The adapter is the console by default; with an address of a crash reporter in the build configuration, it is that reporter. An address that is not valid, or a reporter that does not start, never stops the app: the console stays and says why once (`monitoringNotStarted`).

### `ScreenProtection`

Blocks screenshots and screen recording while a confidential screen is shown, and reports attempts. The port is deliberately dumb: it is **one global switch with no memory of who asked for it**. Which documents need it, and when the last one has gone, is decided by the application (a coordinator that counts the open views of each document and turns the protection off only when the last one closes), so that every adapter behaves the same.

| Operation   | Parameters                                      | Result                                    | Errors                                                  |
| ----------- | ----------------------------------------------- | ----------------------------------------- | ------------------------------------------------------- |
| `enable`    | -                                               | `Result<Void, ScreenProtectionError>`     | `screenProtectionUnsupported`, `screenProtectionFailed` |
| `disable`   | -                                               | `Result<Void, ScreenProtectionError>`     | `screenProtectionUnsupported`, `screenProtectionFailed` |
| `subscribe` | `listener: (event: ScreenCaptureEvent) => Void` | `Unsubscribe` (synchronous, not a Result) | -                                                       |

Contract:

- `enable` and `disable` settle in bounded time and are **idempotent**. `disable` succeeds when the protection was already off.
- `enable` has taken effect **when it resolves**: a screen shown after it is protected (a capture started afterwards is blocked, and the app switcher shows no content).
- `enable` fails when the platform cannot provide the protection (`screenProtectionUnsupported`) or when turning it on failed (`screenProtectionFailed`). A caller that cannot enable the protection must not show the confidential content.
- Calls are **applied in the order they were issued**: a `disable` issued before an `enable` can never land after it. The application also serialises its own calls.
- `subscribe` calls the listener for each capture event until the returned function is called. A listener must not throw; an adapter that meets one that does reports it (`screenProtectionListenerFailed`) and tells the others all the same.
- Capture kinds are the values of `SCREEN_CAPTURE_KIND`. Whether a platform can report each kind is up to the platform.

### `VoteOutbox`

The durable local queue of votes cast without a network, waiting to be sent, and of the votes that ended rejected until the user acknowledges them. It must survive the app being closed. It is **not cleared when a user signs out**: a vote is scoped by its voter and must be sent when they come back.

| Operation           | Parameters                                                          | Result                                             | Errors               |
| ------------------- | ------------------------------------------------------------------- | -------------------------------------------------- | -------------------- |
| `enqueue`           | `pending: PendingVote`                                              | `Result<EnqueueResult, StorageWriteFailedError>`   | `storageWriteFailed` |
| `list`              | `voterId: UserId`                                                   | `Result<OutboxListing, StorageReadFailedError>`    | `storageReadFailed`  |
| `discardUnreadable` | `voterId: UserId`                                                   | `Result<Int, StorageWriteFailedError>`             | `storageWriteFailed` |
| `findByResolution`  | `resolutionId: ResolutionId, voterId: UserId`                       | `Result<List<OutboxVote>, StorageReadFailedError>` | `storageReadFailed`  |
| `markAttempt`       | `key: IdempotencyKey`                                               | `Result<Void, StorageWriteFailedError>`            | `storageWriteFailed` |
| `reject`            | `key: IdempotencyKey, reason: RejectionReason, rejectedAt: Instant` | `Result<Void, StorageWriteFailedError>`            | `storageWriteFailed` |
| `remove`            | `key: IdempotencyKey`                                               | `Result<Void, StorageWriteFailedError>`            | `storageWriteFailed` |

Operations:

- `enqueue` appends a pending vote, unless one with the same idempotency key is already in the outbox, **whatever its state**. A voter has one vote per resolution, so a second one is never queued. The answer says which case it was: `enqueued`; `alreadyQueued` with the vote that holds the key (pending or rejected); or `heldByUnreadable` (see Quarantine).
- `list` returns the votes of a voter, pending and rejected, **oldest first (the order of enqueueing)**, and the number of entries of that voter that cannot be read. Pending votes are sent in that order.
- `discardUnreadable` removes the unreadable entries of the voter and says how many. It is the **one way they leave**. Asking again removes nothing and says zero. The readable votes and the entries of anybody else are not touched.
- `findByResolution` returns the votes of a voter on a resolution, pending and rejected; empty when there is none.
- `markAttempt` counts one more attempt on a pending vote. It does nothing when the key is unknown or the vote is rejected.
- `reject` moves a pending vote to the rejected state with its reason and the instant. It does nothing when the key is unknown or the vote is already rejected.
- `remove` removes a vote, pending or rejected. It does nothing when the key is unknown, and it does not remove an unreadable entry.

Contract:

- **Scoping by voter.** Reads (`list`, `findByResolution`, `discardUnreadable`) take the voter and never return the vote of anybody else. A key already holds the voter (see the idempotency key), which scopes the writes.
- **Lookup by the whole key.** Two keys that share a prefix, or differ only in case, are two votes; a lookup by prefix or substring would merge them.
- **Idempotent writes:** `enqueue` (a second call with the same key changes nothing and says so), `reject`, `remove` and `discardUnreadable`. **Not idempotent:** `markAttempt` counts one more attempt every time it is called.
- **Protection at rest.** It holds the choices of secret ballots and outlives the sign-out, so an adapter stores it **encrypted** (the keystore or secure storage of the device), in app-private storage excluded from backups. Its content is never logged.
- It is read and written by the casting of a vote (a vote that could not be delivered), the synchronisation, the listing of pending votes and the acknowledgement of a rejected vote.
- Only a store that cannot be read or written returns a storage error. A store that does not answer in time is a storage error.
- The in-memory adapter of the `mock` configuration honours every rule above except durability across a restart of the app.

#### Quarantine of unreadable entries

An entry of the outbox that **can no longer be read back as a vote** (the store was altered, or written by something else) is quarantined, never deleted by a read and never overwritten. A vote is the choice of a person; an entry that no longer reads back may still be the only trace of it.

- It is kept **out of the queue**: it is not sent, not offered, not in `votes`.
- It is **counted** in `OutboxListing.unreadable`, so the user can be told how many there are.
- It is removed only by `discardUnreadable`, which the user asks for after being told the count and confirming.
- `reject` and `markAttempt` do not touch it; `remove` does not delete it; `enqueue` of a vote under its key answers `heldByUnreadable` and queues nothing. The vote is then not queued and the caller reports `storageWriteFailed`; the user can discard the entry and cast the vote again.
- An outbox that holds its entries as typed values (the in-memory adapter) has none: `unreadable` is always 0.

### `VoteRepository`

The remote source that records votes.

| Operation | Parameters   | Result                              | Errors                                                                                                                                                                |
| --------- | ------------ | ----------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `submit`  | `vote: Vote` | `Result<Void, VoteSubmissionError>` | `networkUnavailable`, `unauthorized`, `unexpected`, `resolutionNotFound`, `notAParticipant`, `noVotingRights`, `resolutionClosed`, `votingWindowOver`, `alreadyVoted` |

Contract:

- A `VotingError` is a **business rejection**: the server understood the vote and refused it, so sending it again changes nothing. A gateway error is a failure of the exchange itself.
- **Idempotent on `vote.idempotencyKey`.** Sending a vote the server already holds under that key (a retry after the answer was lost) succeeds without recording it twice, and **never** answers `alreadyVoted` to the very vote it recorded. A different choice under the same key is a second vote and is rejected as `alreadyVoted`.
- **The voter must be the authenticated user.** If the voter of the vote is not the user the request is authenticated as, the adapter answers `unauthorized`, never a voting error: a vote is only ever recorded for the signed-in user, whoever queued it. The user a request is authenticated as is the identity attached to the request itself, read when it was created, never the one of a user who signed in while it was in flight.
- **The server must not trust `castAt`.** It comes from the clock of the device, which the user controls: the server stamps the vote with its own time and applies the voting window to that.
- How the application reads the outcomes:
  - `networkUnavailable` and `unexpected` say nothing about the vote (the server may or may not have recorded it): the vote is kept and sent again later, and the key makes the replay safe;
  - `unauthorized` stops everything until the user signs in again;
  - a voting error is final.
- The HTTP statuses behind each code (which statuses mean `networkUnavailable`, how a 422 maps to a voting error, the `Idempotency-Key` header) are in [../api.md](../api.md).

## What survives sign-out

Signing out (and the end of a session the server refused) locks the app, empties both caches for every owner, and forgets the session. The outbox is left alone. Signing in empties both caches again before the new session is used.

| Store                           | Port                                     | After a sign-out                               | Why                                                                                            |
| ------------------------------- | ---------------------------------------- | ---------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| Session and tokens              | `AuthSession`                            | Forgotten (`signOut`)                          | A restart must not restore a session the user left or the server refused                       |
| Cached meetings and pages       | `MeetingCache`                           | Purged for every owner                         | The next user of the device finds nothing of what this one saw                                 |
| Cached documents and content    | `DocumentCache`                          | Purged for every owner, content files included | A confidential file must not outlive the session                                               |
| Pending and rejected votes      | `VoteOutbox`                             | **Kept**                                       | A vote is scoped by its voter and is sent when they come back; unreadable entries are kept too |
| Lock state (in memory)          | none (state of the application)          | Locked                                         | The next sign-in opens it again                                                                |
| Screen protection switch        | `ScreenProtection`                       | Unchanged (driven by the open document views)  | It follows the views, not the session                                                          |
| Clock, connectivity, biometrics | `Clock`, `Connectivity`, `BiometricGate` | Not applicable (no per-user state)             | They report the device                                                                         |
| Logs                            | `Monitoring`                             | Not applicable                                 | Fire and forget, identifiers only                                                              |

A cache that cannot be emptied does not make the sign-out fail: the failure is captured, the entries are kept per owner so the next user cannot read them anyway, and the next sign-in empties the caches again.

## Enumerations

The values below are stable strings shared by the code and by any other implementation. Each table lists every value of the constant of the same name, no more and no fewer.

### `BIOMETRIC_REASON`

Why the user is asked for a biometric proof. The reason is a name, never a text.

| Value         | Meaning                                                                    |
| ------------- | -------------------------------------------------------------------------- |
| `unlockApp`   | The user unlocks the app (restored session, return after the grace period) |
| `confirmVote` | The user confirms a vote before it is cast                                 |

### `CONNECTIVITY_STATUS`

| Value     | Meaning                                                 |
| --------- | ------------------------------------------------------- |
| `online`  | The device has a connection, or the platform cannot say |
| `offline` | The device reports that it has no connection            |

### `SCREEN_CAPTURE_KIND`

What the system reports about the screen being captured.

| Value              | Meaning                                 |
| ------------------ | --------------------------------------- |
| `screenshotTaken`  | A screenshot was taken                  |
| `recordingStarted` | A screen recording or mirroring started |
| `recordingStopped` | A screen recording or mirroring stopped |

### `ENQUEUE_OUTCOME`

What `VoteOutbox.enqueue` did.

| Value              | Meaning                                                                                                                   |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------- |
| `enqueued`         | The vote was appended to the outbox                                                                                       |
| `alreadyQueued`    | A vote with the same idempotency key was already in the outbox: nothing changed; the existing vote is returned            |
| `heldByUnreadable` | An unreadable entry holds the key: nothing changed and the entry was not overwritten; it stays until the user discards it |

### `LOG_LEVEL`

| Value  | Meaning                                                                                   |
| ------ | ----------------------------------------------------------------------------------------- |
| `info` | Expected behaviour worth counting (a copy served from the cache, a vote recorded)         |
| `warn` | Something that deserves attention (a vote refused, a capture detected, a run interrupted) |

### `MONITORING_EVENT`

Every event the application reports. A call site names one of these, never a free text.

| Value                            | Meaning                                                                                                                                                                  |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `sessionExpired`                 | A stored session was found expired at the start and ended                                                                                                                |
| `signOutFailed`                  | The session could not be forgotten while it was being ended                                                                                                              |
| `cacheReadFailed`                | A local cache could not be read; the read is treated as a miss                                                                                                           |
| `cacheWriteFailed`               | A local cache could not be written; the fresh data is returned all the same                                                                                              |
| `cacheRemoveFailed`              | An entry could not be removed from a cache                                                                                                                               |
| `cachePurgeFailed`               | A cache could not be emptied                                                                                                                                             |
| `cacheEntryDiscarded`            | A cached entry was too old, or dated in the future, and counted as a miss                                                                                                |
| `servedFromCache`                | The server was unreachable and a saved copy was served as stale data                                                                                                     |
| `documentOpened`                 | A document was opened (the access log)                                                                                                                                   |
| `screenCaptureDetected`          | A screenshot or recording was reported while a document was shown                                                                                                        |
| `voteSubmitted`                  | The server recorded a vote                                                                                                                                               |
| `voteSubmitFailed`               | Sending a vote failed unexpectedly; it counts as an attempt                                                                                                              |
| `voteQueued`                     | A vote that could not be delivered was put in the outbox                                                                                                                 |
| `voteEnqueueFailed`              | A vote could not be put in the outbox                                                                                                                                    |
| `voteRejected`                   | A vote was refused for a business reason, or given up after too many attempts                                                                                            |
| `voteAttemptNotRecorded`         | An attempt could not be counted on a pending vote                                                                                                                        |
| `voteSyncCompleted`              | A synchronisation run went through the whole queue                                                                                                                       |
| `voteSyncInterrupted`            | A synchronisation run stopped early on a condition that concerns every vote                                                                                              |
| `outboxReadFailed`               | The outbox could not be read when counting the votes that remain                                                                                                         |
| `storedRowDiscarded`             | A row of the local database no longer reads back as what was stored: it is dropped                                                                                       |
| `documentContentNotStored`       | The content of a document was downloaded and could not be written to the files of the device; the document is not shown                                                  |
| `orphanFileNotDeleted`           | Files of the documents that no entry points at could not all be deleted at start, reported once                                                                          |
| `storedRowQuarantined`           | An entry of the outbox no longer reads back as a vote: it is kept, out of the queue, until the user discards it                                                          |
| `responseInvalid`                | The server answered something that does not have the shape of the API                                                                                                    |
| `databaseRecreated`              | The local database could not be opened with its key: the file was set aside unread and an empty one was created; votes that waited in the old one are not in the new one |
| `connectivityListenerFailed`     | A listener of the connectivity threw, which it must not; the others were told all the same                                                                               |
| `screenProtectionListenerFailed` | A listener of the screen capture events threw, which it must not; the others were told all the same                                                                      |
| `screenProtectionNativeFailed`   | The native side of the screen protection failed or did not answer; the failure is also returned                                                                          |
| `biometricMisconfigured`         | The build lacks what the platform needs to ask for the biometrics (a usage description on iOS)                                                                           |
| `unreadableVotesDiscarded`       | The user asked for the unreadable entries of the outbox to be deleted                                                                                                    |
| `monitoringNotStarted`           | The crash reporter was asked for and could not be started; the app goes on with the console                                                                              |
| `resetNoticeUnreadable`          | The record that local data was reset could not be read, so the user may not be told                                                                                      |
| `resetNoticeNotCleared`          | The user has been told local data was reset, and the record of it could not be cleared                                                                                   |

### `LOG_ATTRIBUTE`

The names an event can carry data under. Identifiers, codes and counts only.

| Value             | Meaning                                                                                             |
| ----------------- | --------------------------------------------------------------------------------------------------- |
| `userId`          | Identifier of the user concerned                                                                    |
| `meetingId`       | Identifier of the meeting concerned                                                                 |
| `resolutionId`    | Identifier of the resolution concerned                                                              |
| `documentId`      | Identifier of the document concerned                                                                |
| `period`          | The meeting period of a list (`upcoming` or `past`)                                                 |
| `resource`        | What was being cached or stored: a value of the cache resources (page of a list, meeting, document) |
| `freshness`       | Whether data came straight from the server (`fresh`) or from the cache (`stale`)                    |
| `confidentiality` | The confidentiality level of a document                                                             |
| `captureKind`     | A value of `SCREEN_CAPTURE_KIND`                                                                    |
| `errorCode`       | The stable code of an error                                                                         |
| `attempts`        | A number of attempts to deliver a vote                                                              |
| `synced`          | The number of votes the server recorded in a run                                                    |
| `rejected`        | The number of votes moved to the rejected state in a run                                            |
| `remaining`       | The number of pending votes left after a run                                                        |
| `discarded`       | The number of unreadable entries deleted at the user's request                                      |
| `issuePaths`      | The places a payload broke the schema (`agenda.0.status`), never what it held                       |
| `reason`          | Why something happened, as one of the const sets of the code that reports it                        |
