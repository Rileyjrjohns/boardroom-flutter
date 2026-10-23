# documents

The documents of a meeting: opening one (from the cache or from the server), closing it, and keeping the screen protected while it is shown.

| Layer | What | May import |
| ----- | ---- | ---------- |
| `domain/` | `value_objects/` (`DocumentLocation`, `Watermark`), `errors/` (`ScreenProtectionError`, a sealed family) | `core/domain`, `auth/domain`, `meetings/domain`, its own files, pure Dart |
| `application/` | `ports/` (`DocumentRepository`, `DocumentCache`, `ScreenProtection`), `screen_protection_coordinator.dart`, `document_cache_purger.dart` and `document_cache_evictor.dart` (its `SessionDataPurger` for `auth` and its `MeetingDocumentEvictor` for `meetings`), `retryable_codes.dart` (`documentsRetryableCodes`), `use_cases/` (`open_document`, `close_document`, `observe_screen_capture`) | `domain`, `core`, `auth`, `meetings`, its own files, pure Dart |
| `infrastructure/` | `HttpDocumentRepository` and its wire class (`dto/document_dto.dart`), `DriftDocumentCache` and the stored form of a document (`stored_document.dart`), `persistence/` (the table `DocumentEntries` and the names of the file: `tables.dart`, `schema.dart`), the content on disk (`document_content`, `store_document_content`), `pdf_signature` (the first bytes of a PDF), `InMemoryDocumentCache`, `InMemoryScreenProtection` | `domain`, `application`, `core`, the packages it adapts |
| `presentation/` | none yet | `domain`, `application`, `core`, never `infrastructure` |

- `domain` and `application` are pure Dart: they run under plain `dart test`, without Flutter.
- The `Document` entity is in `meetings/domain`, as the meeting holds its documents.
- The in-memory repository of the development build and the PDF writer of the demo documents are in `lib/app/dev`.
- The watermark reads the `User` of `auth`. A document the user opens is a `Document` of `meetings`; the documents implement the `MeetingDocumentEvictor` port of the meetings, and the `SessionDataPurger` port of `auth`.
- `DriftDocumentCache` is written against a `GeneratedDatabase` and the table the feature owns; `lib/app/persistence` lists it in the database of the file.
