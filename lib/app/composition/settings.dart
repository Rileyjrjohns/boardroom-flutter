import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/duration.dart';

// The configuration values that the use cases and the development world take,
// in one place, each with the reason for its value (the `config.ts` of the
// React Native app, and the "Settings" table of docs/spec/use-cases.md). The
// durations are checked when this library is first loaded: a value the domain
// refuses fails there, loudly, and the tests of the settings load it.

const int _millisPerSecond = 1000;
const int _millisPerHour = 3600000;
const int _millisPerDay = 24 * _millisPerHour;

/// What a duration helper says when it is given a value the domain refuses,
/// which only a typo in this library can do.
const String _invalidDuration = 'a setting is not a valid duration';

/// A duration of [millis] milliseconds. `valid` of the infrastructure is not
/// allowed in this pure layer, so the settings use this one.
DurationMillis _duration(int millis) => switch (durationFromMillis(millis)) {
  Ok(:final value) => value,
  Err() => throw StateError(_invalidDuration),
};

/// A week covers the usual cycle of a board, and older saved content has most
/// likely moved on.
final DurationMillis maxCacheAge = _duration(7 * _millisPerDay);

/// Rides out a bad moment of the server without letting one failing vote hold
/// the queue for ever.
const int maxVoteDeliveryAttempts = 5;

/// Long enough to answer a message and come back, short enough that a phone
/// left on a table locks.
final DurationMillis appLockGracePeriod = _duration(30 * _millisPerSecond);

/// How often an app that stays open and in the foreground checks its session
/// (`SESSION_CHECK_INTERVAL_MILLIS`). The check is local, so a short period
/// costs nothing. The timer itself is for the screens.
final DurationMillis sessionCheckInterval = _duration(30 * _millisPerSecond);

/// Ten rows fill a phone screen and arrive quickly; the next page loads when
/// the end is near.
const int meetingsPageSize = 10;

/// How long a request to the API may take, the answer included, before it
/// counts as a network failure. Long enough for a mobile network on a bad day,
/// short enough that the user is not left staring at a spinner: an offline
/// board member gets the saved copy within the quarter of a minute.
final DurationMillis httpRequestTimeout = _duration(15 * _millisPerSecond);

/// How long the download of a document may take, before it counts as a network
/// failure. A file takes longer than a page of JSON (a board pack is some
/// megabytes, on a mobile network), so it has a budget of its own: a minute is
/// enough for the largest file the app accepts on a slow connection, and an
/// offline board member whose document was seen before gets the saved copy
/// within the minute.
final DurationMillis documentDownloadTimeout = _duration(60 * _millisPerSecond);

/// The smallest request timeout that the configuration accepts.
final DurationMillis minHttpRequestTimeout = _duration(_millisPerSecond);

/// The largest request timeout that the configuration accepts.
final DurationMillis maxHttpRequestTimeout = _duration(60 * _millisPerSecond);

/// Whether the passcode of the device is accepted when the biometrics do not
/// recognise the user. No. The biometrics unlock the app and confirm a vote,
/// which is secret and final: a passcode is something a colleague or a relative
/// may have seen being typed, a fingerprint or a face is not. The price is a
/// user who is locked out of the biometrics (too many failed attempts, which
/// the system clears with its own passcode) waiting for them to come back, or
/// signing out and in again; a board that prefers the other trade-off turns
/// this on, and nothing else changes.
const bool allowDevicePasscodeFallback = false;

/// A working day, so that a session of the simulated server left open overnight
/// expires by itself (`MOCK_SESSION_LIFETIME` of the React Native app).
final DurationMillis devSessionLifetime = _duration(8 * _millisPerHour);

/// Long enough to see the loading states in the demo, short enough not to get
/// in the way.
final DurationMillis devSimulatedLatency = _duration(400);

/// The development configuration starts signed out, like the real one: the
/// user signs in with an account of the simulated server. A test that wants the
/// first account signed in at start asks for it through the raw settings.
const bool devStartsSignedIn = false;

/// The name of the local database file. It is part of what is stored on the
/// device: do not rename it.
const String databaseName = 'boardroom.db';
