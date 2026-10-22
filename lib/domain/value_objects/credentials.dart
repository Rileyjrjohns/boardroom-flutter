import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/email_address.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'credentials.freezed.dart';

/// What a user types to sign in. The password is kept exactly as typed (no
/// trimming) and must never be logged, stored or put in an error: its text is
/// left out of [toString].
@freezed
abstract class Credentials with _$Credentials {
  /// Creates credentials from an already validated [email]. Use
  /// [createCredentials] to validate what was typed.
  const factory({required EmailAddress email, required String password}) =
      _Credentials;

  const new _();

  @override
  String toString() => 'Credentials(email: $email, password: <hidden>)';
}

/// Validates what the user typed: the email first, then the password, which
/// must not be empty and is otherwise kept as typed.
Result<Credentials, ValidationError> createCredentials(
  String rawEmail,
  String password,
) => andThen(
  parseEmailAddress(rawEmail),
  (email) => password.isEmpty
      ? err(validationError(ValidationField.password, ValidationRule.required))
      : ok(Credentials(email: email, password: password)),
);
