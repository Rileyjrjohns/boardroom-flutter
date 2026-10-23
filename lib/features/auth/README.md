# auth

Who the user is and whether the app is open to them: the account, the session, the app lock.

| Layer | What | May import |
| ----- | ---- | ---------- |
| `domain/` | `entities/` (`User`, `Session`), `value_objects/` (`EmailAddress`, `Credentials`), `policies/` (`app_lock`, `session_expiry`) | `core/domain`, its own files, pure Dart |
| `application/` | `ports/` (`AuthSession`, `BiometricGate`), `session/` (the session guards and the rules shared by the other features: `require_session`, `end_session`, `app_lock`, `confirm_with_biometrics`, `session_policy`, `purge_caches`), `use_cases/` (`sign_in`, `sign_out`, `restore_session`, `get_current_user`, `evaluate_app_lock`, `unlock_app`) | `domain`, `core`, its own files, pure Dart |
| `infrastructure/` | `HttpAuthSession` and its wire class (`dto/session_dto.dart`), `SessionVault` (the session kept in the secure storage), `biometrics/` (`DeviceBiometricGate` over a platform layer, `DeviceLocalAuthentication` over `local_auth`; the text of the prompt comes from outside) | `domain`, `application`, `core`, the packages it adapts |
| `presentation/` | none yet | `domain`, `application`, `core`, never `infrastructure` |

- `domain` and `application` are pure Dart: they run under plain `dart test`, without Flutter.
- The in-memory session store and biometric gate of the development build are in `lib/app/dev/in_memory`: they need the simulated server.
- Meant to depend on `core` only. For now `domain/entities/user.dart` still reads the `Watermark` of `documents` (the user is the reader of a watermark), and `application/session/purge_caches.dart` the caches of `meetings` and `documents`: later steps invert them.
