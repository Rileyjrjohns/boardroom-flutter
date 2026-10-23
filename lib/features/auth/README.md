# auth

Who the user is and whether the app is open to them: the account, the session, the app lock.

| Layer | What | May import |
| ----- | ---- | ---------- |
| `domain/` | `entities/` (`User`, `Session`), `value_objects/` (`EmailAddress`, `Credentials`), `policies/` (`app_lock`, `session_expiry`), `errors/` (`AuthenticationError` and `BiometricError`, each a sealed family in its own library) | `core/domain`, its own files, pure Dart |
| `application/` | `ports/` (`AuthSession`, `BiometricGate`, `SessionDataPurger`), `session/` (the session guards and the rules shared by the other features: `require_session`, `end_session`, `app_lock`, `confirm_with_biometrics`, `session_policy`, `purge_caches`, and `auth_session_gate`, the `SessionGate` of `core`), `use_cases/` (`sign_in`, `sign_out`, `restore_session`, `get_current_user`, `evaluate_app_lock`, `unlock_app`) | `domain`, `core`, its own files, pure Dart |
| `infrastructure/` | `HttpAuthSession` and its wire class (`dto/session_dto.dart`), `SessionVault` (the session kept in the secure storage), `biometrics/` (`DeviceBiometricGate` over a platform layer, `DeviceLocalAuthentication` over `local_auth`; the text of the prompt comes from outside) | `domain`, `application`, `core`, the packages it adapts |
| `presentation/` | the session state (`state/access.dart`: the access, its transitions and epoch; the sign-in, sign-out and unlock actions), the session life (`session/`: restore, check, watch, forgetting an ended session), `providers.dart` (the six use cases), `error_messages.dart`, `test_ids.dart`, the sign-in screen, the session notice and the restore failure; the lock screen and the sign-out dialog are to come | `domain`, `application`, `core`, the presentation of the features it depends on, never `infrastructure` |

- `domain` and `application` are pure Dart: they run under plain `dart test`, without Flutter.
- The in-memory session store and biometric gate of the development build are in `lib/app/dev/in_memory`: they need the simulated server.
- Depends on `core` only. What a session leaves on the device is purged through the `SessionDataPurger` port, which `meetings` and `documents` implement and `lib/app/composition` lists; the offline policy of `core` asks the session through the `SessionGate` port, which `auth` implements (`AuthSessionGate`). The `User` is read as it is by `documents` for the watermark. See [`docs/architecture.md`](../../../docs/architecture.md).
