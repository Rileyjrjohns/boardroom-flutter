import 'package:boardroom/infrastructure/in_memory/fixtures/load_fixtures.dart';
import 'package:flutter/services.dart';

// The fixtures that ship with the app: the files of docs/spec/fixtures, which
// are declared as assets in pubspec.yaml and bundled as they are. This is the
// one module that reads them, and it hands them over as they come, unchecked:
// `loadFixtures` validates them.

/// Where the bundled copy of each file is, in the asset bundle.
const String fixtureAssetFolder = 'docs/spec/fixtures';

/// Reads the fixtures that ship with the app from the asset bundle (the one of
/// the app by default).
Future<FixtureFiles> readBundledFixtures([AssetBundle? bundle]) async {
  final source = bundle ?? rootBundle;
  Future<String> read(FixtureFile file) =>
      source.loadString('$fixtureAssetFolder/${file.value}');
  return FixtureFiles(
    accounts: await read(FixtureFile.accounts),
    meetings: await read(FixtureFile.meetings),
    recordedVotes: await read(FixtureFile.recordedVotes),
  );
}
