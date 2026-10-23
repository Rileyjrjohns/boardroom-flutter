# documents

The documents of a meeting: opening one (from the cache or from the server), closing it, and keeping the screen protected while it is shown.

| Layer | What | May import |
| ----- | ---- | ---------- |
| `domain/` | `value_objects/` (`DocumentLocation`, `Watermark`) | `core/domain`, `auth/domain`, `meetings/domain`, its own files, pure Dart |
| `application/` | `ports/` (`DocumentRepository`, `DocumentCache`, `ScreenProtection`), `screen_protection_coordinator.dart`, `use_cases/` (`open_document`, `close_document`, `observe_screen_capture`) | `domain`, `core`, `auth`, `meetings`, its own files, pure Dart |
| `infrastructure/` | `HttpDocumentRepository` and its wire class (`dto/document_dto.dart`), `DriftDocumentCache` and the stored form of a document (`stored_document.dart`), the content on disk (`document_content`, `store_document_content`), `pdf_signature` (the first bytes of a PDF), `InMemoryDocumentCache`, `InMemoryScreenProtection` | `domain`, `application`, `core`, the packages it adapts |
| `presentation/` | none yet | `domain`, `application`, `core`, never `infrastructure` |

- `domain` and `application` are pure Dart: they run under plain `dart test`, without Flutter.
- The `Document` entity is in `meetings/domain`, as the meeting holds its documents.
- The in-memory repository of the development build and the PDF writer of the demo documents are in `lib/app/dev`.
- `DriftDocumentCache` is written against `BoardroomDatabase` of `lib/app/persistence`, for now.
