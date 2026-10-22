# infrastructure

The adapters: the classes that implement the ports of `application` with a real tool (dio, drift, flutter_secure_storage, local_auth, the screen protection plugin) or with an in-memory mock.

- May import: `domain`, `application` (to implement its ports), the packages it adapts, and its own files.
- Must not import: `presentation` or `di`.
