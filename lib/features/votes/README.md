# votes

Casting a vote on a resolution, keeping it in the outbox while the device is offline, and sending it when the connection is back.

| Layer | What | May import |
| ----- | ---- | ---------- |
| `domain/` | `entities/` (`Vote`, `OutboxVote`: pending or rejected), `policies/voting_eligibility.dart` | `core/domain`, `auth/domain`, `meetings/domain`, its own files, pure Dart |
| `application/` | `ports/` (`VoteRepository`, `VoteOutbox`), `record_vote_in_cache.dart`, `use_cases/` (`cast_vote`, `sync_pending_votes`, `list_pending_votes`, `acknowledge_rejected_vote`, `discard_unreadable_votes`) | `domain`, `core`, `auth`, `meetings`, its own files, pure Dart |
| `infrastructure/` | `HttpVoteRepository` and its wire class (`dto/vote_dto.dart`), `DriftVoteOutbox`, `InMemoryVoteOutbox` | `domain`, `application`, `core`, the packages it adapts |
| `presentation/` | none yet | `domain`, `application`, `core`, never `infrastructure` |

- `domain` and `application` are pure Dart: they run under plain `dart test`, without Flutter.
- The in-memory repository of the development build is in `lib/app/dev/in_memory`: it reads the simulated server.
- `record_vote_in_cache.dart` writes in the cache of `meetings`, so it is meant to move to `lib/app` in a later step.
- `DriftVoteOutbox` is written against `BoardroomDatabase` of `lib/app/persistence`, for now.
