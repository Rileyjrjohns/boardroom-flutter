import 'package:boardroom/core/infrastructure/persistence/database_key.dart';
import 'package:test/test.dart';

import '../../../support/builders/names.dart';

final String _key = '0123456789abcdef' * 4;

void main() {
  group('the state of the key', () {
    test('is written as the generation and the key, and read back', () {
      final written = formatKeyState(KeyState(generation: 3, key: _key));

      expect(written, equals('3:$_key'));
      expect(
        parseKeyState(written),
        equals(KeyState(generation: 3, key: _key)),
      );
    });

    test('reads a bare key as the key of the first file: '
        'that is what an app with one file kept', () {
      expect(
        parseKeyState(_key),
        equals(KeyState(generation: firstGeneration, key: _key)),
      );
    });

    final notStates = <String>[
      '',
      ' ',
      'key',
      '$_key ',
      ' $_key',
      '1:${_key.substring(1)}',
      '1:${_key.toUpperCase()}',
      ':$_key',
      'x:$_key',
      '-1:$_key',
      '1.5:$_key',
      '1234567:$_key',
      '1:$_key:2',
      '1:$_key\n',
    ];
    for (final item in notStates) {
      test('does not read ${formatJson(item)} as a state', () {
        expect(parseKeyState(item), isNull);
      });
    }

    test('is never printed with its key', () {
      final state = KeyState(generation: 2, key: _key);

      expect('$state', isNot(contains(_key)));
    });

    test('is the same state for the same generation and key', () {
      expect(
        KeyState(generation: 1, key: _key),
        equals(KeyState(generation: 1, key: _key)),
      );
      expect(
        KeyState(generation: 1, key: _key).hashCode,
        equals(KeyState(generation: 1, key: _key).hashCode),
      );
      expect(
        KeyState(generation: 1, key: _key),
        isNot(equals(KeyState(generation: 2, key: _key))),
      );
    });
  });

  group('databaseFileName', () {
    test('is the name itself for the first generation, '
        'so that an existing file is found', () {
      expect(
        databaseFileName('boardroom.db', firstGeneration),
        equals('boardroom.db'),
      );
    });

    test('is another name for each generation after, '
        'so that no file is ever created over another', () {
      final names = [
        0,
        1,
        2,
        10,
      ].map((generation) => databaseFileName('boardroom.db', generation));

      expect(
        names,
        equals([
          'boardroom.db',
          'boardroom.db.1',
          'boardroom.db.2',
          'boardroom.db.10',
        ]),
      );
      expect(names.toSet(), hasLength(4));
    });
  });
}
