import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'cache_entry.freezed.dart';

/// A value read back from a local cache, with the instant it was stored at.
@freezed
abstract class CacheEntry<T> with _$CacheEntry<T> {
  /// Creates an entry.
  const factory({
    required T value,

    /// The instant given to the `save` call that stored the value, not one the
    /// cache reads itself. The application compares it with the clock to refuse
    /// an entry that is too old or that is dated in the future.
    required Instant cachedAt,
  }) = _CacheEntry<T>;
}
