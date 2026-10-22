# di

The composition root: the Riverpod providers that build the adapters and wire them to the ports and use cases. It is the one place that chooses an implementation.

- May import: `domain`, `application`, `infrastructure`, `riverpod` and its own files.
- Must not import: `presentation`, nor the packages behind the adapters (dio, drift, flutter_secure_storage, local_auth, screen_protection, sqlite3): those stay inside `infrastructure`.
