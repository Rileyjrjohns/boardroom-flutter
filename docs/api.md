# Boardroom API

This is the contract between the HTTP adapters of the app (the client in `lib/core/infrastructure/http`, the adapters of each resource in `lib/features/<feature>/infrastructure`) and the server. It is the one of the React Native app: the Flutter app talks to the same API. The fixture server (`lib/app/dev/fixture_server`) implements it from the simulated server of the app, with the same rules and the same data as the mock configuration: the development build reaches it through a dio `HttpClientAdapter` that answers in process, and the tests of the adapters run against that implementation. A real server must answer the same way.

The constants below (routes, headers, statuses, query parameters) are the ones of `lib/core/infrastructure/http/protocol.dart`, which the client and the fixture server share. The shapes are the wire classes of `lib/core/infrastructure/http/dto/wire.dart` and of the `dto/` folder of each feature (`lib/features/<feature>/infrastructure/dto`, read with `json_serializable`), one file per resource.

## Conventions

- JSON, UTF-8, except the content of a document, which is a PDF. A request with a body sends `Content-Type: application/json`; every request sends `Accept: application/json` (`Accept: application/pdf` for the content of a document) and `Cache-Control: no-store`: the answers are confidential, and nothing between the server and the app (a proxy, the cache of the platform) may keep a copy. The server answers with `Cache-Control: no-store` too.
- **No redirects.** The API does not redirect, and the client does not follow a redirect (`followRedirects: false` and `maxRedirects: 0` in dio): a redirect would carry the token to another address. Any 3xx is an `unexpected` failure.
- **Size.** An answer is at most 2 MiB (`maxResponseBytes`). The client refuses one whose `Content-Length` declares more, without reading it, and stops reading a body that grows past it: the answer is an `unexpected` failure with the cause `response too large`. A request body is at most 64 KiB. The one exception is the content of a document (`GET /documents/{id}/content`), a file: at most 20 MiB (`maxDocumentBytes`), refused and abandoned the same way.
- **Instants** are ISO 8601 strings with a zone: `2030-03-17T17:46:40.000Z`, or with an offset (`2030-03-17T18:46:40+01:00`). They are never numbers.
- **Identifiers** (users, meetings, agenda items, resolutions, documents) are opaque, case-sensitive text of 1 to 128 characters, well-formed UTF-16 (no lone surrogate), and neither `.` nor `..`, which a path would read as a directory. A client puts one in a path percent-encoded and never interprets it; an identifier it cannot encode makes a request that is not sent. Resolution ids are unique across all meetings.
- **Unknown fields are ignored** by the client, so the server may add fields without breaking it. A field that is missing, or that has the wrong type, makes the answer invalid: the client treats it as an `unexpected` failure and reports the paths of the fields that did not match (never their values).
- A text field is trimmed and checked by the rules of the domain (a title is not blank and is at most 300 characters, and so on). An answer that breaks one of them is invalid like one with a wrong type.
- There is no version in the path. A change that is not backward compatible is a new version of this document and of the app.

## Authentication

`POST /auth/sign-in` returns a bearer token. Every other route needs `Authorization: Bearer <token>`. The token is read by the client when it creates the request, so the answer is the one for the user who held the token then.

There is no refresh and no endpoint to revoke a token: it expires after `expiresIn` seconds. **The first `401` on any route but the sign-in ends the session on the device**: the application layer that met it locks the app, empties the saved copies, and forgets the session and its token, so a restart does not restore a session the server refuses; the votes that wait to be sent stay for the next sign-in of their voter. A `401` is also what the client answers by itself, without sending, when the token it holds belongs to another user than the request is made for (a vote whose voter is not the user who is signed in); that case ends nothing, since the session now open was not refused. Signing out forgets the token on the device only.

The expiry the app uses is computed on the clock of the device from `expiresIn`; the server enforces its own on every call. The client believes a token only if it is made of visible ASCII characters (no space, no control character) and is at most 4096 characters long, since it goes into a header, and a lifetime only if it is at most 30 days (`2592000` seconds): a sign-in answer that breaks either is invalid.

## Errors

Every failure has a status, and a body of this shape (the codes are for people and logs, a client acts on the status):

```json
{ "error": { "code": "notFound" } }
```

