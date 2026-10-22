import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/shared/validation.dart';
import 'package:boardroom/domain/value_objects/email_address.dart';
import 'package:boardroom/domain/value_objects/ids.dart';
import 'package:boardroom/domain/value_objects/watermark.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'user.freezed.dart';

/// The longest full name, in UTF-16 code units, once trimmed.
const int maxFullNameLength = 200;

/// A person who signs in.
@freezed
abstract class User with _$User implements WatermarkReader {
  /// Creates a user from validated parts. Use [createUser] to validate the
  /// full name.
  const factory({
    required UserId id,
    required String fullName,
    required EmailAddress email,
  }) = _User;
}

/// Builds a user. The full name is trimmed; it must not be blank nor longer
/// than [maxFullNameLength].
Result<User, ValidationError> createUser({
  required UserId id,
  required String fullName,
  required EmailAddress email,
}) => map(
  requireText(ValidationField.fullName, fullName, maxFullNameLength),
  (name) => User(id: id, fullName: name, email: email),
);
