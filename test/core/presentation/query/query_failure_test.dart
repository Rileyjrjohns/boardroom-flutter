import 'package:boardroom/app/error_catalog.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/presentation/query/query_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final catalog = createAppErrorCatalog();

  group('unwrapResult', () {
    test('gives the data of a success', () {
      expect(unwrapResult<int, AppError>(ok(3)), 3);
    });

    test('throws the failure of an error, with the epoch it started under', () {
      final Result<int, AppError> failed = err(forbidden());

      expect(
        () => unwrapResult(failed, startedUnder: 2),
        throwsA(
          isA<QueryFailure>()
              .having((f) => f.error, 'error', forbidden())
              .having((f) => f.startedUnder, 'startedUnder', 2),
        ),
      );
    });
  });

  group('errorCodeOf', () {
    test('is the code of a failure the catalog has a text for', () {
      expect(
        errorCodeOf(QueryFailure(notFound()), catalog),
        RepositoryErrorCode.notFound.value,
      );
    });

    test('is unexpected for anything else', () {
      expect(errorCodeOf(null, catalog), 'unexpected');
      expect(errorCodeOf(StateError('x'), catalog), 'unexpected');
    });
  });

  test('a failure and a refusal print their code', () {
    expect(QueryFailure(notFound()).toString(), contains('notFound'));
    expect(itemRefusalCodes, {'forbidden', 'notFound'});
  });
}
