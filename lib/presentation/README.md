# presentation

The widgets, the screens, the routing and the Riverpod notifiers. It drives the use cases and shows their results.

- May import: Flutter, `domain`, `application`, `di` (to read providers), the generated localizations (`lib/l10n`) and its own files.
- Must not import: `infrastructure`, nor the packages behind the adapters (connectivity_plus, dio, drift, flutter_secure_storage, local_auth, path_provider, screen_protection, sqlite3). An adapter reaches a screen only through a provider of `di`.
- Every user-facing text comes from the ARB files, never from a literal.
