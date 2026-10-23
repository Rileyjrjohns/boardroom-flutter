import 'package:boardroom/domain/shared/result.dart';

/// Turns a list of results into the result of the list: the values in order,
/// or the first failure. For mapping the members of a collection through the
/// factories of the domain.
Result<List<T>, E> collect<T, E>(Iterable<Result<T, E>> results) {
  final values = <T>[];
  for (final result in results) {
    switch (result) {
      case Ok(:final value):
        values.add(value);
      case Err(:final error):
        return err(error);
    }
  }
  return ok(values);
}
