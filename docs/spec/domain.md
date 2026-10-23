# Domain

The domain is the part of Boardroom that does not depend on a framework, a screen, a network or a database: the values, the entities, the business policies and the errors. A Flutter version of the app re-implements this file one to one, in `lib/domain` or wherever its architecture puts it. The use cases that orchestrate it are in [use-cases.md](use-cases.md), the interfaces it needs from the outside in [ports.md](ports.md).

The notation is the one of [README.md](README.md). Three rules apply to the whole domain:

1. **Nothing throws.** Every fallible operation returns a `Result<T, E>`. An error is plain data with a stable `code`, never a thrown value and never a user-facing text.
2. **A value is built once, validated, and is then trusted.** An identifier, an email or a title is made by a validating factory (the "built by" column below). Code that holds one does not check it again.
3. **Text is trimmed where the rule says so, and never otherwise.** A trimmed text keeps its inner whitespace. Identifiers, cursors and passwords are kept exactly as received or typed.

## Value objects

| Type               | Representation                  | Rules                                                                                                                                                                                 | Built by                                                                                     |
| ------------------ | ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| `Instant`          | A point in time, UTC            | A whole number of milliseconds since the Unix epoch, from 0 to 8640000000000000 (the range of a JavaScript `Date`). The domain never formats it and has no time zone                  | `parseInstant(epochMillis)`; `validation` on `instant`: `notAnInteger`, `outOfRange`         |
| `Duration`         | A length of time                | A whole, non-negative number of milliseconds, at most 3153600000000 (about a century)                                                                                                 | `durationFromMillis(millis)`; `validation` on `duration`                                     |
| `UserId`           | Text                            | An identifier (see below), field `userId`                                                                                                                                             | `parseUserId(raw)`                                                                           |
| `MeetingId`        | Text                            | An identifier, field `meetingId`                                                                                                                                                      | `parseMeetingId(raw)`                                                                        |
| `AgendaItemId`     | Text                            | An identifier, field `agendaItemId`                                                                                                                                                   | `parseAgendaItemId(raw)`                                                                     |
| `ResolutionId`     | Text                            | An identifier, field `resolutionId`. **Globally unique**: no two meetings have a resolution with the same id (the idempotency key of a vote does not hold the meeting id)             | `parseResolutionId(raw)`                                                                     |
| `DocumentId`       | Text                            | An identifier, field `documentId`                                                                                                                                                     | `parseDocumentId(raw)`                                                                       |
| `EmailAddress`     | Text                            | Trimmed and lower-cased. Not empty, at most 254 characters, matches one `@`, a dot in the domain part and no whitespace: `^[^\s@]+@[^\s@]+\.[^\s@]+$`. Deliverability is not checked  | `parseEmailAddress(raw)`; `validation` on `email`: `required`, `tooLong`, `invalidFormat`    |
| `Credentials`      | `{ email, password }`           | `email` is an `EmailAddress`. `password` is kept exactly as typed (no trimming), must not be empty, and is never logged, stored or put in an error                                    | `createCredentials(rawEmail, password)`; the email is checked first, then `password`         |
| `DocumentLocation` | Text                            | An opaque reference to where the content of a document can be read now (a file in app-private storage). Trimmed, 1 to 2048 characters. Produced by an adapter, consumed by the viewer | `parseDocumentLocation(raw)`; `validation` on `documentLocation`                             |
| `PageCursor`       | Text                            | Opaque: built by the remote source, handed back unchanged. Trimmed, 1 to 512 characters, well-formed UTF-16 (it is put in a URL)                                                      | `parsePageCursor(raw)`; `validation` on `pageCursor`: `required`, `tooLong`, `invalidFormat` |
| `PageRequest`      | `{ cursor?, limit }`            | Which page to read: after `cursor` (the first page when absent), at most `limit` items. `limit` is a whole number from 1 to 50 and defaults to 20                                     | `createPageRequest({ cursor?, limit? })`; `validation` on `pageLimit`                        |
| `Page<T>`          | `{ items, nextCursor? }`        | One page of a list. `nextCursor` is absent on the last page. The items are copied                                                                                                     | `createPage(items, nextCursor?)`                                                             |
| `MeetingPeriod`    | Enumeration                     | `upcoming` or `past`. Which one a meeting belongs to is decided by the remote source against its clock                                                                                | `parseMeetingPeriod(raw)`; `validation` on `meetingPeriod`: `unknownValue`                   |
| `VoteChoice`       | Enumeration                     | `for`, `against`, `abstain`                                                                                                                                                           | `parseVoteChoice(raw)`; `validation` on `voteChoice`: `unknownValue`                         |
| `Watermark`        | `{ fullName, email, viewedAt }` | What every document page shows to identify the reader. See [Watermark](#watermark)                                                                                                    | `createWatermark(reader, viewedAt)`; cannot fail                                             |
| `IdempotencyKey`   | Text                            | Identifies a vote for the remote source. See [Idempotency key](#idempotency-key)                                                                                                      | `idempotencyKeyOf(resolutionId, voterId)`; cannot fail                                       |

### Identifiers

All five identifiers follow one rule. They come from the remote source and are never interpreted, so they are **kept as received** (no trimming, case-sensitive). They must only be usable as a key and as a segment of a path:

1. not blank (`required`, when the text is empty or only whitespace);
2. at most 128 characters (`tooLong`, measured on the text as received);
3. well-formed UTF-16: every surrogate is half of a pair, a high one followed by a low one (`invalidFormat`: a lone surrogate cannot be encoded as UTF-8 or percent-encoded);
4. neither `.` nor `..` (`invalidFormat`: a URL would resolve them as directories).

The checks run in this order, and the first failure is the error. The error is `validation` with the `field` of the identifier (`userId`, `meetingId`, `agendaItemId`, `resolutionId`, `documentId`).

### Text rules

Four helpers are shared by the entities:

- **Required text**: trimmed; empty after trimming is `required`; longer than the maximum is `tooLong`.
- **Optional text**: absent or blank (after trimming) is "no text" and not an error; otherwise a required text.
- **Integer in range**: not a whole number is `notAnInteger`; outside the bounds (both included) is `outOfRange`.
- **Unique members**: a collection whose members share a key is `duplicate`.

## Limits

Every length is a number of UTF-16 code units of the trimmed text, unless the row says otherwise. The conformance test probes each limit with the code: the value just inside is accepted, the value just outside is refused.

| Limit              | Min | Max              | Applies to                                                                                           |
| ------------------ | --- | ---------------- | ---------------------------------------------------------------------------------------------------- |
| `identifier`       | 1   | 128              | Every identifier (length of the text as received)                                                    |
| `email`            | -   | 254              | `EmailAddress`, after trimming and lower-casing                                                      |
| `fullName`         | 1   | 200              | `User.fullName`, `Participant.fullName`                                                              |
| `title`            | 1   | 300              | `Document.title`, `MeetingSummary.title`, `Resolution.title`, `AgendaItem.title`                     |
| `description`      | 1   | 5000             | `Resolution.description` (required). `AgendaItem.description` has the same maximum and may be absent |
| `meetingLocation`  | 1   | 300              | `MeetingSummary.location`                                                                            |
| `pageCursor`       | 1   | 512              | `PageCursor`                                                                                         |
| `documentLocation` | 1   | 2048             | `DocumentLocation`                                                                                   |
| `pageCount`        | 1   | 10000            | `Document.pageCount`                                                                                 |
| `agendaPosition`   | 1   | 1000             | `AgendaItem.position`                                                                                |
| `pageLimit`        | 1   | 50               | `PageRequest.limit`                                                                                  |
| `attemptCount`     | 0   | 1000000          | `PendingVote.attempts` read back from storage                                                        |
| `duration`         | 0   | 3153600000000    | `Duration`, in milliseconds                                                                          |
| `instant`          | 0   | 8640000000000000 | `Instant`, in milliseconds since the Unix epoch                                                      |

## Entities

Fields marked `?` are optional: absent, never null. A "built by" function validates its input and returns a `Result`; the entity it returns is immutable.

### `User`

| Field      | Type           | Invariant                                                 |
| ---------- | -------------- | --------------------------------------------------------- |
| `id`       | `UserId`       |                                                           |
| `fullName` | `Text`         | Trimmed, 1 to 200 characters (`validation` on `fullName`) |
| `email`    | `EmailAddress` |                                                           |

Built by `createUser`.

### `Session`

| Field       | Type      | Invariant                                                                                                                                                                                     |
| ----------- | --------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `user`      | `User`    |                                                                                                                                                                                               |
| `expiresAt` | `Instant` | On the **device clock**, the same time base as the `Clock` port: the adapter computes it at sign-in as `clock.now()` plus the lifetime the server grants, and never copies a server timestamp |

A session holds no secret: the tokens belong to the `AuthSession` adapter. `createSession` cannot fail. The local value only decides when the app stops offering the session: a clock set back extends it locally, a clock set forward ends it early, and the server enforces its own expiry on every call.

### `MeetingSummary`

What a list of meetings shows.

| Field         | Type        | Invariant                                                                  |
| ------------- | ----------- | -------------------------------------------------------------------------- |
| `id`          | `MeetingId` |                                                                            |
| `title`       | `Text`      | Trimmed, 1 to 300 characters                                               |
| `scheduledAt` | `Instant`   |                                                                            |
| `location`    | `Text`      | Trimmed, 1 to 300 characters, free text (a room, an address, a video call) |

Built by `createMeetingSummary` (title is checked before location).

### `Meeting`

A `MeetingSummary` plus everything the detail screen shows.

| Field          | Type                | Invariant                                                                                      |
| -------------- | ------------------- | ---------------------------------------------------------------------------------------------- |
| (summary)      | `MeetingSummary`    | `id`, `title`, `scheduledAt`, `location`, flattened into the meeting                           |
| `agenda`       | `List<AgendaItem>`  | Sorted by `position` ascending. Distinct item ids, distinct positions, distinct resolution ids |
| `documents`    | `List<Document>`    | Distinct document ids                                                                          |
| `participants` | `List<Participant>` | Distinct user ids                                                                              |

Built by `createMeeting`. The checks run in this order and each reports `validation` with rule `duplicate`: agenda (field `agenda`: item ids, then positions, then resolution ids), documents (field `documents`), participants (field `participants`). The collections are copied and the agenda is sorted.

Helpers:

- `findResolution(meeting, resolutionId)`: the resolution with this id, wherever it sits in the agenda, or absent.
- `findParticipant(meeting, userId)`: the participant with this user id, or absent.
- `withVoteRecorded(meeting, vote)`: a copy of the meeting in which `vote.choice` is the `recordedVote` of the resolution `vote.resolutionId`. When `vote.meetingId` is another meeting, the same meeting is returned; when the meeting has no such resolution, an equal meeting is returned (a copy with no change). Either way nothing is recorded. It keeps a cached copy truthful once the server has accepted a vote.

### `AgendaItem`

| Field         | Type           | Invariant                                                               |
| ------------- | -------------- | ----------------------------------------------------------------------- |
| `id`          | `AgendaItemId` |                                                                         |
| `position`    | `Int`          | 1 to 1000, starting at 1 (`validation` on `position`)                   |
| `title`       | `Text`         | Trimmed, 1 to 300 characters                                            |
| `description` | `Text?`        | Trimmed, at most 5000 characters. A blank description is no description |
| `resolution`  | `Resolution?`  | The decision submitted to a vote at this point, if any                  |

Built by `createAgendaItem`: position, then title, then description.

### `Resolution`

A decision the board votes on.

| Field          | Type               | Invariant                                                                                                                             |
| -------------- | ------------------ | ------------------------------------------------------------------------------------------------------------------------------------- |
| `id`           | `ResolutionId`     | Globally unique                                                                                                                       |
| `title`        | `Text`             | Trimmed, 1 to 300 characters                                                                                                          |
| `description`  | `Text`             | Trimmed, 1 to 5000 characters, required                                                                                               |
| `status`       | `ResolutionStatus` | `open` or `closed`                                                                                                                    |
| `closesAt`     | `Instant?`         | The end of the voting window. A resolution without one stays open until its status says otherwise                                     |
| `recordedVote` | `VoteChoice?`      | The vote the **current user** has already cast, as the remote source records it. Absent: none yet. Nobody else's vote is ever present |

Built by `createResolution`: title, then description. `parseResolutionStatus(raw)` gives `validation` on `resolutionStatus` with `unknownValue`.

### `Document`

The metadata of a document attached to a meeting. Its content is read through a `DocumentLocation`.

| Field             | Type                   | Invariant                                |
| ----------------- | ---------------------- | ---------------------------------------- |
| `id`              | `DocumentId`           |                                          |
| `title`           | `Text`                 | Trimmed, 1 to 300 characters             |
| `confidentiality` | `ConfidentialityLevel` | `public`, `internal` or `confidential`   |
| `pageCount`       | `Int`                  | 1 to 10000 (`validation` on `pageCount`) |

Built by `createDocument`: title, then page count. `parseConfidentialityLevel(raw)` gives `validation` on `confidentialityLevel` with `unknownValue`. `isConfidential(document)` is true exactly when the level is `confidential`: such a document is opened with its screen protected (`OpenDocument` also protects a document served from the cache, whatever level the cache remembers). The watermark is not tied to the level: every document carries it, confidential or not (see [Watermark](#watermark)).

### `Participant`

A person invited to a meeting, in a role.

| Field      | Type              | Invariant                                                 |
| ---------- | ----------------- | --------------------------------------------------------- |
| `userId`   | `UserId`          |                                                           |
| `fullName` | `Text`            | Trimmed, 1 to 200 characters (`validation` on `fullName`) |
| `role`     | `ParticipantRole` | `chair`, `secretary`, `member` or `guest`                 |

Built by `createParticipant`. `parseParticipantRole(raw)` gives `validation` on `participantRole` with `unknownValue`. `hasVotingRights(participant)` is true for `chair` and `member`; a `secretary` takes the minutes and a `guest` attends: neither votes.

### `Vote`

A vote that has been cast. It is final: there is no way to change it.

| Field            | Type             | Invariant                                                         |
| ---------------- | ---------------- | ----------------------------------------------------------------- |
| `resolutionId`   | `ResolutionId`   |                                                                   |
| `meetingId`      | `MeetingId`      |                                                                   |
| `voterId`        | `UserId`         |                                                                   |
| `choice`         | `VoteChoice`     |                                                                   |
| `castAt`         | `Instant`        | The time on the device of the voter. The server does not trust it |
| `idempotencyKey` | `IdempotencyKey` | Always `idempotencyKeyOf(resolutionId, voterId)`                  |

Built by `createVote`, which **cannot fail**: every field is already a validated value. Whether the voter may vote is the business of [Voting eligibility](#voting-eligibility), which runs before.

### `OutboxVote`

A vote the app keeps locally because it has not been recorded by the server. It is one of two states, told apart by `status`:

`PendingVote` (`status = pending`): waiting to be sent.

| Field        | Type      | Invariant                                                                                        |
| ------------ | --------- | ------------------------------------------------------------------------------------------------ |
| `status`     | `pending` |                                                                                                  |
| `vote`       | `Vote`    |                                                                                                  |
| `enqueuedAt` | `Instant` | When the vote was put in the outbox                                                              |
| `attempts`   | `Int`     | 0 to 1000000. How many times sending failed **in a way that says nothing about the vote itself** |

`RejectedVote` (`status = rejected`): the server refused the vote for a business reason, or the app gave up. It will not be sent again and stays until the user acknowledges it.

| Field        | Type              | Invariant                                                              |
| ------------ | ----------------- | ---------------------------------------------------------------------- |
| `status`     | `rejected`        |                                                                        |
| `vote`       | `Vote`            |                                                                        |
| `enqueuedAt` | `Instant`         |                                                                        |
| `attempts`   | `Int`             | Kept from the pending state                                            |
| `reason`     | `RejectionReason` | A `VotingError` or a `voteUndeliverable` error (see [Errors](#errors)) |
| `rejectedAt` | `Instant`         | When the vote was moved to this state                                  |

The reason is part of the state: a rejected vote without a reason, or a pending one with a reason, cannot exist. Operations:

- `createPendingVote(vote, enqueuedAt)`: a pending vote with `attempts = 0`.
- `restorePendingVote(snapshot)`: rebuilds a pending vote read back from storage; `validation` on `attemptCount` (`notAnInteger`, `outOfRange`).
- `recordAttempt(pending)`: the same vote with `attempts + 1`.
- `rejectVote(pending, reason, rejectedAt)`: the rejected state. Only a pending vote can be rejected.
- `isPending(entry)`, `isRejected(entry)`: tell the two states apart.

### Idempotency key

`idempotencyKeyOf(resolutionId, voterId)` is the text `<length of the resolution id>.<resolution id>.<voter id>`, where the length is the decimal number of UTF-16 code units of the resolution id and `.` is the separator. Examples: `12.resolution-1.user-alice`. It is:

- **deterministic**: same inputs, same key;
- **total**: it only concatenates and cannot fail;
- **injective**: the length says where the resolution id ends, so two different (resolution, voter) pairs never give the same key, whatever characters the ids contain, separators included;
- built from the resolution and the voter and **not the meeting**, because a member votes once per resolution and resolution ids are globally unique.

The HTTP API percent-encodes the key in the `Idempotency-Key` header ([../api.md](../api.md)).

### Watermark

What every document shows on every page to identify who reads it. The domain guarantees the content and nothing visual:

| Field      | Type           | Content                                                                             |
| ---------- | -------------- | ----------------------------------------------------------------------------------- |
| `fullName` | `Text`         | The full name of the signed-in user (never blank: it comes from a validated `User`) |
| `email`    | `EmailAddress` | The email of the signed-in user (a well-formed address)                             |
| `viewedAt` | `Instant`      | The instant at which the document was opened, read from the `Clock`                 |

How `viewedAt` is formatted (language, time zone, date style) and the layout (text, tiling, angle, opacity) belong to the presentation; the values the React Native app uses are in [screens.md](screens.md). The watermark text is the three lines `fullName`, `email`, formatted `viewedAt`. Every document carries it, protected or not.

## Enumerations

Each table lists the exact values (stable strings) of a constant of the code. The conformance test compares each table with the constant it is named after.

### `VOTE_CHOICE`

| Value     | Meaning                 |
| --------- | ----------------------- |
| `for`     | The voter approves      |
| `against` | The voter rejects       |
| `abstain` | The voter takes no side |

### `MEETING_PERIOD`

| Value      | Meaning                                                                    |
| ---------- | -------------------------------------------------------------------------- |
| `upcoming` | Meetings that have not happened yet, soonest first (decided by the server) |
| `past`     | Meetings that already happened, latest first (decided by the server)       |

### `CONFIDENTIALITY_LEVEL`

| Value          | Meaning                                                            |
| -------------- | ------------------------------------------------------------------ |
| `public`       | No restriction                                                     |
| `internal`     | Internal to the board                                              |
| `confidential` | Shown with the screen protected and a watermark (`isConfidential`) |

### `PARTICIPANT_ROLE`

| Value       | Meaning                                     |
| ----------- | ------------------------------------------- |
| `chair`     | Presides the meeting; has the right to vote |
| `secretary` | Takes the minutes; no vote                  |
| `member`    | Board member; has the right to vote         |
| `guest`     | Attends; no vote                            |

### `RESOLUTION_STATUS`

| Value    | Meaning                                                              |
| -------- | -------------------------------------------------------------------- |
| `open`   | Voting may be open: see [Voting state](#voting-state) for the window |
| `closed` | Closed by the remote source; wins over the window                    |

### `OUTBOX_STATUS`

| Value      | Meaning                                                       |
| ---------- | ------------------------------------------------------------- |
| `pending`  | Waiting to be sent                                            |
| `rejected` | Refused by the server, or given up. It will not be sent again |

### `VOTING_STATE`

| Value        | Meaning                                                                      |
| ------------ | ---------------------------------------------------------------------------- |
| `open`       | The status is open and the voting window, if there is one, is not over       |
| `closed`     | The status says the resolution is closed                                     |
| `windowOver` | The status is still open, but the voting window is over (`closesAt` reached) |

### `ALREADY_VOTED_SOURCE`

| Value      | Meaning                                                              |
| ---------- | -------------------------------------------------------------------- |
| `recorded` | The remote source holds the earlier vote (it is part of the meeting) |
| `queued`   | The earlier vote waits in the outbox to be sent                      |

### `VALIDATION_FIELD`

The input a validation rule was applied to. The presentation maps a field to a form field or a label; the domain carries no text.

| Value                  | Meaning                                                   |
| ---------------------- | --------------------------------------------------------- |
| `userId`               | A user identifier                                         |
| `meetingId`            | A meeting identifier                                      |
| `agendaItemId`         | An agenda item identifier                                 |
| `resolutionId`         | A resolution identifier                                   |
| `documentId`           | A document identifier                                     |
| `fullName`             | The full name of a user or a participant                  |
| `email`                | An email address                                          |
| `password`             | A password                                                |
| `title`                | A title of a document, meeting, agenda item or resolution |
| `description`          | A description of an agenda item or a resolution           |
| `location`             | The location of a meeting                                 |
| `position`             | The position of an agenda item                            |
| `pageCount`            | The number of pages of a document                         |
| `pageLimit`            | The size of a page of a list                              |
| `pageCursor`           | The cursor of a page                                      |
| `instant`              | A point in time                                           |
| `duration`             | A length of time                                          |
| `documentLocation`     | The location of the content of a document                 |
| `attemptCount`         | The number of attempts to send a vote                     |
| `agenda`               | The agenda of a meeting taken as a collection             |
| `documents`            | The documents of a meeting taken as a collection          |
| `participants`         | The participants of a meeting taken as a collection       |
| `voteChoice`           | A vote choice                                             |
| `meetingPeriod`        | A meeting period                                          |
| `participantRole`      | A participant role                                        |
| `resolutionStatus`     | A resolution status                                       |
| `confidentialityLevel` | A confidentiality level                                   |

### `VALIDATION_RULE`

The rule that a value broke.

| Value           | Meaning                                                           |
| --------------- | ----------------------------------------------------------------- |
| `required`      | Empty, blank or missing                                           |
| `tooLong`       | Longer than the maximum                                           |
| `invalidFormat` | Does not have the expected shape                                  |
| `notAnInteger`  | Not a whole number                                                |
| `outOfRange`    | A whole number outside the bounds                                 |
| `unknownValue`  | Not a member of a closed set of values                            |
| `duplicate`     | Two members of a collection that must be unique share an identity |

## Policies

A policy is a pure function of its inputs. It reads no clock and no state: the instant is a parameter. Every policy below fails closed when the clock looks wrong.

### Voting eligibility

`checkVotingEligibility({ meeting, resolutionId, voterId, queuedVotes, now })` answers `Result<Void, VotingError>`: ok, or the **first** reason why not, checked in exactly this order. `queuedVotes` are the pending votes of the outbox for this resolution, whoever cast them.

| Order | Condition                                                                    | Error                                      |
| ----- | ---------------------------------------------------------------------------- | ------------------------------------------ |
| 1     | The meeting has no resolution with this id                                   | `resolutionNotFound` (with `resolutionId`) |
| 2     | The voter is not a participant of the meeting                                | `notAParticipant`                          |
| 3     | The voter's role carries no vote (`secretary`, `guest`)                      | `noVotingRights`                           |
| 4     | [Voting state](#voting-state) of the resolution at `now` is `closed`         | `resolutionClosed`                         |
| 5     | The voting state is `windowOver`                                             | `votingWindowOver`                         |
| 6     | The resolution has a `recordedVote`                                          | `alreadyVoted` with `source = recorded`    |
| 7     | A queued vote exists with the same `resolutionId` **and** the same `voterId` | `alreadyVoted` with `source = queued`      |

A cast vote is final: there is no second vote and no change of mind. The rule is evaluated on whatever copy of the meeting the caller holds, possibly a stale one: the server has the last word.

### Voting state

`getVotingState(resolution, now)` is the one definition of "can still be voted on". The eligibility policy and the screens both call it, so a resolution cannot be open on a screen and closed for the rules.

1. If `status = closed`, the state is `closed`, whatever `closesAt` says (a resolution closed by hand stays closed).
2. Otherwise, if `closesAt` is present and `now >= closesAt`, the state is `windowOver`. **The closing instant itself is already too late.**
3. Otherwise the state is `open`. A resolution without `closesAt` stays open until its status says otherwise.

### App lock

`isUnlockRequired({ backgroundedAt, now, gracePeriod, hasSession })` decides whether the user must unlock the app with the biometrics on returning from the background:

1. Without a session there is nothing to protect: **not required**.
2. If `now < backgroundedAt`, the clock was set back and the time away cannot be known: **required** (fails closed).
3. Otherwise required exactly when `now - backgroundedAt >= gracePeriod` (in milliseconds). A grace period of zero locks every time; an absence of exactly the grace period locks.

The default grace period is 30 seconds (see the settings in [use-cases.md](use-cases.md#settings)).

### Session expiry

`isSessionExpired(session, now)` is true when `now >= session.expiresAt`. A session is expired **at** its expiry instant and after it.

### Cache age

`isWithinMaxAge(cachedAt, now, maxAge)` answers whether a cached entry may still be shown as stale data. With `age = now - cachedAt`, it is true exactly when `age >= 0` and `age <= maxAge`: an entry of exactly `maxAge` is still good, one millisecond older is not, and an entry dated in the future (`age < 0`, the clock was set back since it was stored) is not trusted. The default `maxAge` is seven days (see the settings in [use-cases.md](use-cases.md#settings)).

### Pagination

`DEFAULT_PAGE_LIMIT = 20` and `MAX_PAGE_LIMIT = 50` (see `PageRequest`). The app asks for pages of 10 (the `MEETINGS_PAGE_SIZE` setting). The cursor is opaque and handed back unchanged.

## Errors

An error is a record with a stable `code` and, for some, a few more fields. The `code` of every member is **unique across all groups**, so errors from several concerns can be told apart by `code` alone. Codes are the contract: a client acts on the code, never on a text, and the codes are the same in every language and every port.

| Error                    | Extra fields                                     |
| ------------------------ | ------------------------------------------------ |
| `validation`             | `field: ValidationField`, `rule: ValidationRule` |
| `unexpected`             | `cause?: Text`                                   |
| `storageReadFailed`      | `cause?: Text`                                   |
| `storageWriteFailed`     | `cause?: Text`                                   |
| `resolutionNotFound`     | `resolutionId: ResolutionId`                     |
| `alreadyVoted`           | `source: AlreadyVotedSource`                     |
| `voteUndeliverable`      | `attempts: Int`                                  |
| `votePreviouslyRejected` | `reason: RejectionReason`                        |

Every other error has only its `code`. `RejectionReason` is `VotingError | voteUndeliverable`. A `cause` is a technical diagnostic for monitoring: a status code or a kind of failure, never a file path, a URL, the location or title of a document, a name, an email, an identifier taken from a query, nor the choice of a vote.

The groups, with the meaning of each code, follow. The conformance test compares each table with the constant it is named after.

### `VALIDATION_ERROR_CODE`

| Code         | Meaning                                                                                 |
| ------------ | --------------------------------------------------------------------------------------- |
| `validation` | A value broke an invariant: which input (`field`), which rule (`rule`). Carries no text |

### `AUTHENTICATION_ERROR_CODE`

| Code                 | Meaning                                                                                                                                                                                                                           |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `invalidCredentials` | The email and password pair was refused (an unknown email and a wrong password are not told apart)                                                                                                                                |
| `sessionExpired`     | A session exists but its expiry has passed                                                                                                                                                                                        |
| `notAuthenticated`   | An operation that needs a signed-in user ran without a session                                                                                                                                                                    |
| `sessionChanged`     | The user who started a long operation is no longer the signed-in user                                                                                                                                                             |
| `appLocked`          | A session exists and is valid, but the app is locked: nobody has proven they are there since the app started or came back past the grace period. Nothing is read, queued or sent for the user until the biometric unlock succeeds |

### `REPOSITORY_ERROR_CODE`

| Code                 | Meaning                                                                                                                                                                                                                                                        |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `networkUnavailable` | The remote source could not be reached (a request that times out included). **The only error the offline policy recovers from**                                                                                                                                |
| `notFound`           | The remote source answered that the requested item does not exist                                                                                                                                                                                              |
| `unauthorized`       | The session is no longer valid: expired, revoked, signed out elsewhere. It concerns everything the caller holds: the session is ended on the device. To be told apart from `forbidden`                                                                         |
| `forbidden`          | The session is valid but this user may not see this item. It concerns one item: it is dropped from the caches with what hangs off it. A server that prefers not to reveal that the item exists answers `notFound`, and the application treats the two the same |
| `unexpected`         | Anything else: a server fault, an answer that cannot be read. `cause` is a status code or a kind of failure                                                                                                                                                    |

Two aliases group them: **`GatewayError`** is `networkUnavailable | unauthorized | unexpected` (a call that addresses no particular item, a listing); **`RepositoryError`** is `GatewayError | notFound | forbidden` (a call that addresses one item).

### `VOTING_ERROR_CODE`

Why a vote cannot be cast. The same reasons come back from the remote source when it rejects a vote. A voting error is **final**: sending the vote again changes nothing.

| Code                 | Meaning                                                                       |
| -------------------- | ----------------------------------------------------------------------------- |
| `resolutionNotFound` | The meeting has no such resolution                                            |
| `notAParticipant`    | The voter is not invited to the meeting                                       |
| `noVotingRights`     | The voter takes part in the meeting without the right to vote                 |
| `resolutionClosed`   | The resolution is closed                                                      |
| `votingWindowOver`   | The resolution is still marked open, but its closing instant has been reached |
| `alreadyVoted`       | The voter has already voted on this resolution (`source` says where)          |

`isVotingError(error)` tells a business rejection from the other errors of a union by its code.

### `BIOMETRIC_ERROR_CODE`

| Code                   | Meaning                                                                              |
| ---------------------- | ------------------------------------------------------------------------------------ |
| `biometricUnavailable` | The device has no biometric hardware, or the app may not use it                      |
| `biometricNotEnrolled` | The device has biometric hardware but the user has registered no fingerprint or face |
| `biometricCancelled`   | The user dismissed the prompt                                                        |
| `biometricFailed`      | The prompt was shown and the user did not match                                      |
| `biometricLockedOut`   | Too many failed attempts: the system refuses new ones for a while                    |

`BiometricAvailabilityError` is `biometricUnavailable | biometricNotEnrolled` (what a check of the capability reports); `BiometricError` adds the other three (what an authentication reports).

### `STORAGE_ERROR_CODE`

| Code                 | Meaning                                                                                  |
| -------------------- | ---------------------------------------------------------------------------------------- |
| `storageReadFailed`  | The local store could not be read. A miss is not an error: a cache returns it as a value |
| `storageWriteFailed` | The local store could not be written                                                     |

### `SCREEN_PROTECTION_ERROR_CODE`

| Code                          | Meaning                                                               |
| ----------------------------- | --------------------------------------------------------------------- |
| `screenProtectionUnsupported` | The platform cannot block screenshots and screen recording            |
| `screenProtectionFailed`      | The platform could do it, but turning the protection on or off failed |

### `VOTE_DELIVERY_ERROR_CODE`

What can go wrong between a vote being cast and the server recording it.

| Code                     | Meaning                                                                                                                                                 |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `voteUndeliverable`      | Sending failed unexpectedly `attempts` times and the app gave up. A reason a queued vote is moved to the rejected state, so that the user sees it       |
| `votePreviouslyRejected` | A new vote on a resolution was refused because an earlier vote of the same voter on it is still in the outbox, rejected. The user acknowledges it first |
| `voteInProgress`         | A vote on the same resolution is being cast right now (on this instance of the use case)                                                                |
| `voteNotRejected`        | Only a rejected vote can be acknowledged; this one is still waiting to be sent                                                                          |