| Status        | `code`                                | Meaning                                                                      | The client reports                                                        |
| ------------- | ------------------------------------- | ---------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| 400           | `badRequest`                          | The request is malformed: a parameter, a body, a header                      | `unexpected` (cause `status 400`)                                         |
| 401           | `unauthorized`                        | No token, an unknown or expired token, or a vote whose voter is not the user | `unauthorized`                                                            |
| 401 (sign-in) | `invalidCredentials`                  | The email and the password are refused                                       | `invalidCredentials`                                                      |
| 403           | `forbidden`                           | The token is valid, the user may not have this item                          | `forbidden`                                                               |
| 404           | `notFound`                            | There is no such route or item                                               | `notFound`                                                                |
| 413           | `badRequest`                          | The body is bigger than 64 KiB                                               | `unexpected` (cause `status 413`)                                         |
| 422           | the code of a voting error, see below | A business rule refused the vote                                             | a voting error                                                            |
| 408, 429      |                                       | The server gave up waiting for the request, or asks for fewer of them        | `networkUnavailable`: the offline policy and the retry of the votes apply |
| 502, 503, 504 | `serviceUnavailable` for 503          | The service behind the gateway cannot be reached                             | `networkUnavailable`: the offline policy and the retry of the votes apply |
| 3xx           |                                       | A redirect, which the API never sends                                        | `unexpected`, with the status as its only cause                           |
| anything else | `unexpected` for 500                  | The server failed                                                            | `unexpected`, with the status as its only cause                           |
| no answer     |                                       | The request failed, was cut off, or took more than the timeout (15 seconds)  | `networkUnavailable`                                                      |

A 5xx other than 502, 503 and 504 is `unexpected`, and a vote that meets it is retried later but counted as an attempt: after 5 it is given up. Gateway errors, 408 and 429 do not count, because they say nothing about the vote: an outage, or a server that asks for fewer requests, must not use up the attempts of a queue. A server that sends 429 may add a `Retry-After`; the client does not read it, it sends the votes again at the next synchronisation.

The `cause` of an `unexpected` error is the status or the kind of failure, never a URL, a path, a header or a part of a body.

## Routes

### `POST /auth/sign-in`

Request:

```json
{ "email": "alice.martin@boardroom.example", "password": "…" }
```

The email is compared as the app writes it: trimmed, in lower case. Response `200`:

```json
{
  "accessToken": "…",
  "tokenType": "Bearer",
  "expiresIn": 28800,
  "user": {
    "id": "user-alice",
    "fullName": "Alice Martin",
    "email": "alice.martin@boardroom.example"
  }
}
```

`expiresIn` is a number of seconds from now, from 0 to 2592000 (30 days). `401` with `invalidCredentials` when the credentials are refused (an unknown email and a wrong password are not told apart). `400` for a body that is not `{ email, password }`.

### `GET /meetings?period=upcoming|past&limit=N[&cursor=C]`

A page of the meetings the user takes part in. `period` is `upcoming` or `past`: which list a meeting is in is decided by the server against its clock. Upcoming meetings come soonest first, past ones latest first, ties broken by id.

- `limit`: a whole number from 1 to 50, written in decimal digits and nothing else (no sign, no space, no exponent, no leading zero: `1e1`, ` 10`, `0x10` and `05` are refused). Required.
- `cursor`: the `nextCursor` of the previous page. Absent for the first page. Opaque: the client hands it back as it received it. It stays valid when a meeting moves from one list to the other between two pages.

Response `200`:

```json
{
  "items": [
    {
      "id": "meeting-001",
      "title": "Audit committee: Half-year financial statements",
      "scheduledAt": "2026-10-15T09:00:00.000Z",
      "location": "Boardroom, 12th floor"
    }
  ],
  "nextCursor": "1792317600000:meeting-002"
}
```

`nextCursor` is absent on the last page. `400` for a missing or unknown `period`, a `limit` out of range or not written as above, and a cursor the server did not write. A cursor is well-formed UTF-16 text.

### `GET /meetings/{id}`

A meeting with its agenda (sorted by position), documents and participants. `404` for a meeting that does not exist, `403` for one the user is not invited to. The resolutions carry the vote of the user who asks, as the server recorded it, and nobody else's.

```json
{
  "id": "meeting-001",
  "title": "…",
  "scheduledAt": "2026-10-15T09:00:00.000Z",
  "location": "…",
  "agenda": [
    {
      "id": "agenda-1",
      "position": 1,
      "title": "Opening"
    },
    {
      "id": "agenda-2",
      "position": 2,
      "title": "Accounts",
      "description": "Optional text.",
      "resolution": {
        "id": "resolution-1",
        "title": "Approve the accounts",
        "description": "…",
        "status": "open",
        "closesAt": "2026-10-15T11:00:00.000Z",
        "recordedVote": "for"
      }
    }
  ],
  "documents": [
    {
      "id": "document-1",
      "title": "Financial statements",
      "confidentiality": "confidential",
      "pageCount": 3
    }
  ],
  "participants": [{ "userId": "user-alice", "fullName": "Alice Martin", "role": "member" }]
}
```

`description`, `resolution`, `closesAt` and `recordedVote` are absent when there is none. `status` is `open` or `closed`; `recordedVote` is `for`, `against` or `abstain`; `confidentiality` is `public`, `internal` or `confidential`; `role` is `chair`, `secretary`, `member` or `guest`. A resolution without `closesAt` stays open until its status says otherwise.

### `GET /documents/{id}`

The metadata of a document, as in the meeting: `{ "id", "title", "confidentiality", "pageCount" }`. `404` and `403` as for a meeting: a user may have a document when they take part in a meeting that lists it.

### `GET /documents/{id}/content`

The content of a document: the file itself, a PDF. Response `200`:

