# domain

The business rules of Boardroom: entities, value objects, policies and domain errors, plus the `Result<T, E>` type.

- Pure Dart. It runs under plain `dart test`, without Flutter.
- May import: its own files, `dart:core|async|collection|math|typed_data|convert` and the pure packages `meta`, `collection`, `freezed_annotation`, `json_annotation`. Nothing else (the allowlist lives in `tool/check_imports.dart`).
- Must not import: `dart:io`, `dart:ui`, `dart:isolate`, `dart:ffi`, `dart:html`, Flutter, any package of the infrastructure (dio, drift, secure storage, local_auth, ...), `application`, `infrastructure`, `presentation` or `di`.
