import 'package:boardroom/domain/value_objects/page_cursor.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'page.freezed.dart';

/// One page of a list. [nextCursor] is null on the last page.
@freezed
abstract class Page<T> with _$Page<T> {
  /// Creates a page that holds [items] as given. Use [createPage] to get a
  /// page that does not share its list with the caller.
  const factory({required List<T> items, PageCursor? nextCursor}) = _Page<T>;
}

/// Builds a page. The items are copied, so the page does not share a list with
/// its caller.
Page<T> createPage<T>(List<T> items, [PageCursor? nextCursor]) =>
    Page<T>(items: List<T>.of(items), nextCursor: nextCursor);
