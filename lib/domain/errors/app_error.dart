/// Every error the domain defines, as sealed classes.
///
/// An error is plain data with a stable [AppError.code] and, for some, a few
/// more fields. It carries no user-facing text: the presentation turns a code
/// into a message of the language of the user. The codes are unique across all
/// the families (a test checks it), so errors of several concerns can be told
/// apart by `code` alone.
///
/// All the families live in one library (one `part` file each) because Dart
/// only lets a sealed class be extended inside its own library. That is what
/// makes a `switch` over an [AppError], or over any family, exhaustive. Import
/// this file to use any of them.
library;

import 'package:boardroom/domain/shared/constants.dart';
import 'package:boardroom/domain/value_objects/ids.dart' show ResolutionId;
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

part 'authentication_error.dart';
part 'biometric_error.dart';
part 'repository_error.dart';
part 'screen_protection_error.dart';
part 'storage_error.dart';
part 'validation_error.dart';
part 'vote_delivery_error.dart';
part 'voting_error.dart';

/// Every error the domain defines. Match on it with a `switch`: the families
/// are sealed too, so the switch is checked to be exhaustive.
///
/// Two errors are equal when they are of the same class and carry the same
/// data.
@immutable
sealed class AppError {
  /// Creates an error.
  const new();

  /// The stable string that identifies this kind of error, for example
  /// `'networkUnavailable'`. Unique across every family.
  String get code;

  /// The data this kind of error carries besides its [code]. Empty when it
  /// carries none; an optional field that is absent is left out.
  Map<String, Object?> get payload => const {};

  @override
  bool operator ==(Object other) =>
      other is AppError &&
      other.runtimeType == runtimeType &&
      const DeepCollectionEquality().equals(payload, other.payload);

  @override
  int get hashCode =>
      Object.hash(runtimeType, const DeepCollectionEquality().hash(payload));

  @override
  String toString() {
    final fields = [
      'code: $code',
      for (final MapEntry(:key, :value) in payload.entries)
        '$key: ${value is StableValue ? value.value : value}',
    ];
    return 'AppError(${fields.join(', ')})';
  }
}
