import 'dart:convert';
import 'dart:io';

import 'package:boardroom/app/dev/in_memory/fixtures/load_fixtures.dart';

// Test support, not production code: the fixtures of docs/spec/fixtures as they
// are on disk, for the tests that compare what the app reads with what the
// files say, and that break a copy of them on purpose. The tests run from the
// root of the project, so the folder is a relative path.

/// The folder of the fixtures.
const String fixturesFolder = 'docs/spec/fixtures';

/// The names of the JSON files that are in the folder, sorted.
List<String> fixtureFileNamesOnDisk() =>
    Directory(fixturesFolder)
        .listSync()
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .where((name) => name.endsWith('.json'))
        .toList()
      ..sort();

/// The text of a file of the folder.
String readFixtureText(String name) =>
    File('$fixturesFolder/$name').readAsStringSync();

/// A file of the folder, parsed. A new copy at each call, so that a test may
/// change it freely.
Object? readFixtureFile(String name) => jsonDecode(readFixtureText(name));

/// All the files, as text, as the app bundles them.
FixtureFiles readFixtureFiles() => FixtureFiles(
  accounts: readFixtureText(FixtureFile.accounts.value),
  meetings: readFixtureText(FixtureFile.meetings.value),
  recordedVotes: readFixtureText(FixtureFile.recordedVotes.value),
);

/// The three files parsed, to change in place: [encode] writes them back as the
/// text the loader reads. The members are the maps and lists of the JSON, so a
/// test reaches into them as the React Native tests reach into the parsed
/// files.
final class DecodedFixtures {
  /// Reads the files from disk.
  new()
    : accounts = readFixtureFile(FixtureFile.accounts.value),
      meetings = readFixtureFile(FixtureFile.meetings.value),
      recordedVotes = readFixtureFile(FixtureFile.recordedVotes.value);

  /// `accounts.json`.
  Object? accounts;

  /// `meetings.json`.
  Object? meetings;

  /// `recorded-votes.json`.
  Object? recordedVotes;

  /// The files as text.
  FixtureFiles encode() => FixtureFiles(
    accounts: jsonEncode(accounts),
    meetings: jsonEncode(meetings),
    recordedVotes: jsonEncode(recordedVotes),
  );
}

/// The `referenceDate` the files declare, in milliseconds since the epoch.
int referenceDateOnDisk() {
  final file = readFixtureFile(FixtureFile.meetings.value)! as Map;
  return DateTime.parse(file['referenceDate']! as String)
      .millisecondsSinceEpoch;
}
