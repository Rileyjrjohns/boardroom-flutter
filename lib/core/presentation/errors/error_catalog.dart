import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/l10n/app_localizations.dart';

/// The text of a code: a function of the localizations, so that the language
/// is the one of the screen at the time the text is shown.
typedef ErrorMessage = String Function(AppLocalizations l10n);

/// What the screens know of the failures of the app: which codes they have a
/// text for, what it is, and which of them a second try can fix. The codes
/// belong to the core and to the features (each declares its own: the session
/// codes are `auth`'s), so the core does not list them: it declares the shape
/// it needs and `lib/app` assembles the catalog from what everybody says.
final class ErrorCatalog {
  /// Creates a catalog from the [messages] by code (it must tell
  /// `unexpected`, the text of any code with none) and the [isRetryableCode]
  /// rule.
  new({
    required Map<String, ErrorMessage> messages,
    required bool Function(String code) isRetryableCode,
  }) : _messages = Map.unmodifiable(messages),
       _isRetryable = isRetryableCode,
       assert(
         messages.containsKey('unexpected'),
         'the catalog must tell unexpected',
       );

  final Map<String, ErrorMessage> _messages;
  final bool Function(String code) _isRetryable;

  /// Whether a screen has a text for a failure with this [code].
  bool has(String code) => _messages.containsKey(code);

  /// The text of [code], or the one of `unexpected` for a code with none.
  String messageOf(AppLocalizations l10n, String code) {
    final message =
        _messages[code] ?? _messages[RepositoryErrorCode.unexpected.value]!;
    return message(l10n);
  }

  /// Whether asking again can fix a failure with this [code].
  bool isRetryableCode(String code) => _isRetryable(code);
}

/// What the core says of its own families: reading a source, reading a store,
/// building a request. The same on every screen.
final Map<String, ErrorMessage> coreErrorMessages = Map.unmodifiable({
  RepositoryErrorCode.networkUnavailable.value: (AppLocalizations l) =>
      l.coreErrorsNetworkUnavailable,
  RepositoryErrorCode.unauthorized.value: (AppLocalizations l) =>
      l.coreErrorsUnauthorized,
  RepositoryErrorCode.forbidden.value: (AppLocalizations l) =>
      l.coreErrorsForbidden,
  RepositoryErrorCode.notFound.value: (AppLocalizations l) =>
      l.coreErrorsNotFound,
  RepositoryErrorCode.unexpected.value: (AppLocalizations l) =>
      l.coreErrorsUnexpected,
  StorageErrorCode.readFailed.value: (AppLocalizations l) =>
      l.coreErrorsStorageReadFailed,
  StorageErrorCode.writeFailed.value: (AppLocalizations l) =>
      l.coreErrorsStorageWriteFailed,
  ValidationErrorCode.validation.value: (AppLocalizations l) =>
      l.coreErrorsValidation,
});
