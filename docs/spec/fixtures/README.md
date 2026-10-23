# Fixtures

Frozen demo data of the Boardroom domain: a generic board, invented people, `.example` domains. They are the single source of the data of the React Native app (the `mock` configuration and the local mock API, `npm run mock:api`), and a Flutter client of the same domain reads the very same files. Nothing in them is specific to one client.

The files are JSON, UTF-8, pretty-printed with two spaces and a final newline. The keys of every object are in alphabetical order (the order of the keys means nothing) except `referenceDate`, which comes first; the order of a list is part of the data and is kept.

## The files

Where the HTTP API ([`docs/api.md`](../../api.md)) has an equivalent, the format is the one of the API, so that a client reads these files with the models it already has for its answers. The fields the API does not expose are in files of their own.

| File                  | Holds                                                         | Format                                                                                                                             |
| --------------------- | ------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `meetings.json`       | The 66 meetings, with agenda, documents and participants      | `{ referenceDate, meetings }`: each meeting is a `GET /meetings/{id}` answer, with no `recordedVote`                               |
| `recorded-votes.json` | The 62 votes already recorded, whoever cast them              | `{ referenceDate, recordedVotes }`: each vote is a `POST /votes` body (`resolutionId`, `meetingId`, `voterId`, `choice`, `castAt`) |
| `accounts.json`       | The two demo accounts that can sign in, and which one is demo | `{ referenceDate, accounts, demoUserId }`: each account is `{ user, password }`, the `user` being the one of a sign-in answer      |

`meetings.json` is every meeting, in the order of its id (`meeting-001` to `meeting-066`). The summary a list shows (`GET /meetings`: `id`, `title`, `scheduledAt`, `location`) is those four fields of a meeting. Whether a meeting is upcoming or past is not stored: it follows from `scheduledAt` and the clock, as in the API.

### What the API does not expose

- **The accounts and their password** (`accounts.json`). The API checks credentials and never lists accounts. The password of both demo accounts is `boardroom-demo`: it protects nothing, the accounts exist only in the simulation. `demoUserId` names the account that is signed in at start by the mock configuration (`user-alice`); the sign-in screen offers both.
- **The votes already recorded** (`recorded-votes.json`). The API gives a user their own vote on a resolution (`recordedVote` in `GET /meetings/{id}`) and nobody else's. Here every vote of every voter is listed, with `castAt` being the time the server stamped. A resolution of `meetings.json` therefore never carries a `recordedVote`: a client adds the one of the user who asks.
- **Who is invited to which meeting** is not in a file of its own, because the API already says it: the `participants` of a meeting (`userId`, `fullName`, `role`). A user takes part in the meetings that list them, sees only those, and may vote when their role is `chair` or `member` (not `secretary`, not `guest`).

## `referenceDate`

