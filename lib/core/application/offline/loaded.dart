import 'package:boardroom/core/domain/shared/constants.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'loaded.freezed.dart';

/// Whether data comes straight from the remote source, or from the local cache.
enum Freshness implements StableValue {
  /// Read from the remote source just now.
  fresh('fresh'),

  /// A saved copy, served because the remote source could not be reached.
  stale('stale');

  new(this.value);

  @override
  final String value;
}

/// Where data comes from: [FreshSource] or [StaleSource]. Stale data says when
/// it was cached, so a screen can show its age.
@freezed
sealed class DataSource with _$DataSource {
  /// Read from the remote source.
  const factory fresh() = FreshSource;

  /// A saved copy.
  const factory stale({
    /// When the copy was cached.
    required Instant cachedAt,
  }) = StaleSource;

  const new _();

  /// Whether the data is fresh or stale, as a stable value.
  Freshness get freshness => switch (this) {
    FreshSource() => Freshness.fresh,
    StaleSource() => Freshness.stale,
  };
}

/// Data, where it comes from, and the instant it was produced at. The instant
/// is the one of the clock when the use case answered, for saved data as well
/// as for fresh data: it is the "now" that a screen needs to judge what depends
/// on time (is a voting window over?) without reading a clock itself. For saved
/// data it is not `cachedAt`, which says how old the copy is.
@freezed
abstract class Loaded<T> with _$Loaded<T> {
  /// Creates a loaded value.
  const factory({
    required T data,
    required DataSource source,
    required Instant loadedAt,
  }) = _Loaded<T>;
}
