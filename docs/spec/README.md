# Boardroom specification

This folder is the reference for Boardroom that does not depend on a language or a framework. It is shared by the React Native app in this repository and by a Flutter version of the same domain: both must behave as it says. It describes what the app **is** (its values, rules, operations, contracts and screens), not how React Native or Flutter happen to build it.

## The rule

**The code follows the spec, exactly, and a test checks it.**

- A behaviour, a name, a code, a limit or a test id that is in the code must be in the spec, and the reverse.
- To change one, change the spec and the code in the same commit. A Flutter version is correct when it matches the spec; if the two disagree, the spec is the question to settle first.
- `tooling/spec.test.ts` (run by `npm test`, in the "tooling" project) reads these files and the code, and fails with the name of the item that is missing on one side. The checks are listed in [What the test checks](#what-the-test-checks). What it cannot check (the rules written in prose) is kept honest by the unit tests of the code and by review.

## The files

| File                         | What it specifies                                                                                                                                                                                           |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [domain.md](domain.md)       | Every entity and value object (fields, invariants, limits, how it is built), the business policies (voting eligibility, voting state, app lock, session expiry, cache age, watermark), and every error code |
| [use-cases.md](use-cases.md) | Every use case: input, output, error codes, the rules and side effects in order, the ports it uses. The session guard, the session policy, the offline policy, the settings and the constants, written once |
| [ports.md](ports.md)         | Every port: operations as language-neutral signatures, contracts (never throws, bounded time, idempotence, ordering, scoping, quarantine, what survives sign-out), and the adapters that exist              |
| [screens.md](screens.md)     | Every screen: route, parameters, what it shows, states, actions and navigation, stable test ids; the navigation map with its guards                                                                         |
| [fixtures/](fixtures/)       | The data of the demonstration: see [fixtures/README.md](fixtures/README.md)                                                                                                                                 |

The HTTP contract between the app and a server is [../api.md](../api.md). The decisions behind the architecture are in [../adr](../adr).

## How to read it

Read in this order when building the app again:

1. **This file**, for the notation and the conventions.
2. **domain.md**: the vocabulary. Everything else uses its types and its error codes.
3. **ports.md**: what the application needs from the outside world, and the contracts any adapter must keep.
4. **use-cases.md**: the behaviour. Each use case lists the ports it calls and the order of its steps.
5. **screens.md**: what the user sees and does, and the ids a UI test can rely on.

A Flutter implementation keeps the same layers: domain, application (ports and use cases), infrastructure (adapters), presentation. Dependencies only point inward: the domain imports nothing; the application imports the domain; the adapters implement the ports; the presentation calls the use cases and never an adapter. The composition root is the one place that builds the adapters and wires them (see the two configurations in [ports.md](ports.md#configurations)).

## Conventions

### Notation for types

Types are written in a neutral notation. Map them to the types of your language.

| Notation          | Meaning                                                                                                                                                                                                                                                                                                             |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Text`            | A string of UTF-16 code units. Lengths in this spec count code units (the code points of the BMP count 1, others 2)                                                                                                                                                                                                 |
| `Int`, `Bool`     | A whole number, a boolean                                                                                                                                                                                                                                                                                           |
| `Void`            | No value. A `Result<Void, E>` succeeds with nothing                                                                                                                                                                                                                                                                 |
| `Instant`         | A point in time, UTC, millisecond precision. On the wire (the HTTP API and the fixtures) an ISO 8601 string with a zone, such as `2030-03-17T17:46:40.000Z`; in memory any native date-time type. The React Native code holds it as a whole number of milliseconds since the Unix epoch, from 0 to 8640000000000000 |
| `Duration`        | A length of time, a whole non-negative number of milliseconds                                                                                                                                                                                                                                                       |
| `List<T>`         | An ordered collection. `Page<T>` is `{ items: List<T>, nextCursor?: PageCursor }`                                                                                                                                                                                                                                   |
| `T?`              | **Optional**: the value may be absent. A field marked `?` is absent, never null; an optional parameter is written `name?: Type`                                                                                                                                                                                     |
| `A \| B`          | One of several types                                                                                                                                                                                                                                                                                                |
| `{ a: A, b?: B }` | A record. Fields are immutable once built                                                                                                                                                                                                                                                                           |
| `Result<T, E>`    | Either a success holding a `T`, or an error holding an `E`. Never both. Every fallible operation returns one; **nothing throws**                                                                                                                                                                                    |
| `(A) -> B`        | A function from `A` to `B`. `Unsubscribe` is `() -> Void` and calling it twice does nothing                                                                                                                                                                                                                         |
| `Brand` types     | `UserId`, `MeetingId`, `EmailAddress`, ... are text (or numbers) that can only be made by their validating factory. Two branded types are never interchangeable even if both are text                                                                                                                               |

Names are written in the camel case of the code (`castAt`, `closesAt`). A Flutter implementation may follow the conventions of its language for identifiers, but the **stable strings** below must be identical.

### Stable strings

Every value that crosses a boundary is a stable string, spelled exactly as in the spec and never translated:

- **Error codes** (`networkUnavailable`, `alreadyVoted`, ...). An error is plain data with a `code` and, for some, a few more fields. Codes are unique across all groups, so errors of several concerns can be told apart by `code` alone. A client acts on the code, never on a text. The domain and the application carry **no user-facing text**: the presentation turns a code into a message of the language of the user.
- **Enumeration values** (`for`, `against`, `abstain`; `upcoming`, `past`; `pending`, `rejected`; ...), the **log event names** and **log attribute names** ([ports.md](ports.md#monitoring_event)), the **routes** and the **test ids** ([screens.md](screens.md)).

A new value is added to the spec and to the code together. A value is never renamed: that is a change of contract.

### Results and errors

- An operation that can fail returns `Result<T, E>`. The error side is a union of coded errors listed with the operation. An unexpected fault inside an adapter is turned into the error the contract names (`unexpected`, `storageReadFailed`, `storageWriteFailed`), never thrown.
- A **miss** (a cache that has nothing for a key) is a successful result with an absent value, not an error.
- A `cause` field on an error is a technical diagnostic for monitoring: a status code or a kind of failure. It never holds personal data, a credential, a token, a path, a URL, a document title or location, a name, an email or the choice of a vote.

### Time

The domain and the application read time only through the `Clock` port. Business code never reads the system clock, so every rule that depends on time is testable with a clock set by hand. The device clock is not trustworthy (the user can set it): the rules built on it fail closed (see the policies in [domain.md](domain.md#policies)).

### Language

All user-facing text is translated (English and French in the app) from the first screen; the specification refers to messages by their meaning or by the name of the translation key, never by their words. Literals in the code are named constants.

## Conformance conventions

The test reads these Markdown files with plain string handling, so the rule is small and the files stay readable.

- A **checked table** is a Markdown table whose **first header cell** is exactly one of the _kind labels_ below. The first cell of every row holds an **identifier in backticks**; the test reads the text between the first pair of backticks of that cell and nothing else. All other tables, and all prose, are free.
- The **subject** of a checked table is the first backticked token of the **nearest preceding heading**. A heading that introduces a table of the kinds `Value`, `Code` or `Operation` therefore starts with the name that table is about, in backticks, for example ``### `VOTING_ERROR_CODE` `` or ``### `MeetingCache` ``.
- A line that starts with `- **Ports**:` or `- **Errors**:` in a use case section is checked too: every backticked token on it must be a real port (resp. error code).
- The first line that opens a fenced block with the language `mermaid` is the navigation map.

| Kind label  | File         | Rows are                                        | Compared with                                                                                                                                                                                                                                                |
| ----------- | ------------ | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `Code`      | domain.md    | The values of an error code constant            | The values of the constant named by the subject (`VOTING_ERROR_CODE`, ...) exported by `src/domain/errors`                                                                                                                                                   |
| `Value`     | all          | The values of an enumeration                    | The values (an object, a list or a set) of the exported constant named by the subject: `src/domain` in domain.md, `src/application/ports` in ports.md, `src/application/shared` and `use-cases` in use-cases.md, the presentation enumerations in screens.md |
| `Limit`     | domain.md    | A numeric limit (`Min`, `Max` columns)          | The code, probed with the factories: the value inside is accepted, the value just outside is refused                                                                                                                                                         |
| `Use case`  | use-cases.md | The use cases                                   | The classes under `src/application/use-cases` that have an `execute` method                                                                                                                                                                                  |
| `Setting`   | use-cases.md | A configuration setting and its default         | The exports of `src/di/config.ts`                                                                                                                                                                                                                            |
| `Constant`  | use-cases.md | A fixed number of the application               | The numeric constants exported by `src/application/shared`, each exactly once                                                                                                                                                                                |
| `Port`      | ports.md     | The ports                                       | The exported interfaces of `src/application/ports` that declare at least one method                                                                                                                                                                          |
| `Operation` | ports.md     | The operations of the port named by the subject | The method names and the parameter names, in order, of that interface; the error codes in the `Errors` column must exist                                                                                                                                     |
| `Route`     | screens.md   | The routes                                      | The files under `app/` (without the layout and the native intent file) and the dynamic segments of their names                                                                                                                                               |
| `Test id`   | screens.md   | The fixed test ids                              | The values of `TEST_IDS` in `src/presentation/testIds.ts`, each exactly once, and the constant name in the second column                                                                                                                                     |
| `Builder`   | screens.md   | The test id builders                            | The exported builder functions of `testIds.ts`: names, parameters, and the resulting pattern                                                                                                                                                                 |

The tables of a file may be in any order and may be split in any number of groups, as long as the union is complete and has no duplicate.

## What the test checks

`tooling/spec.test.ts` asserts, in **both directions** (everything in the code is in the spec, everything in the spec is in the code), that:

1. the **error codes** of each constant of `src/domain/errors` match the `Code` table under its name in [domain.md](domain.md#errors), and all the other **enumerations** of the domain, the ports, the use cases and the presentation match their `Value` tables;
2. the **use cases** of `src/application/use-cases` match [use-cases.md](use-cases.md), and every port and error code they cite exists;
3. the **ports** of `src/application/ports`, and for each of them its **operations** and their parameter names, match [ports.md](ports.md);
4. the **routes** of `app/` and their parameters, the **test ids** and the **test id builders** of `src/presentation/testIds.ts` match [screens.md](screens.md), and the navigation map names every route;
5. the **limits** of [domain.md](domain.md#limits), the **settings** of [use-cases.md](use-cases.md#settings) and its **constants** have the values of the code;
6. the relative links of these files point to files that exist.

It does **not** check the prose: the order of the steps of a use case, the contract of a port, the states of a screen. Those are checked by the unit tests of the code and by the shared contract suites that every adapter of a port must pass (`src/application/testing/contracts`). A Flutter version should port those suites too.
