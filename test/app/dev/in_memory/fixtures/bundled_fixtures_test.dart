import 'package:boardroom/app/dev/in_memory/fixtures/bundled_fixtures.dart';
import 'package:boardroom/app/dev/in_memory/fixtures/load_fixtures.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/builders/builders.dart';
import '../../../../support/infrastructure/fixture_files.dart';

// The fixtures that ship with the app are the files of docs/spec/fixtures,
// declared as assets in pubspec.yaml. This test needs the asset bundle of
// Flutter, so it runs under `flutter test` only.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the fixtures of docs/spec/fixtures', () {
    for (final file in FixtureFile.values) {
      group(file.value, () {
        test('is what the app bundles, as it is on disk', () async {
          final bundled = await readBundledFixtures();

          final text = switch (file) {
            FixtureFile.accounts => bundled.accounts,
            FixtureFile.meetings => bundled.meetings,
            FixtureFile.recordedVotes => bundled.recordedVotes,
          };
          expect(text, equals(readFixtureText(file.value)));
        });
      });
    }

    test('are the ones the app reads: the seed is made of them', () async {
      final seed = loadFixtures(await readBundledFixtures(), now);

      expect(seed, isA<Ok<SeedData, FixtureError>>());
      expect(loadFixtures(readFixtureFiles(), now), equals(seed));
    });
  });
}
