# meetings

The meetings of the board: the list by period, and the detail with its agenda, resolutions, participants and documents.

| Layer | What | May import |
| ----- | ---- | ---------- |
| `domain/` | `entities/` (`Meeting`, `MeetingSummary`, `AgendaItem`, `Resolution`, `Participant`, `Document`), `value_objects/` (`MeetingPeriod`, `VoteChoice`), `policies/voting_state.dart` | `core/domain`, `auth/domain`, its own files, pure Dart |
| `application/` | `ports/` (`MeetingRepository`, `MeetingCache`, `MeetingDocumentEvictor`), `load_meeting.dart` (the meeting through the offline policy), `meeting_cache_purger.dart` (its `SessionDataPurger` for `auth`), `use_cases/` (`list_meetings`, `get_meeting`) | `domain`, `core`, `auth`, its own files, pure Dart |
| `infrastructure/` | `HttpMeetingRepository` and its wire classes (`dto/meeting_dto.dart`, the documents it lists included), `DriftMeetingCache` and the stored form of a meeting (`stored_meeting.dart`), `persistence/` (the tables `MeetingPages` and `MeetingDetails` and the names of the file: `tables.dart`, `schema.dart`), `InMemoryMeetingCache` | `domain`, `application`, `core`, the packages it adapts |
| `presentation/` | `providers.dart` (the use cases, the page size) and `test_ids.dart`; the screens are placeholders until the meetings agent writes them | `domain`, `application`, `core`, the presentation of the features it depends on, never `infrastructure` |

- `domain` and `application` are pure Dart: they run under plain `dart test`, without Flutter.
- The in-memory repository of the development build is in `lib/app/dev/in_memory`: it reads the simulated server.
- Depends on `core` and `auth`. A meeting knows nothing of votes: a resolution records a `VoteChoice`, and `withVoteRecorded` is in `votes`. The documents it lists have their own wire class and stored form here, since an adapter does not import the adapter of another feature. The documents a refused meeting takes with it are dropped through the `MeetingDocumentEvictor` port, which `documents` implements.
- `DriftMeetingCache` is written against a `GeneratedDatabase` and the tables the feature owns; `lib/app/persistence` lists them in the database of the file.