```http
HTTP/1.1 200 OK
Content-Type: application/pdf
ETag: "3"
Cache-Control: no-store

%PDF-1.4
…
```

The same authorisation as the metadata of the document: `401`, `403` and `404` as for `GET /documents/{id}`, with the body of an error (`application/json`), which the client does not read.

- **`Content-Type`** must be `application/pdf` (parameters and case are ignored). The client checks it before it reads a byte of the body, and refuses another type: an `unexpected` failure with the cause `unexpected media type`.
- **The signature.** The body starts with `%PDF-`. A server that says `application/pdf` and sends something else (an error page, a sign-in form) is not trusted: the client refuses it, stores nothing, and the failure is `unexpected` with the cause `invalid response`.
- **`ETag`** is the version of the content, and is required. It changes when the content or the classification of the document does, and it is the same while they do not. It is opaque, visible ASCII, 1 to 256 characters (`"3"`, `W/"abc"`). The client names the file it writes after the user the token belongs to, the document and this version, so that a download is never reused for somebody else nor across versions, and asking twice for the same version replaces the file in the same place. An answer without a usable `ETag` is `unexpected`, cause `invalid response`.
- **Size and time.** At most 20 MiB (`maxDocumentBytes`): the client refuses a body that declares more without reading it, and stops reading one that grows past it (`unexpected`, cause `response too large`). It has a timeout of its own, one minute (the document download timeout the composition root gives to `HttpDocumentRepository`), since a file takes longer than a page of JSON; past it the failure is `networkUnavailable`, and nothing is stored. The statuses that say the service cannot take the request now (408, 429, 502, 503, 504) are `networkUnavailable` here as everywhere.
- **No redirect, no cache**, as for every request: the token goes to this address only, and nothing between the server and the app keeps a copy.

The client writes the file to the private storage of the app whole or not at all (a temporary file moved into place when it is complete), and the location of that file is what the use cases carry: the API does not name a location, and the client never reads one from an answer.

### `POST /votes`

Records the vote of the user. A vote is final: one per resolution and voter.

```json
{
  "resolutionId": "resolution-1",
  "meetingId": "meeting-1",
  "voterId": "user-alice",
  "choice": "for",
  "castAt": "2026-10-14T08:30:00.000Z"
}
```

`castAt` is the time on the device of the voter. The server does not trust it: it stamps the vote with its own time and applies the voting window to that.

**Idempotency.** The request carries the header `Idempotency-Key`: the key of the vote, `<length of the resolution id>.<resolution id>.<voter id>`, percent-encoded because the ids are free text (`12.resolution-1.user-alice`). The server derives the same key from the body and answers `400` when they differ. Sending a vote again, because the answer was lost, is safe:

- the same vote (same key, same choice) answers `204` again and records nothing more, even if the resolution has closed in between;
- another choice under the same key is a second vote: `422` with `alreadyVoted`.

Responses:

- `204`, no body: the vote is recorded (or already was). The client does not read the body of a success of this route: any 2xx is a recorded vote, whatever it says.
- `401`: no valid token, or `voterId` is not the user the token belongs to. A vote is only ever recorded for the user it is authenticated as, whoever queued it.
- `422`: a business rule refused the vote, so sending it again changes nothing. The body is `{ "error": { "code": "…" } }` with one of:

| `code`               | Other fields                     | Meaning                                                       |
| -------------------- | -------------------------------- | ------------------------------------------------------------- |
| `resolutionNotFound` | `resolutionId`                   | The meeting has no such resolution                            |
| `notAParticipant`    |                                  | The voter is not invited to the meeting                       |
| `noVotingRights`     |                                  | The voter is a secretary or a guest                           |
| `resolutionClosed`   |                                  | The resolution is closed                                      |
| `votingWindowOver`   |                                  | The resolution is open, but its closing time has been reached |
| `alreadyVoted`       | `source`: `recorded` or `queued` | The voter already voted on this resolution                    |

- `400` for a body that is not a vote, an unknown `choice`, a missing or mismatched `Idempotency-Key`.
- `503` and the other gateway statuses mean the vote may or may not have been recorded: the client keeps it and sends it again.

## What the fixture server adds

It is the simulated server of the app behind these routes, so it also has what a simulation has: the seed (the frozen fixtures of `docs/spec/fixtures`, every date shifted by the time elapsed since their `referenceDate`: 24 upcoming and 42 past meetings and two accounts that share the password `boardroom-demo`), a configurable latency, and tokens it forgets when it stops. It listens on no port: the requests of the client reach it through the dio adapter (`FixtureServerAdapter`). It answers `503` while its simulated network is cut, which the tests use to take it offline.

The content of a document is generated: a valid PDF with one page of A4 for each page of the document, up to 100 (`demoPdfMaxPages`), each page showing the title of the document and `page i / n`, in the standard Helvetica font. The same title and page count always give the same bytes. Its `ETag` is the revision of what the server holds, so replacing the content (which the tests do) gives every document a new version.
