/// The root of every error of the app, and the families of the core.
///
/// An error is plain data with a stable [AppError.code] and, for some, a few
/// more fields. It carries no user-facing text: the presentation turns a code
/// into a message of the language of the user. The codes are unique across all
/// the families (a test of the composition checks it, as it is the only place
/// that sees every family), so errors of several concerns can be told apart by
/// `code` alone.
///
/// [AppError] is open: a feature declares the errors that are its own, as a
/// family sealed in its own library (`AuthenticationError`, `BiometricError`,
/// `VotingError`, `ScreenProtectionError`...), and the core does not know them.
/// A `switch` over a family is checked to be exhaustive, since Dart only lets a
/// sealed class be extended inside its own library; a `switch` over [AppError]
/// itself, whose subclasses are in several libraries, is not. The families of
/// the core are here, one `part` file each: the repository errors, the storage
/// errors and the validation error. Import this file to use any of them.
library;

import 'package:boardroom/core/domain/shared/constants.dart';
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

part 'repository_error.dart';
part 'storage_error.dart';
part 'validation_error.dart';

/// Every error of the app. A family extends it, in the core or in a feature.
///
/// Two errors are equal when they are of the same class and carry the same
/// data.
@immutable
abstract base class AppError {
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
