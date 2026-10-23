import 'package:boardroom/domain/shared/result.dart';

/// A value that is valid by construction turned out not to be: a constant, a
/// seed, a clamped reading. It is a programming error found by the first test
/// that runs the code, never a runtime condition, so it is thrown instead of
/// returned. It stops at the first use of the value (a configuration
/// constant), or at the edge of the function that catches it. Data that comes
/// from outside, such as the fixtures, is never read with it: that is an error
/// `Result` to return.
final class InvalidStaticValueError extends Error {
  /// Creates the error for a value found invalid, described by [detail].
  new(this.detail);

  /// What was wrong: the error the factory gave.
  final String detail;

  @override
  String toString() => 'Invalid static value: $detail';
}

/// The value of a success. For data written in the code itself, where a
/// failure of a domain factory means the data is wrong. Never use it on data
/// that comes from outside: that is an error `Result` to return.
T valid<T, E>(Result<T, E> result) => switch (result) {
  Ok(:final value) => value,
  Err(:final error) => throw InvalidStaticValueError('$error'),
};
