import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/shared/validation.dart';
import 'package:boardroom/domain/value_objects/page_cursor.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'page_request.freezed.dart';

/// The size of a page when the caller does not ask for one.
const int defaultPageLimit = 20;

/// The largest page a caller may ask for.
const int maxPageLimit = 50;

/// Which page to read: after [cursor] (the first page when null), at most
/// [limit] items.
@freezed
abstract class PageRequest with _$PageRequest {
  /// Creates a request from already validated parts. Use [createPageRequest]
  /// to validate a limit.
  const factory({required int limit, PageCursor? cursor}) = _PageRequest;
}

/// Validates the request: [limit] is a whole number from 1 to [maxPageLimit]
/// and defaults to [defaultPageLimit]; [cursor] is null for the first page.
Result<PageRequest, ValidationError> createPageRequest({
  PageCursor? cursor,
  num limit = defaultPageLimit,
}) => map(
  requireIntegerInRange(ValidationField.pageLimit, limit, 1, maxPageLimit),
  (validLimit) => PageRequest(limit: validLimit, cursor: cursor),
);
