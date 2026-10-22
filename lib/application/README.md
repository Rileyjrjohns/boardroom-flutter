# application

The use cases and the ports (interfaces) they depend on. A use case orchestrates the domain and talks to the outside world only through a port.

- Pure Dart. It runs under plain `dart test`, without Flutter.
- May import: `domain`, its own files, and the same pure `dart:` libraries and packages as the domain (see `tool/check_imports.dart`).
- Must not import: Flutter, `infrastructure`, `presentation`, `di`, or any infrastructure package.
