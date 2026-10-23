# Porting the React Native code to Dart

The Flutter app has the same domain and the same application as the React Native one ([Boardroom](https://github.com/Rileyjrjohns/boardroom), the commit in [`parity/RN_COMMIT`](parity/RN_COMMIT)). The specification in [`spec/`](spec) is the contract; the TypeScript code under `src/core` and `src/features` conforms to it and is the reference implementation to translate. Every file of the `domain` and `application` folders of `lib/core` and `lib/features` is the translation of one TypeScript file, and every test is the translation of one React Native test, with the same name.

These rules are binding and mechanical. When the code you translate does something this document does not cover, do not invent: follow the TypeScript code, and write the point in [`parity/open-questions.md`](parity/open-questions.md). When the specification and the TypeScript code disagree, implement the specification and write it there too.

What changes is the language, never the behaviour: same entities, value objects, rules, errors and error codes, ports, use cases, and same test scenarios.

## 1. Files

The Flutter app is organised by feature. `lib/core` is the shared kernel, `lib/features/<feature>/{domain,application,infrastructure,presentation}` holds what belongs to one feature (`auth`, `meetings`, `documents`, `votes`), and `lib/app` is the composition (the screens that are not part of a feature, the database of the whole file, and the simulated world of the development build). The React Native app is organised by layer, so a file `src/<layer>/<area>/X.ts` finds its place in two steps:

1. **The layer is kept.** `src/domain` is a `domain` folder, `src/application` an `application` folder, `src/infrastructure` an `infrastructure` folder.
2. **The owner is `core` or a feature.** A file goes to `lib/core` when it carries no rule of a feature and several features use it: `Result`, the ids, `Instant`, `Page`, the errors, the `Clock`, `Monitoring` and `Connectivity` ports, `CacheEntry`, the offline policy (`loadWithCacheFallback`), the retryable codes of the core and the errors of the core (the repository, storage and validation errors). Every other file goes to the feature that owns the concept: `auth` (the user, the session, the credentials, the lock, the session guards, the authentication and biometric errors), `meetings` (the meetings, their agenda, resolutions and documents, `voteChoice`), `documents` (the location, the watermark, the screen protection and its errors), `votes` (the vote, the outbox, the eligibility, `withVoteRecorded`, the voting and delivery errors). A file of the React Native app that mixes the concerns of several features is split along them: `withVoteRecorded` is in `Meeting.ts` there and in `votes` here, and `recordVoteInCache` is the `MeetingCacheVoteRecorder` of `lib/app/composition`. The React Native app is still layered first; the deviations are in [`parity/open-questions.md`](parity/open-questions.md), and the architecture is in [`architecture.md`](architecture.md).

Inside the folder of the layer the path follows the TypeScript one: `src/domain/X/FooBar.ts` is `lib/<owner>/domain/x/foo_bar.dart`. The `shared` folder of the TypeScript application has no Dart counterpart of its own: its files go to where the rule above sends them (`lib/features/auth/application/session` for the session helpers, `lib/core/application/offline` for the offline policy, `lib/features/meetings/application/load_meeting.dart`, `lib/app/composition/meeting_cache_vote_recorder.dart` for `recordVoteInCache`, `lib/features/documents/application/screen_protection_coordinator.dart`), and `use-cases/<area>` becomes `use_cases` under the feature of the area (`use-cases/connectivity` is `lib/core/application/use_cases`). Folders and files are `snake_case`; a kebab-case folder becomes snake case.

| React Native                                  | Dart                                                                      | Note                                                                  |
| --------------------------------------------- | ------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| `src/domain/shared/Result.ts`                 | `lib/core/domain/shared/result.dart`                                      | The shared kernel                                                     |
| `src/domain/shared/Brand.ts`                  | (none)                                                                    | An extension type per value object replaces the brand (section 3)     |
| `src/domain/value-objects/ids.ts`             | `lib/core/domain/value_objects/ids.dart`                                  | `value-objects` is `value_objects`                                    |
| `src/domain/value-objects/EmailAddress.ts`    | `lib/features/auth/domain/value_objects/email_address.dart`               | A value of one feature                                                |
| `src/domain/errors/RepositoryError.ts`        | `lib/core/domain/errors/repository_error.dart`                            | A `part` of `app_error.dart` (section 5)                              |
| `src/domain/errors/AppError.ts`               | `lib/core/domain/errors/app_error.dart`                                   | The open root, and the library that holds the parts of the core       |
| `src/domain/errors/AuthenticationError.ts`    | `lib/features/auth/domain/errors/authentication_error.dart`               | A family sealed in its own library, in its feature (section 5)        |
| `src/domain/errors/VotingError.ts`            | `lib/features/votes/domain/errors/voting_error.dart`                      | A `part` of `vote_errors.dart`, with `vote_delivery_error.dart`       |
| `src/domain/entities/Meeting.ts` (`withVoteRecorded`) | `lib/features/votes/domain/with_vote_recorded.dart`               | Moved to `votes`, which depend on the meetings                        |
| `src/domain/policies/votingEligibility.ts`    | `lib/features/votes/domain/policies/voting_eligibility.dart`              | `camelCase` is `snake_case`                                           |
| `src/application/ports/AuthSession.ts`        | `lib/features/auth/application/ports/auth_session.dart`                   |                                                                       |
| `src/application/ports/Clock.ts`              | `lib/core/application/ports/clock.dart`                                   | A port of the kernel                                                  |
| `src/application/ports/types/CacheEntry.ts`   | `lib/core/application/ports/types/cache_entry.dart`                       |                                                                       |
| `src/application/shared/requireSession.ts`    | `lib/features/auth/application/session/require_session.dart`              | `shared` goes to the owner of the rule                                |
| `src/application/shared/loadWithCacheFallback.ts` | `lib/core/application/offline/load_with_cache_fallback.dart`          | The offline policy                                                    |
| `src/application/shared/recordVoteInCache.ts` | `lib/app/composition/meeting_cache_vote_recorder.dart`                    | The `RecordedVoteSink` of the votes, implemented by the composition   |
| `src/application/shared/retryableCodes.ts`    | `lib/core/application/retryable_codes.dart`, `lib/features/documents/application/retryable_codes.dart`, `lib/app/composition/retryable_codes.dart` | The core and the documents declare theirs, the composition assembles the set |
| `src/application/use-cases/auth/SignIn.ts`    | `lib/features/auth/application/use_cases/sign_in.dart`                    | `use-cases` is `use_cases`                                            |
| `src/application/use-cases/connectivity/ObserveConnectivity.ts` | `lib/core/application/use_cases/observe_connectivity.dart` | Connectivity is not a feature                                 |
| `X.test.ts` (next to `X.ts`)                  | `test/<same folders as the Dart file>/x_test.dart`                        | The test tree mirrors the `lib` tree                                  |
| `src/composition/glue/limits.test.ts`         | `test/core/domain/limits_test.dart`                                       | A test that spans the features stays in `test/core/domain`            |
| `src/composition/glue/domainLiterals.test.ts` | `test/core/domain/domain_literals_test.dart`                              | Same                                                                  |
| `src/domain/testing/builders.ts`              | `test/support/builders/builders.dart`                                     | `testing` is `test/support`                                           |
| `src/application/testing/FakeClock.ts`        | `test/support/fakes/fake_clock.dart`                                      |                                                                       |
| `src/application/testing/createFakes.ts`      | `test/support/fakes/create_fakes.dart`                                    |                                                                       |
| `src/application/testing/contracts/xContract.ts` | `test/support/contracts/x_contract.dart`                               | The contract suites                                                   |
| `src/application/testing/fakes.test.ts`       | `test/support/fakes/fakes_test.dart`                                      | A test of the support code stays with it                              |
| `src/application/testing/fakes.contracts.test.ts` | `test/support/fakes/fakes_contracts_test.dart`                        | `.` in a file name is `_`                                             |
| `src/composition/glue/applicationLiterals.test.ts` | `test/core/application/application_literals_test.dart`               | A test that spans the features stays in `test/core/application`       |
| `src/composition/glue/securityScenarios.test.ts` | `test/core/application/security_scenarios_test.dart`                   | Same                                                                  |
| `src/composition/glue/MeetingCacheVoteRecorder.test.ts` | `test/app/composition/meeting_cache_vote_recorder_test.dart`    | The glue between features is `test/app/composition`                   |
| `src/composition/glue/retryableCodes.test.ts` | `test/app/composition/retryable_codes_test.dart`                          | Same; the codes of the core and of the documents have a file each     |
| `src/features/auth/domain/errors/errors.test.ts` | `test/features/auth/domain/errors/auth_errors_test.dart`               | The name `errors.test.ts` is shared by the core and three features, so the Dart files of the features are named after the family (`dartFileNames`) |
| `src/features/votes/domain/withVoteRecorded.test.ts` | `test/features/votes/domain/with_vote_recorded_test.dart`          | `.` and the case are the only changes                                 |

The shared test support is in `test/support`, importable by any test: `builders/` (the builders, the matchers and the name helpers of the domain), `fakes/` (the fakes of the ports, `createFakes`, the fake clock and monitoring), `contracts/` (the contract suites that every adapter of a port runs), and `infrastructure/` (what the adapters need: the in-memory volumes, the test databases, the HTTP world, the fixture files). The first three are pure Dart; `infrastructure/` is not, and a pure test never imports it. The tests of the support code stay with it: `test/support/fakes/*_test.dart` run under `dart test`, `test/support/infrastructure/*_test.dart` under `flutter test`.

`snake_case` of a name: a capital letter after a lower-case letter or a digit starts a word (`fooBar` is `foo_bar`); a run of capitals followed by a lower-case letter splits before the last capital (`URLParser` is `url_parser`); `-` and `.` are `_`. `tool/scenario_parity.dart` applies exactly this rule (`snakeCase`) to find the Dart file of a React Native test: it is the single `<snake_name>_test.dart` among the pure test folders (`test/core/domain`, `test/core/application`, `test/features/*/domain`, `test/features/*/application`, `test/app/composition`, `test/support/fakes`). A React Native file whose scenarios are in several Dart files is declared in `splitScenarioFiles`: each part names its Dart file and the beginnings of the names of its scenarios. When two files share the name (`appLock.test.ts` exists in `src/domain/policies` and in `src/application/shared`), it takes the one whose path has a `domain` or an `application` folder, like the React Native layer.

Imports of `lib/` are `package:boardroom/...` URIs, never relative (the lint `always_use_package_imports`). A test file imports its support files (`test/support/...`) with relative URIs, because they are not under `lib/`. `tool/check_imports.dart` allows the tests of the `domain` and `application` folders of `test/core` and `test/features/*` (and the pure support, `test/support/{builders,contracts,fakes}`) the same imports as their layer, plus `package:test` and the pure support files, and never Flutter.

A generated file (`*.freezed.dart`) sits next to its source and is never committed. After any change to an annotated class, run `dart run build_runner build`.

## 2. Names and style

Dart conventions, applied mechanically.

| TypeScript                                          | Dart                                                          |
| --------------------------------------------------- | ------------------------------------------------------------- |
| `interface Foo`, `class Foo`, `type Foo = {...}`    | `UpperCamelCase`: `Foo`                                       |
| function, method, variable, property                | `lowerCamelCase`, same name: `parseEmailAddress`, `isOk`      |
| exported numeric constant `DEFAULT_PAGE_LIMIT`      | `lowerCamelCase`: `defaultPageLimit`                          |
| private constant `MAX_EMAIL_LENGTH` (not exported)  | private: `_maxEmailLength`                                    |
| `as const` object of strings (an enumeration)       | an `enum` (section 4)                                         |
| `private readonly x`, `private x`                   | `final _x` / `_x`                                             |
| `readonly x: T`                                     | `final T x`                                                   |
| `x?: T` (absent, never null)                        | `T? x`, null means absent (section 6)                         |
| `Promise<T>`                                        | `Future<T>`                                                   |
| `async` / `await`                                   | `async` / `await`                                             |
| `readonly T[]`                                      | `List<T>`; `List.unmodifiable(...)` where the TypeScript freezes or copies it |
| `ReadonlySet<T>`, `Set<T>`                          | `Set<T>`                                                      |
| `Record<K, V>`                                      | `Map<K, V>`                                                   |
| tuple `[A, B]`                                      | record `(A, B)`                                               |
| `string`, `boolean`                                 | `String`, `bool`                                              |
| `number`                                            | `int` for a count, a position, milliseconds; `num` at a validating factory (see below) |
| `void` result of `Result<void, E>`                  | `Result<void, E>`, built with `ok<void>(null)`                |
| `undefined`, `T \| undefined`                       | `null`, `T?`                                                  |
| `Unsubscribe` (`() => void`)                        | `typedef Unsubscribe = void Function();`                      |
| `interface` of a port                               | `abstract interface class`                                    |
| `JSON.stringify(x)` in a message                    | `'$x'`                                                        |

**Numbers.** The factories that validate a number received from outside (`parseInstant`, `durationFromMillis`, `createPageRequest`, `requireIntegerInRange`) take a `num`, because a decoded answer or a stored row can hold `1.5` or `NaN`, and the specification says those are `notAnInteger`. Once validated, the value is an `int`. Everything else that is a whole number in the TypeScript is an `int`.

**Strings.** A Dart `String.length` counts UTF-16 code units, like JavaScript, so every limit of the specification holds as is. Trim with `trimText` (`lib/core/domain/shared/validation.dart`), never with `String.trim`: Dart's `trim` removes U+0085, which `String.prototype.trim` keeps, and the specification's "trimmed" is the JavaScript one. `\s` in a `RegExp` is the same in both languages.

**Reserved words.** `for` is a reserved word of Dart: `VOTE_CHOICE.For` is `VoteChoice.forChoice`, whose stable string is still `'for'`. `Duration` is a type of `dart:core`, so the domain type `Duration` is `DurationMillis` (its factory is still `durationFromMillis`). No other name changes.

**Constructors.** The lint set (`very_good_analysis`) refuses the type name in a constructor, so a generative constructor is written `const new(this.x)` (`new(this.x)` in an `enum`, where `const` is implied and the lint `unnecessary_const_in_enum_constructor` refuses it), a named one `const new named(this.x)`, and a freezed factory `const factory ({...}) = _Foo;` (an unnamed factory has no name at all). Every public member of `lib/` has a `///` comment (`public_member_api_docs`): keep the TypeScript comment, translated to Dart wording (`undefined` is `null`, no `@param`), and add a short one where the TypeScript had none.

**Comments.** English, the same plain tone and density as the TypeScript. Translate the doc comments; adapt only the TypeScript-specific wording ("the branded type", "`Result` or a `Promise<Result>`" become "an extension type", "a `Result` or a `Future<Result>`"). Do not mention any tool or vendor.

**Literals.** No magic strings: a code or a literal is a named constant or an enum member. Stable strings are written once, in the enum.

## 3. Branded values and `Instant`

A TypeScript `Brand<string, 'UserId'>` is an **extension type** over the primitive that implements it, with a private representation field and a private constructor. Only the validating factory of the same file can build one, and a `UserId` is not a `MeetingId`, exactly like the brand:

```dart
extension type const UserId._(String _id) implements String;

Result<UserId, ValidationError> parseUserId(String raw) =>
    map(_parseIdentifier(ValidationField.userId, raw), UserId._);
```

At runtime it is the `String` itself (no allocation), so it compares, hashes and serialises as the string; `implements String` lets it be used where a `String` is expected, as a branded TypeScript value can.

- `Instant` is an extension type over the `int` of milliseconds since the epoch (`extension type const Instant._(int _epochMillis) implements int;`). `instant < other`, `instant + duration` and `jsonEncode` work on it. `isBefore`, `isAtOrAfter`, `plus` and `millisBetween` keep their names and meaning.
- `DurationMillis` is the same over a non-negative `int`.
- `EmailAddress`, `DocumentLocation`, `PageCursor` and the five ids are extension types over `String`.
- `Credentials`, `PageRequest`, `Page<T>`, `Watermark` and the entities are not extension types: they have several fields (section 6).

A `Brand` has no file of its own.

## 4. Enumerations and error codes

An `as const` object of strings and the union of its values (`VOTE_CHOICE`, `VoteChoice`) is **one Dart `enum`** whose members carry the stable string. Every such enum implements `StableValue` (`lib/core/domain/shared/constants.dart`) and calls its string `value`:

```dart
enum MeetingPeriod implements StableValue {
  upcoming('upcoming'),
  past('past');

  new(this.value);

  @override
  final String value;
}
```

| TypeScript                                          | Dart                                                          |
| --------------------------------------------------- | ------------------------------------------------------------- |
| `MEETING_PERIOD.Upcoming`                           | `MeetingPeriod.upcoming`                                      |
| `'upcoming'` (the stable string)                    | `MeetingPeriod.upcoming.value`                                |
| `Object.values(MEETING_PERIOD)`, `valuesOf(X)`      | `MeetingPeriod.values` (the members) or `valuesOf(MeetingPeriod.values)` (the strings) |
| `findConstant(valuesOf(X), raw)`                    | `findConstant(MeetingPeriod.values, raw)` (the member or `null`) |
| `type MeetingPeriod = ValueOf<typeof MEETING_PERIOD>` | the enum itself                                             |
| `parseMeetingPeriod(raw)`                           | `parseMeetingPeriod(String raw)`, same errors                 |

The key of the TypeScript object (`Upcoming`) becomes the member name in `lowerCamelCase`; the value is the string, spelled exactly as in the specification. A list or a set of codes (`SESSION_ENDING_CODES`, `RETRYABLE_CODES`) becomes a `final` list or set of `String`s built from the members (`RepositoryErrorCode.unauthorized.value`; an enum field is not a constant expression, so it cannot be `const`), and the predicates that take a code (`isRetryableCode(String code)`) keep taking a `String`.

The error code constants (`REPOSITORY_ERROR_CODE`...) are enums in the same way: `RepositoryErrorCode`, `AuthenticationErrorCode`, `VotingErrorCode`, `VoteDeliveryErrorCode`, `BiometricErrorCode`, `StorageErrorCode`, `ScreenProtectionErrorCode`, `ValidationErrorCode`. `REPOSITORY_ERROR_CODE.NetworkUnavailable` is `RepositoryErrorCode.networkUnavailable`, and the string `'networkUnavailable'` is its `value`. The same goes for `VALIDATION_FIELD` (`ValidationField`), `VALIDATION_RULE` (`ValidationRule`) and `ALREADY_VOTED_SOURCE` (`AlreadyVotedSource`).

## 5. `Result` and the errors

**Result.** `lib/core/domain/shared/result.dart`.

| TypeScript                                 | Dart                                                        |
| ------------------------------------------ | ----------------------------------------------------------- |
| `Result<T, E>`                             | `sealed class Result<T, E>`; subclasses `Ok<T, E>` and `Err<T, E>` |
| `ok(value)`, `err(error)`                  | `ok(value)`, `err(error)` (same names; they return `Ok<T, Never>` and `Err<Never, E>`, which fit any `Result<T, E>`) |
| `isOk(r)`, `isErr(r)`                      | `isOk(r)`, `isErr(r)`                                       |
| `map(r, f)`, `andThen(r, f)`               | `map(r, f)`, `andThen(r, f)`                                |
| `andThenAsync(r \| Promise<r>, f)`         | `andThenAsync(FutureOr<Result> r, f)`                       |
| `result.ok` then `result.value`            | `switch (result) { case Ok(:final value): ...; case Err(:final error): ... }`, or `if (result case Ok(:final value))` |
| `if (!result.ok) return result;`           | `if (result case Err(:final error)) return err(error);`    |
| `ok(undefined)`                            | `ok<void>(null)` or `ok<T?>(null)`                          |
| `expect(result).toEqual(ok(x))`            | `expect(result, equals(ok(x)))`                             |

`Ok` and `Err` compare by value (`DeepCollectionEquality`, so a list inside compares by content) and print as `Ok(1)` / `Err(boom)`. They have private constructors: build a result only with `ok` and `err`. When two steps of `andThen` fail with different errors, `E` is inferred as their closest common type (`AppError` for the errors of the domain).

Nothing in the `domain` or `application` folders of `lib/` throws or catches: a failure is a `Result`. (`async` functions still return `Future`s, and the tests may throw.)

**Errors.** `lib/core/domain/errors/` and `lib/features/<feature>/domain/errors/`. An error is plain data with a stable `code` and no text.

- `AppError` is an open `abstract base class` in the core, and every **family is sealed** in its own library, so a `switch` over a family is checked to be exhaustive (a `switch` over `AppError` itself is not: its subclasses are in several libraries). Dart only lets a sealed class be extended inside its own library, so the families that are related are `part`s of one library. The core has `app_error.dart` with the `part`s `repository_error.dart`, `storage_error.dart` and `validation_error.dart`; `auth` has `authentication_error.dart` and `biometric_error.dart`, `documents` `screen_protection_error.dart`, and `votes` `vote_errors.dart` with the `part`s `voting_error.dart` and `vote_delivery_error.dart` (a `VotingError` is a `RejectionReason`, which is sealed with the delivery errors). Import the library of the family you use.
- Each TypeScript error `interface` is a `final class ...Error extends <Family>` with a `const new(...)` constructor; `code` is a `String` getter that returns the stable string of its enum (`RepositoryErrorCode.notFound.value`). Fields are `final` with the same names (`field`, `rule`, `resolutionId`, `source`, `attempts`, `reason`, `cause`); an optional field (`cause?`) is a nullable field, left out of `payload` when `null`.
- `AppError.payload` is the map of the fields besides the `code`. Two errors are equal when they have the same class and the same payload, so `expect(unexpected('x'), equals(unexpected('x')))` works.
- The TypeScript factory functions keep their names and signatures: `networkUnavailable()`, `unexpected([String? cause])`, `storageReadFailed([String? cause])`, `voteUndeliverable(int attempts)`, `votePreviouslyRejected(RejectionReason reason)`, `validationError(field, rule)`. An error that has no factory in TypeScript and is written as an object literal there (`{ code: VOTING_ERROR_CODE.ResolutionClosed }`) is built with its constructor: `const ResolutionClosedError()`, `AlreadyVotedError(source: AlreadyVotedSource.recorded)`.
- The unions of the domain are sealed classes: `GatewayError` (network unavailable, unauthorized, unexpected) is a `RepositoryError`; `BiometricAvailabilityError` (unavailable, not enrolled) is a `BiometricError`; `VotingError` and `VoteUndeliverableError` are `RejectionReason`s. `isVotingError(error)` is kept as `error is VotingError`.
- **Unions defined by the application** (`GetMeetingError = SessionRequiredError | SessionChangedError | RepositoryError`, `VoteSubmissionError = GatewayError | VotingError`...) have no Dart equivalent. Write a `typedef` named like the TypeScript alias to the closest sealed type that contains every member, and list the members in its comment:

  ```dart
  /// What a meeting listing fails with: `sessionRequired` errors (not authenticated,
  /// session expired, app locked, storage read failed), `sessionChanged` and a
  /// [GatewayError].
  typedef ListMeetingsError = AppError;
  ```

  A union made of members of one family is that family (`Result<void, StorageError>`); a single member is its class (`Result<void, StorageWriteFailedError>`). A test asserts the exact error with `equals(err(...))`, as in TypeScript, so the precise set is still checked. This is the one place where Dart is less precise than TypeScript; it is written in the open questions.
- A TypeScript test that narrows with `Extract` or a type guard (`isVotingError(e)` then reads `e.resourceId`) uses `is` / a `switch` pattern.

## 6. Entities and value data

- A value with **several fields and equality** is a `freezed` class: `Credentials`, `PageRequest`, `Page<T>`, `Watermark`, and the entities of `lib/features/*/domain/entities`. `@freezed abstract class Foo with _$Foo { const factory ({required ...}) = _Foo; }`, `part 'foo.freezed.dart';`. It gives `==`, `hashCode`, `toString` and `copyWith`, and keeps lists unmodifiable.
- A freezed class that must not print something (`Credentials.password`) declares its own `toString` (the generator then leaves it alone) and needs `const new _();`.
- The TypeScript `createFoo(input)` factory that validates and returns a `Result` stays a top-level function with the same name (`createCredentials`, `createPageRequest`, `createUser`...). Its input `interface FooInput` becomes **named parameters** when it has at most three fields and a small `final class FooInput` with a `const new({required ...})` constructor otherwise (so that the tests read `createMeeting(MeetingInput(...))`). The entity's own constructor is public but documented as "use `createFoo`".
- The same rule applies to the input of a use case's `execute` (`execute({required email, required password})`, `execute(resolutionId:)`): at most three fields, named parameters. So the TypeScript input types of up to three fields (`SignInInput`, `GetMeetingInput`, `CastVoteInput`, `AcknowledgeRejectedVoteInput`, `UserInput`, `ParticipantInput`, `PageRequestInput`, `PendingVoteSnapshot`, `AppLockOptions`...) have no Dart type.
- **Optional properties** (`description?: string`, `exactOptionalPropertyTypes`): a nullable field. A TypeScript test that checks the key is absent (`expect(x).not.toHaveProperty('cursor')`) checks `isNull` in Dart. A blank optional text is `null`.
- **Lists**: the entity holds an unmodifiable copy (`List.unmodifiable`), as the TypeScript copies and sorts. `[...items]` is `List.of(items)`.
- **Plain `final class`** (no freezed) for: errors (hand written equality in `AppError`), ports and use cases, the fakes, and anything with behaviour and no value semantics.
- **Structural typing.** A TypeScript parameter typed by shape (`reader: { fullName; email }`, a `deps` object that carries more than the use case needs) becomes a small `abstract interface class` that the real types implement explicitly, or the real type itself when the feature may import it: `createWatermark(User reader, ...)` takes the `User` of `auth`, since `documents` depends on `auth`. The `deps` interfaces of the use cases (`SignInDeps`) are `abstract interface class`es with one getter per dependency; the `Fakes` class of the tests (and, later, the composition root) `implements` all of them, which is what lets `new SignIn(createFakes())` become `SignIn(createFakes())`.
- **Unions of entities** (`OutboxVote = PendingVote | RejectedVote`): a sealed freezed class whose variants are the factories (`const factory pending({...}) = PendingVote;`, written without the class name, as the lint asks). A field the TypeScript stores to tell the variants apart (`status`) is a getter derived from the class.
- **`extends` between entities** (`Meeting extends MeetingSummary`): the sub-entity repeats the fields and `implements` the base; the base is `@Freezed(copyWith: false)`.
- **Classes**: `export class SignIn { constructor(private readonly deps: SignInDeps) {} async execute(input) }` is `final class SignIn { const new(this._deps); final SignInDeps _deps; Future<Result<Session, SignInError>> execute({required String email, required String password}) async {...} }`. A port is an `abstract interface class` with the same methods, parameter names (the conformance rule compares them) and comments.

## 7. Tests

The test of a React Native file is the Dart test file of the mapping in section 1. Each React Native test becomes **one** Dart `test` whose **full name is identical** to the React Native one. `tool/scenario_parity.dart` checks it.

**Full names.** The full name of a test is the descriptions of its enclosing `describe` / `group` calls and its own, joined with one space: `describe('Result') > describe('map') > it('transforms the value of a success')` is `Result map transforms the value of a success`, in Jest and in `package:test` alike. Copy the descriptions character for character; a title longer than the line is written as adjacent string literals (`'a, ' 'b'`), which is the same string.

| Jest                                  | `package:test`                                               |
| ------------------------------------- | ------------------------------------------------------------ |
| `describe('X', () => {...})`          | `group('X', () {...})`                                       |
| `it('...', () => {...})`, `test(...)`  | `test('...', () {...})`                                      |
| `async () => {...}`                   | `() async {...}`                                             |
| `beforeEach`, `afterEach`, `beforeAll` | `setUp`, `tearDown`, `setUpAll`                              |
| `it.skip(...)`, `it.todo(...)`        | `test(..., skip: 'reason')` (a skipped test is still listed, so still counted) |
| `(cond ? describe : describe.skip)('x', fn)` | `group('x', fn, skip: !cond)`                        |
| `it.each(rows)('title %s', fn)`       | a `for` loop that makes one `test` per row (below)           |
| `describe.each(rows)('title %s', fn)` | a `for` loop that makes one `group` per row                  |
| `jest.useFakeTimers()`                | not used: time comes from `FakeClock`, the fake of the `Clock` port |
| `jest.fn()`, `toHaveBeenCalledTimes`  | a counter or a list the test fills                           |
| `new Promise((resolve) => ...)` gate  | `Completer<T>`                                               |

**`it.each` and `describe.each`.** Jest builds the name by replacing the placeholders of the title with the values of the row, in order. Dart builds the same name in a loop, with the helpers of `test/support/builders/names.dart`:

| Placeholder | Meaning                          | Dart                                                          |
| ----------- | -------------------------------- | ------------------------------------------------------------- |
| `%s`        | `String(value)`                  | plain interpolation: `'parses ${choice.value}'`               |
| `%j`        | `JSON.stringify(value)`          | `formatJson(value)`: `"\n\t"`, `undefined` for `null`, lone surrogates as `\ud800` |
| `%p`        | pretty-format on one line        | `formatPretty(value)`: `NaN`, `Infinity`, `"text"`, `{"code": "unexpected"}` for an error (keys in alphabetical order) |
| `%#`        | the index of the row             | the loop index                                                |
| `%%`        | a `%`                            | `%`                                                           |

```dart
// it.each(['', '   ', '\n\t'])('rejects the blank text %j', (raw) => {...})
for (final raw in ['', '   ', '\n\t']) {
  test('rejects the blank text ${formatJson(raw)}', () {...});
}

// describe.each(PARSERS)('the %s', (_name, parse, field) => {...})
for (final (name, parse, field) in parsers) {
  group('the $name', () {...});
}
```

A row of several values uses a record `(name, parse, field)`. A number is written with `formatNumber` / `formatPretty` so that `NaN` and `Infinity` print as in JavaScript and a whole number has no `.0`. Rows that are objects or errors are named the way pretty-format prints them (the helpers know `AppError`). Keep the rows in the same order, and keep every row, even when two rows print the same name.

**Assertions.**

| Jest                                           | Dart                                                         |
| ---------------------------------------------- | ------------------------------------------------------------ |
| `toEqual(x)`, `toStrictEqual(x)`               | `expect(actual, equals(x))` (entities, `Result`s and errors compare by value) |
| `toBe(true)`, `toBe(false)`                    | `isTrue`, `isFalse`                                          |
| `toBe(primitive)`                              | `equals(primitive)`                                          |
| `toBe(sameObject)`                             | `same(sameObject)`                                           |
| `toBeUndefined()`                              | `isNull`                                                     |
| `toBeDefined()`                                | `isNotNull`                                                  |
| `toHaveLength(n)`                              | `hasLength(n)`                                               |
| `toContain(x)`, `not.toContain(x)`             | `contains(x)`, `isNot(contains(x))`                          |
| `toContainEqual(x)`                            | `contains(x)` (it compares by value)                         |
| `toMatchObject({ a: 1 })`                      | `isA<T>().having((v) => v.a, 'a', 1)`                        |
| `expect.objectContaining(...)`                 | `isA<T>().having(...)`                                       |
| `not.toHaveProperty('k')`                      | `expect(object.k, isNull)`                                   |
| `expect(err).toEqual({ code, ...fields })`     | `expect(err, isAppError(code, {fields}))` (`test/support/builders/matchers.dart`) |
| `await expect(p).resolves.toEqual(x)`          | `await expectLater(p, completion(equals(x)))`                |
| `await expect(p).rejects.toThrow(...)`         | `await expectLater(p, throwsA(isA<...>()))`                  |
| `expect(fn).not.toThrow()`                     | `expect(fn, returnsNormally)`                                |
| `expect(result.ok && result.value).toEqual(x)` | `expect(result, isA<Ok<...>>().having((r) => r.value, 'value', x))` |

Assert the same things with the same values and the same error codes. A Dart test must not be weaker than the React Native one.

**Builders and fakes.** `src/domain/testing/builders.ts` is `test/support/builders/builders.dart`: `NOW` is `now`, `MILLIS_PER_DAY` is `millisPerDay`, `aUserId('user-2')` is `aUserId('user-2')` (an optional positional parameter), `unwrap` throws a `StateError` on a failed `Result`. A builder with `overrides: Partial<Input>` takes the fields as optional named parameters. The fakes keep their class names, their public fields and methods (`FakeClock.set`, `.advance`), and implement the same ports. `{ ...fakes, appLock: new AppLock() }` is `fakes.copyWith(appLock: AppLock())` (it replaces `appLock`, `maxCacheAge` or `maxAttempts`; the other fakes are shared); to replace a port by something that is not the fake, write a small class that implements the deps and forwards to the fakes. A contract suite (`describeXContract(name, createHarness, options)`) is a function that registers `group`s and `test`s, called from `fakes_contracts_test.dart` once per fake and, later, once per real adapter.

**A scenario that cannot exist in Dart.** A purely type-level test (`@ts-expect-error`, a check of what the compiler refuses) has no Dart test. List it in [`parity/exceptions.md`](parity/exceptions.md) with its React Native file, its full name and a one-line reason. The checker then does not expect it, and complains if the entry is not needed (the test exists in Dart) or stale (no such React Native test).

**A Dart-only test.** A test with no React Native scenario (Dart-specific behaviour, such as `trimText`) is allowed, in a file of its own or in a mapped file, but it must be listed in [`parity/extras.md`](parity/extras.md) with its Dart file, its full name and a reason (the entry `*` covers a whole Dart file that has no React Native counterpart).

**Run.**

```sh
dart run build_runner build
dart test test/core/domain test/core/application test/features/*/domain test/features/*/application test/support/fakes test/tool
dart run tool/scenario_parity.dart --rn ../boardroom --only src/core/domain/shared
dart run tool/scenario_parity.dart --rn ../boardroom --only src/features/votes/application/use-cases --table
```

`--rn` is a checkout of the React Native repository at the commit of [`parity/RN_COMMIT`](parity/RN_COMMIT). The checker reads its test sources (`*.test.ts` in the `domain` and `application` folders of `src/core` and `src/features/*`, in `src/composition/glue` and in `src/testing/application`), expands the `.each` tables the way Jest does (it follows the constants of the file and of the files it imports, and the contract suites a test file calls), asks `dart test --reporter json` for the names of the Dart tests, and compares the full names per file. It exits with 1 on any difference that no note explains.

## 8. Presentation

The screens, the shared components and the shell are specified in `docs/spec/screens.md` and built the way `docs/presentation.md` says. The mapping of the React Native pieces:

| React Native (`src/...`)                                          | Dart (`lib/...`)                                                                                                         |
| ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `core/presentation/theme/tokens.ts`                               | `core/presentation/theme/tokens.dart` (`AppColors`, `AppSpacing`...) and `app_theme.dart`                                |
| `core/presentation/components/*.tsx`                              | `core/presentation/components/*.dart` (`Button` is `AppButton`, `Badge` is `AppBadge`, `TextField` is `AppTextField`, `Dialog`/`DialogHost` are `AppDialog` and `ContentHost`) |
| `core/presentation/errors/ErrorCatalog.tsx`                       | `core/presentation/errors/error_catalog.dart`; assembled in `app/error_catalog.dart`                                      |
| `core/presentation/query/*` (query client, `retryPolicy`, `QueryFailure`, `useResultMutation`) | `core/presentation/query/` (`RetryPolicy`, `QueryFailure`, `keepQueryFor`, `runResultAction`)               |
| `core/presentation/state/uiStore.tsx`, `actionEpoch.tsx`         | `core/presentation/state/ui_state.dart`, `sessionEpochProvider`                                                           |
| `core/presentation/services/CoreServices.tsx`                     | `core/presentation/providers.dart`, `core/presentation/demo/`, `core/presentation/notices/`                               |
| `core/presentation/navigation/routes.ts`                          | `core/presentation/navigation/routes.dart`                                                                                |
| `core/presentation/testIds.ts`, `features/*/presentation/testIds.ts`, `composition/shell/testIds.ts` | `.../test_ids.dart` (the same strings, as `Key`s); registry in `app/test_ids.dart`        |
| `features/<f>/presentation/services/<F>Services.tsx`              | `features/<f>/presentation/providers.dart` (one provider per use case, throws until overridden)                           |
| `features/auth/presentation/state/accessStore.tsx`                | `features/auth/presentation/state/access.dart` (`AccessController`)                                                       |
| `features/auth/presentation/session/*`                            | `features/auth/presentation/session/*`                                                                                    |
| `composition/shell/session/*`, `services/StartupGate.tsx`         | `app/shell/*`                                                                                                             |
| `composition/shell/navigation/AppNavigator.tsx`, `systemLinks.ts` | `app/router/app_router.dart` (`redirectOf`, `maxLinkLength`)                                                              |
| `composition/shell/services/AppProviders.tsx`                     | `app/providers/app_overrides.dart`, `app/providers/slot_overrides.dart`                                                   |
| `composition/shell/errorCatalog.ts`                               | `app/error_catalog.dart`                                                                                                  |
| `core/presentation/i18n/resources/{en,fr}.ts`                     | `lib/l10n/app_{en,fr}.arb`                                                                                                |

**Text keys.** The key `signIn.title` of the specification is the ARB key `authSignInTitle`: the prefix of the owner (`core`, `auth`, `meetings`, `documents`, `votes`) followed by the React Native key in PascalCase, the prefix not doubled (`meetings.empty.upcoming` is `meetingsEmptyUpcoming`). The table of the namespaces is in `docs/presentation.md`, "Texts". `{{name}}` parameters are `{name}`; the plural keys (`_one`, `_many`, `_other`) are one ICU message with `{count, plural, ...}` and an `int` `count`. Dates are formatted with `Formatters`, not with the `{date}` of the message.

**Test ids** are the strings of the specification, set as `Key(id)`. **Names** follow section 2 (`TEST_IDS.signInEmail` is `AuthTestIds.signInEmail`; `meetingRowTestId` keeps its name).
