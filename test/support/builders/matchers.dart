import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:test/test.dart';

/// Matches an [AppError] with the given [code] and the given [payload], the
/// way a React Native test compares an error with `{ code, ...fields }`.
Matcher isAppError(String code, [Map<String, Object?> payload = const {}]) =>
    isA<AppError>()
        .having((error) => error.code, 'code', code)
        .having((error) => error.payload, 'payload', equals(payload));
