import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/shared/validation.dart';

const int _maxEmailLength = 254;

/// One `@`, a dot in the domain, no whitespace. Deliverability is the remote
/// source's business.
final RegExp _emailFormat = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// A syntactically plausible email address, trimmed and in lower case. A
/// `String` at runtime (an extension type).
///
/// It can only be made by [parseEmailAddress].
extension type const EmailAddress._(String _address) implements String;

/// Validates [raw]: trimmed, lower-cased, not empty, at most 254 characters,
/// one `@` and a dot in the domain.
Result<EmailAddress, ValidationError> parseEmailAddress(String raw) {
  final email = trimText(raw).toLowerCase();
  if (email.isEmpty) {
    return err(validationError(ValidationField.email, ValidationRule.required));
  }
  if (email.length > _maxEmailLength) {
    return err(validationError(ValidationField.email, ValidationRule.tooLong));
  }
  if (!_emailFormat.hasMatch(email)) {
    return err(
      validationError(ValidationField.email, ValidationRule.invalidFormat),
    );
  }
  return ok(EmailAddress._(email));
}
