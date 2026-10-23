import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/page.dart';
import 'package:boardroom/core/domain/value_objects/page_cursor.dart';
import 'package:boardroom/core/domain/value_objects/page_request.dart';
import 'package:test/test.dart';

import '../../../support/builders/builders.dart';
import '../../../support/builders/names.dart';

void main() {
  group('parsePageCursor', () {
    test('keeps an opaque cursor, trimmed', () {
      expect(
        parsePageCursor(' eyJvZmZzZXQiOjIwfQ== '),
        equals(ok('eyJvZmZzZXQiOjIwfQ==')),
      );
    });

    for (final raw in ['\ud800', 'a\udc00b', 'abc\ud83d']) {
      test('rejects the ill-formed cursor ${formatJson(raw)}', () {
        expect(
          parsePageCursor(raw),
          equals(
            err(
              validationError(
                ValidationField.pageCursor,
                ValidationRule.invalidFormat,
              ),
            ),
          ),
        );
      });
    }

    test('keeps a cursor with a character outside the basic plane', () {
      expect(parsePageCursor('a\u{1F600}'), equals(ok('a\u{1F600}')));
    });

    test('rejects a blank cursor and one that is too long', () {
      expect(
        parsePageCursor(''),
        equals(
          err(
            validationError(
              ValidationField.pageCursor,
              ValidationRule.required,
            ),
          ),
        ),
      );
      expect(
        parsePageCursor('a' * 513),
        equals(
          err(
            validationError(ValidationField.pageCursor, ValidationRule.tooLong),
          ),
        ),
      );
    });
  });

  group('createPageRequest', () {
    final cursor = unwrap(parsePageCursor('next'));

    test(
      'asks for the first page with the default limit when given nothing',
      () {
        expect(
          createPageRequest(),
          equals(ok(const PageRequest(limit: defaultPageLimit))),
        );
      },
    );

    test('keeps the cursor and the limit it is given', () {
      expect(
        createPageRequest(cursor: cursor, limit: 10),
        equals(ok(PageRequest(cursor: cursor, limit: 10))),
      );
    });

    test('has no cursor key on the first page', () {
      expect(unwrap(createPageRequest(limit: 10)).cursor, isNull);
    });

    test('bounds the limit between 1 and the maximum', () {
      expect(
        createPageRequest(limit: 1),
        equals(ok(const PageRequest(limit: 1))),
      );
      expect(
        createPageRequest(limit: maxPageLimit),
        equals(ok(const PageRequest(limit: maxPageLimit))),
      );
      final outOfRange = err(
        validationError(ValidationField.pageLimit, ValidationRule.outOfRange),
      );
      expect(createPageRequest(limit: 0), equals(outOfRange));
      expect(createPageRequest(limit: maxPageLimit + 1), equals(outOfRange));
    });

    test('rejects a limit that is not an integer', () {
      expect(
        createPageRequest(limit: 2.5),
        equals(
          err(
            validationError(
              ValidationField.pageLimit,
              ValidationRule.notAnInteger,
            ),
          ),
        ),
      );
    });
  });

  group('createPage', () {
    test('holds a copy of the items and the next cursor', () {
      final items = ['a', 'b'];
      final cursor = unwrap(parsePageCursor('next'));
      final page = createPage(items, cursor);
      items.add('c');

      expect(page, equals(Page(items: ['a', 'b'], nextCursor: cursor)));
      expect(page.items, equals(['a', 'b']));
    });

    test('has no next cursor on the last page', () {
      expect(createPage(['a']), equals(const Page(items: ['a'])));
      expect(createPage(['a']).nextCursor, isNull);
    });
  });
}
