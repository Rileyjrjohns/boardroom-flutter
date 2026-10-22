/// A copy of plain data for the fakes of the caches and of the outbox, which
/// copy what they are given and what they hand back, as the real adapters do by
/// turning the data into rows and back, so that a test cannot pass by accident
/// because a use case changed an object the fake also holds.
///
/// In Dart the entities, the pages and the errors are immutable values (the
/// lists they hold are unmodifiable), so sharing one cannot let a change slip
/// from a use case into a fake: the value is returned as it is. A list that
/// the fake builds itself is a new list each time (`List.of`).
T copyPlain<T>(T value) => value;
