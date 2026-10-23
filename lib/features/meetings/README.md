# meetings

The meetings of the board: the list by period, and the detail with its agenda, resolutions, participants and documents.

| Layer | What | May import |
| ----- | ---- | ---------- |
| `domain/` | `entities/` (`Meeting`, `MeetingSummary`, `AgendaItem`, `Resolution`, `Participant`, `Document`), `value_objects/` (`MeetingPeriod`, `VoteChoice`), `policies/voting_state.dart` | `core/domain`, `auth/domain`, its own files, pure Dart |
| `application/` | `ports/` (`MeetingRepository`, `MeetingCache`), `load_meeting.dart` (the meeting through the offline policy), `use_cases/` (`list_meetings`, `get_meeting`) | `domain`, `core`, `auth`, its own files, pure Dart |
| `infrastructure/` | `HttpMeetingRepository` and its wire class (`dto/meeting_dto.dart`), `DriftMeetingCache` and the stored form of a meeting (`stored_meeting.dart`), `InMemoryMeetingCache` | `domain`, `application`, `core`, the packages it adapts |
| `presentation/` | none yet | `domain`, `application`, `core`, never `infrastructure` |

- `domain` and `application` are pure Dart: they run under plain `dart test`, without Flutter.
- The in-memory repository of the development build is in `lib/app/dev/in_memory`: it reads the simulated server.
- Meant to depend on `core` and `auth`. For now `domain/entities/meeting.dart` still reads the `Vote` of `votes`, and the wire class and the stored form of a meeting read those of `documents`: later steps invert them.
- `DriftMeetingCache` is written against `BoardroomDatabase` of `lib/app/persistence`, for now.