Every file starts with `referenceDate`, an ISO 8601 instant with a zone (`2026-10-01T08:00:00.000Z`): the moment the dates of the files are relative to. All the dates in the files (`scheduledAt`, `closesAt`, `castAt`) are absolute instants, written as the API writes them, and consistent with it: at the reference date, 24 meetings are ahead and 42 behind, every resolution of an upcoming meeting is open, every vote recorded was cast before it. No meeting and no closing time is within a day of the reference date, on either side (see [the margin](#the-margin-around-the-reference-date)); the meetings start on a round hour, at 09:00, 10:00, 14:00 or 16:00 UTC, and every closing time is a whole number of hours after its meeting starts.

The files carry the same `referenceDate`, even `accounts.json`, which holds no date, so that a file cannot be mixed with another of a different generation. A client refuses files that disagree.

## The shifting rule

A client that runs in demo mode **shifts every instant of the files by a whole number of days** when it loads them, so that the meetings stay upcoming whatever day the app is launched, and keep their time of day:

```
days   = floor((now - referenceDate) / 86 400 000 ms)
loaded = date in the file + days x 86 400 000 ms
```

- **The number of days is rounded down**, towards the earlier day, also when `now` is before the reference date: it is the largest whole number not greater than the quotient, not the quotient truncated towards zero. One millisecond before the reference date is `-1` day, not `0`. Beware of the integer division of a language that truncates (`~/` in Dart, `/` on integers in Swift and Kotlin): use a floor division, or `floor` on the quotient.

  | `now - referenceDate`      | days |
  | -------------------------- | ---- |
  | 0                          | 0    |
  | 1 day minus 1 millisecond  | 0    |
  | 1 day                      | 1    |
  | minus 1 millisecond        | -1   |
  | minus 1 day                | -1   |
  | minus 1 day, 1 millisecond | -2   |

- It applies to **every** instant: `scheduledAt` and `closesAt` of `meetings.json`, `castAt` of `recorded-votes.json`. A date left unshifted would no longer be consistent with the others. `referenceDate` itself is not shifted: it is what the shift is measured from.
- A day is exactly 86 400 000 milliseconds, and the arithmetic is on instants (milliseconds since the epoch), done once, with the `now` read once at load. Not calendar arithmetic: no month and no daylight saving time is involved, and a date written with an offset (`+01:00`) is the instant it stands for. The consequence is that a meeting keeps its **time of day in UTC** (09:00Z stays 09:00Z, on a round hour); shown in a time zone with daylight saving time, its local hour can differ by one hour from the one it had on the reference date, which is expected.
- The whole timeline moves rigidly. The distance between any two dates is unchanged, a vote closes the same time after its meeting starts, and a shift that would take an instant out of the range the domain accepts (before 1970) makes the data invalid.
- The shift is the elapsed time rounded down to whole days, so it is **never later and less than a day earlier** than `now - referenceDate`: `0 <= (now - referenceDate) - days x 1 day < 1 day`. The margin below is what makes this harmless.
- **Text is not shifted.** That is why no title or description names a month or a year (see [the titles](#what-the-data-contains)): such a name would freeze the reference date in the middle of a shifted timeline.
- **Any client must apply this same shift**, React Native today, Flutter tomorrow: a client that reads the dates as they are would show the demo as it was on the reference date, with no upcoming meeting once it has passed, and a client that shifted by the exact elapsed time would show meetings at 11:37. A client that does not run in demo mode (it talks to a server) reads no fixture.

### The margin around the reference date

Rounding down to whole days moves an instant by up to a day less than the elapsed time, so an instant close to the reference date could land on the other side of `now`. The files rule that out **by construction**:

- every `scheduledAt` and every `closesAt` is **at least one day** (86 400 000 ms) before or after `referenceDate`: `abs(instant - referenceDate) >= 1 day`, a distance of exactly one day being fine;
- no `castAt` is after `referenceDate`.

With `e = (now - referenceDate) - days x 1 day`, in `[0, 1 day)`, a loaded instant is `t + days x 1 day`, so it is at `(t - referenceDate) - e` from `now`. A meeting at least a day after the reference date is at `1 day - e > 0` from `now` at least: upcoming, whatever `now`. A meeting at least a day before it is at `-1 day - e < 0` at most: past. The same holds for the end of a voting window, so a resolution of an upcoming meeting is always open and one of a past meeting is always closed or past its window; a vote cast at or before the reference date is never in the future. Whatever the day and the time of day the app is launched, there are 24 upcoming and 42 past meetings and every resolution is in the same voting state.

A client **checks the margin** when it loads the files and refuses files that break it, with an error of its own kind (the React Native loader reports `timelineMargin`, naming the place: `meetings.0.scheduledAt`, `meetings.0.agenda.1.resolution.closesAt`, `recordedVotes.4.castAt`).

## What a client must check

The React Native loader (`src/composition/dev/in-memory/fixtures`) reads the files like an answer of the API, and a client should do the same: the fields exist and have the right type (unknown fields are ignored), every value passes the rules of the domain (a title is not blank, a status is `open` or `closed`, and so on), the files share their `referenceDate`, ids that must be unique are (meetings, documents, accounts, and one vote per resolution and voter), every id that points elsewhere points to something (`demoUserId` to an account, a recorded vote to a resolution of the meeting it names and to a participant of that meeting), and [the margin](#the-margin-around-the-reference-date) around the reference date is kept. A flaw is an error that the client reports, never a crash.

## What the data contains

Whatever `now` is, the shifted data keeps these properties, which the tests of the React Native app check at many instants (every hour of a day, the minutes around midnight UTC and around the time of day the shift changes, every quarter of an hour over three days, and across the years from 1990 to 2200):

- 24 upcoming and 42 past meetings, enough for several pages of each; every id and title is distinct;
- titles that carry no date: `<committee>: <subject>, session <n>`, `n` being the rank of the meeting among those of its committee, the oldest being session 1 and the number growing with the date (`Audit committee: Half-year financial statements, session 8`, `Board of directors: Annual budget, session 15`, `Nominations committee: Board succession planning, session 1`). Two meetings of a committee never share a number, so no two titles are alike, and a title never names a month or a year, which the shift would leave behind;
- two accounts, `alice.martin@boardroom.example` (the demo user, in every meeting: chair, member, secretary once, guest twice, `meeting-004` and `meeting-031`) and `bruno.durand@boardroom.example` (in two meetings out of three), both with the password above; six more people appear as participants only;
- 99 resolutions, 36 in upcoming meetings, all open (some without `closesAt`), and 63 in past meetings: closed with a `closesAt` after the meeting started, except in some meetings where the status was never closed and the voting window is simply over (no vote recorded there);
- the three voting states (open, closed, window over) and the three choices (`for`, `against`, `abstain`) are present; the demo user already voted on the minutes of `meeting-001`, which is upcoming, and can still vote on the main resolution of several other upcoming meetings (`meeting-002`, for one);
- 176 documents, at the three confidentiality levels, each listed by one meeting only.

## Changing them

Edit the files by hand: they are the source of truth. Keep the format above, keep [the margin](#the-margin-around-the-reference-date) (a meeting or a closing time put within a day of the reference date is refused when the app loads the files), and run `npm test`, which checks that every file has the shape its schema describes, that the app loads them, that the invariants above hold at the instants listed, and that the titles carry no date.

`tooling/generate-fixtures` is the script that made them, once, at the reference date, from the generator that used to be the seed of the app. Its offsets keep the margin by construction (the nearest meeting ahead is on the second day after the reference date, the nearest one behind on the second day before it), it reads what it wrote back through the loader of the app before saving anything, so that a generation that breaks a rule fails instead of being saved, and two runs give the same bytes. Running it again overwrites the files, hand edits included.

How the React Native app reads them: `src/composition/dev/in-memory/fixtures/loadFixtures.ts` validates the files with the schemas of the API (the `infrastructure/dto` folders of the features), checks the margin, builds the domain objects through the factories of the domain, shifts the instants by whole days, and returns a `Result` instead of throwing.
