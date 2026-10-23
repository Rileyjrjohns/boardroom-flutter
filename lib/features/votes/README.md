# votes

Casting a vote on a resolution, keeping it in the outbox while the device is offline, and sending it when the connection is back.

| Layer | What | May import |
| ----- | ---- | ---------- |
| `domain/` | `entities/` (`Vote`, `OutboxVote`: pending or rejected), `policies/voting_eligibility.dart`, `with_vote_recorded.dart` (a meeting with the vote recorded on its resolution), `errors/` (`VotingError` and the delivery errors, sealed, in one library) | `core/domain`, `auth/domain`, `meetings/domain`, its own files, pure Dart |
| `application/` | `ports/` (`VoteRepository`, `VoteOutbox`, `RecordedVoteSink`), `use_cases/` (`cast_vote`, `sync_pending_votes`, `list_pending_votes`, `acknowledge_rejected_vote`, `discard_unreadable_votes`) | `domain`, `core`, `auth`, `meetings`, its own files, pure Dart |
| `infrastructure/` | `HttpVoteRepository` and its wire class (`dto/vote_dto.dart`), `rejection_schemas.dart` (how the rejection of a vote is written on the wire and in the outbox), `DriftVoteOutbox`, `persistence/` (the table `OutboxVotes` and the names of the file: `tables.dart`, `schema.dart`), `InMemoryVoteOutbox` | `domain`, `application`, `core`, the packages it adapts |
| `presentation/` | `providers.dart`, `test_ids.dart`, the placeholder of the vote synchronisation trigger (`state/vote_sync.dart`) and of the pending votes screen | `domain`, `application`, `core`, the presentation of the features it depends on, never `infrastructure` |

- `domain` and `application` are pure Dart: they run under plain `dart test`, without Flutter.
- The in-memory repository of the development build is in `lib/app/dev/in_memory`: it reads the simulated server.
- Writing a vote the server recorded into the cached meeting is the `RecordedVoteSink` port, which `CastVote` and `SyncPendingVotes` use and `lib/app/composition` implements (`MeetingCacheVoteRecorder`, over the cache of `meetings`).
- `DriftVoteOutbox` is written against a `GeneratedDatabase` and the table the feature owns; `lib/app/persistence` lists it in the database of the file.
