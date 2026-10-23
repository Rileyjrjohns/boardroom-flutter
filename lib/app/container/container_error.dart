// The container errors: why the composition root could not hand over a
// container. Plain data, like every error. They extend the open `AppError` of
// the core, and the family is sealed here, in the composition that owns it.

import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/constants.dart';
import 'package:boardroom/core/infrastructure/persistence/protected_database.dart';

/// The code of the error that stands for the start of the app being abandoned:
/// the gate of the app puts it on a start that was cancelled (the app was
/// closed while the container was still being built). The container itself
/// never produces it.
const String startupAbortedCode = 'startupAborted';

/// The codes of the container errors.
enum ContainerErrorCode implements StableValue {
  /// The environment names a way of wiring that does not exist.
  invalidAdaptersSetting('invalidAdaptersSetting'),

  /// The environment names no way of wiring, outside of a development build.
  missingAdaptersSetting('missingAdaptersSetting'),

  /// The real adapters need the address of the API, and the environment gives
  /// none.
  missingApiBaseUrl('missingApiBaseUrl'),

  /// The address of the API is not an `http` or `https` URL of a host, or
  /// carries more than that.
  invalidApiBaseUrl('invalidApiBaseUrl'),

  /// The address of the API is `http`, in a build that is not a development
  /// one, for a host that is not on this machine.
  insecureApiBaseUrl('insecureApiBaseUrl'),

  /// The request timeout is not a whole number of milliseconds within the
  /// bounds the app accepts.
  invalidRequestTimeout('invalidRequestTimeout'),

  /// The setting that says whether the device passcode is accepted is not a yes
  /// or a no.
  invalidBiometricFallback('invalidBiometricFallback'),

  /// The local database, or the key that protects it, cannot be had.
  storageUnavailable('storageUnavailable'),

  /// Something the device provides could not be loaded or set up.
  platformUnavailable('platformUnavailable'),

  /// The seed of the simulated server, or the session built from it, broke an
  /// invariant.
  mockDataInvalid('mockDataInvalid');

  new(this.value);

  @override
  final String value;
}

/// Why the composition root could not hand over a container.
sealed class ContainerError extends AppError {
  /// Creates a container error.
  const new();
}

/// The environment names a way of wiring that does not exist.
final class InvalidAdaptersSettingError extends ContainerError {
  /// Creates the error for the [received] setting.
  const new({required this.received});

  /// What was found, trimmed. It is configuration, not personal data.
  final String received;

  @override
  String get code => ContainerErrorCode.invalidAdaptersSetting.value;

  @override
  Map<String, Object?> get payload => {_receivedKey: received};
}

/// The environment names no way of wiring, outside of a development build. The
/// development adapters are a default for development only: a release build
/// that was not told what to talk to must not start on a simulated server.
final class MissingAdaptersSettingError extends ContainerError {
  /// Creates the error.
  const new();

  @override
  String get code => ContainerErrorCode.missingAdaptersSetting.value;
}

/// The real adapters need the address of the API, and the environment gives
/// none.
final class MissingApiBaseUrlError extends ContainerError {
  /// Creates the error.
  const new();

  @override
  String get code => ContainerErrorCode.missingApiBaseUrl.value;
}

/// The address of the API is not an `http` or `https` URL of a host, or carries
/// more than that.
final class InvalidApiBaseUrlError extends ContainerError {
  /// Creates the error.
  const new();

  @override
  String get code => ContainerErrorCode.invalidApiBaseUrl.value;
}

/// The address of the API is `http`, in a build that is not a development one,
/// for a host that is not on this machine: the session token and the
/// confidential content would cross the network in clear.
final class InsecureApiBaseUrlError extends ContainerError {
  /// Creates the error.
  const new();

  @override
  String get code => ContainerErrorCode.insecureApiBaseUrl.value;
}

/// The request timeout is not a whole number of milliseconds within the bounds
/// the app accepts.
final class InvalidRequestTimeoutError extends ContainerError {
  /// Creates the error.
  const new();

  @override
  String get code => ContainerErrorCode.invalidRequestTimeout.value;
}

/// The setting that says whether the device passcode is accepted is not a yes
/// or a no.
final class InvalidBiometricFallbackError extends ContainerError {
  /// Creates the error.
  const new();

  @override
  String get code => ContainerErrorCode.invalidBiometricFallback.value;
}

/// The local database, or the key that protects it, cannot be had: the app does
/// not start rather than keep confidential data unprotected, or lose votes it
/// could not store.
final class StorageUnavailableError extends ContainerError {
  /// Creates the error for the [reason] the database cannot be had.
  const new({required this.reason});

  /// Which part failed.
  final DatabaseFailureReason reason;

  @override
  String get code => ContainerErrorCode.storageUnavailable.value;

  @override
  Map<String, Object?> get payload => {_reasonKey: reason};
}

/// Something the device provides could not be loaded or set up: a native module
/// that is missing from the build, or that fails when it is used for the first
/// time. Nothing says which: the error is caught where it is thrown, and what
/// it says (a message, a path) is not kept.
final class PlatformUnavailableError extends ContainerError {
  /// Creates the error.
  const new();

  @override
  String get code => ContainerErrorCode.platformUnavailable.value;
}

/// The seed of the simulated server, or the session built from it, broke an
/// invariant.
final class MockDataInvalidError extends ContainerError {
  /// Creates the error with the [detail] of what is wrong.
  const new({required this.detail});

  /// Names a place in a fixture or a rule of the content, never a value.
  final String detail;

  @override
  String get code => ContainerErrorCode.mockDataInvalid.value;

  @override
  Map<String, Object?> get payload => {_detailKey: detail};
}

const String _receivedKey = 'received';
const String _reasonKey = 'reason';
const String _detailKey = 'detail';

/// Builds an [InvalidAdaptersSettingError].
InvalidAdaptersSettingError invalidAdaptersSetting(String received) =>
    InvalidAdaptersSettingError(received: received);

/// Builds a [MissingAdaptersSettingError].
MissingAdaptersSettingError missingAdaptersSetting() =>
    const MissingAdaptersSettingError();

/// Builds a [MissingApiBaseUrlError].
MissingApiBaseUrlError missingApiBaseUrl() => const MissingApiBaseUrlError();

/// Builds an [InvalidApiBaseUrlError].
InvalidApiBaseUrlError invalidApiBaseUrl() => const InvalidApiBaseUrlError();

/// Builds an [InsecureApiBaseUrlError].
InsecureApiBaseUrlError insecureApiBaseUrl() => const InsecureApiBaseUrlError();

/// Builds an [InvalidRequestTimeoutError].
InvalidRequestTimeoutError invalidRequestTimeout() =>
    const InvalidRequestTimeoutError();

/// Builds an [InvalidBiometricFallbackError].
InvalidBiometricFallbackError invalidBiometricFallback() =>
    const InvalidBiometricFallbackError();

/// Builds a [StorageUnavailableError].
StorageUnavailableError storageUnavailable(DatabaseFailureReason reason) =>
    StorageUnavailableError(reason: reason);

/// Builds a [PlatformUnavailableError].
PlatformUnavailableError platformUnavailable() =>
    const PlatformUnavailableError();

/// Builds a [MockDataInvalidError].
MockDataInvalidError mockDataInvalid(String detail) =>
    MockDataInvalidError(detail: detail);
