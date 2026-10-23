import 'package:boardroom/app/dev/in_memory/fixtures/bundled_fixtures.dart';
import 'package:boardroom/app/dev/in_memory/fixtures/load_fixtures.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:flutter/services.dart';

// The content of the simulated server. It is server data, not user interface
// text: it is written in English, whatever the language of the app, and the
// screens show it as it comes. It is not generated here: it is read from the
// fixtures of docs/spec/fixtures, which are shared with the other clients of
// the same domain (see docs/spec/fixtures/README.md).

export 'package:boardroom/app/dev/in_memory/fixtures/load_fixtures.dart'
    show SeedData;

/// Why the seed cannot be built: the fixtures are not acceptable.
typedef SeedError = FixtureError;

/// The password of the demo accounts. It protects nothing: the accounts exist
/// only in the simulation, and it is documented in docs/quick-start.md so that
/// anybody can sign in. It is the one of `accounts.json`, and the tests check
/// that the two agree.
const String demoPassword = 'boardroom-demo';

/// The seed of the simulated server: the fixtures of docs/spec/fixtures with
/// every date shifted by the complete days between their reference date and
/// [now], so that there are always upcoming and past meetings whenever the app
/// starts, in the proportions the files have (24 meetings ahead and 42 behind),
/// at the same time of day as in the files, nothing random, so that two runs at
/// the same instant give the same data.
///
/// Two demo accounts: Alice Martin, who is a voting member of most meetings,
/// chairs some, attends two as a guest and one as the secretary (no vote in
/// those); and Bruno Durand, who is in two meetings out of three, so that the
/// two users see different lists.
///
/// The state of the resolutions follows from the date of the meeting. In an
/// upcoming meeting they are open, with a closing time after the meeting starts
/// (or none), and most are still to be voted on; Alice voted on the minutes of
/// one of them. In a past meeting they were closed after the meeting started,
/// with the votes of the demo users on most of them (Alice voted for, against
/// and abstained in turn), except in some meetings where the status was never
/// closed although the voting window is over, so that every state a screen can
/// show is in the data.
///
/// The files are read from the assets of the app ([bundle], or the root
/// bundle).
/// Returns the reason when the fixtures are not acceptable, and never throws.
Future<Result<SeedData, SeedError>> buildSeed(
  Instant now, [
  AssetBundle? bundle,
]) async => loadFixtures(await readBundledFixtures(bundle), now);
