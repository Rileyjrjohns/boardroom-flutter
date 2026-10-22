import 'package:boardroom/domain/entities/agenda_item.dart';
import 'package:boardroom/domain/entities/resolution.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:test/test.dart';

import '../support/builders.dart';
import '../support/names.dart';

AgendaItemInput _valid({
  num position = 1,
  String title = 'Budget',
  String? description,
  Resolution? resolution,
}) => AgendaItemInput(
  id: anAgendaItemId(),
  position: position,
  title: title,
  description: description,
  resolution: resolution,
);

void main() {
  group('createAgendaItem', () {
    test('builds an item with neither description nor resolution', () {
      final item = unwrap(createAgendaItem(_valid()));

      expect(
        item,
        equals(AgendaItem(id: anAgendaItemId(), position: 1, title: 'Budget')),
      );
      expect(item.description, isNull);
      expect(item.resolution, isNull);
    });

    test('keeps a trimmed description and the resolution', () {
      final resolution = aResolution();

      expect(
        createAgendaItem(
          _valid(description: ' Context ', resolution: resolution),
        ),
        equals(
          ok(
            AgendaItem(
              id: anAgendaItemId(),
              position: 1,
              title: 'Budget',
              description: 'Context',
              resolution: resolution,
            ),
          ),
        ),
      );
    });

    test('treats a blank description as none', () {
      expect(
        unwrap(createAgendaItem(_valid(description: '  '))).description,
        isNull,
      );
    });

    test('rejects a blank title', () {
      expect(
        createAgendaItem(_valid(title: '')),
        equals(
          err(validationError(ValidationField.title, ValidationRule.required)),
        ),
      );
    });

    test('rejects a description that is too long', () {
      expect(
        createAgendaItem(_valid(description: 'a' * 5001)),
        equals(
          err(
            validationError(
              ValidationField.description,
              ValidationRule.tooLong,
            ),
          ),
        ),
      );
    });

    for (final (position, rule) in <(num, ValidationRule)>[
      (0, ValidationRule.outOfRange),
      (1001, ValidationRule.outOfRange),
      (1.5, ValidationRule.notAnInteger),
    ]) {
      test('rejects the position ${formatPretty(position)}', () {
        expect(
          createAgendaItem(_valid(position: position)),
          equals(err(validationError(ValidationField.position, rule))),
        );
      });
    }
  });
}
