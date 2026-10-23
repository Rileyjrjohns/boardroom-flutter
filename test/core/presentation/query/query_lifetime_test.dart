// Each step of these tests is a call of its own on a notifier or a container;
// a cascade would hide the order.
// ignore_for_file: cascade_invocations

import 'package:boardroom/core/presentation/providers.dart';
import 'package:boardroom/core/presentation/query/query_lifetime.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// The query client defaults of the React Native app: current for a minute, kept
// for five, dropped when the user leaves the open app.

void main() {
  late int loads;
  late NotifierProvider<_Epoch, int> epoch;
  late FutureProvider<int> query;

  setUp(() {
    loads = 0;
    epoch = NotifierProvider<_Epoch, int>(_Epoch.new);
    query = FutureProvider.autoDispose<int>((ref) async {
      ref.keepQueryFor();
      return ++loads;
    });
  });

  ProviderContainer container() {
    final created = ProviderContainer(
      overrides: [sessionEpochProvider.overrideWith((ref) => ref.watch(epoch))],
    );
    addTearDown(created.dispose);
    return created;
  }

  test('keeps the data while nobody listens, and gives it back at once', () {
    fakeAsync((async) {
      final providers = container();
      var subscription = providers.listen(query, (_, _) {});
      async.flushMicrotasks();
      subscription.close();

      async.elapse(const Duration(seconds: 30));
      subscription = providers.listen(query, (_, _) {});
      async.flushMicrotasks();

      expect(loads, 1);
      expect(providers.read(query).value, 1);
    });
  });

  test('asks again, keeping the previous value, when a screen comes back '
      'after the stale time', () {
    fakeAsync((async) {
      final providers = container();
      providers.listen(query, (_, _) {}).close();
      async.flushMicrotasks();

      async.elapse(queryStaleTime + const Duration(seconds: 1));
      final seen = <AsyncValue<int>>[];
      providers.listen(
        query,
        (_, next) => seen.add(next),
        fireImmediately: true,
      );
      async.flushMicrotasks();

      providers.read(query);
      async.elapse(const Duration(milliseconds: 10));

      expect(loads, 2);
      expect(seen.first.value, 1);
      expect(providers.read(query).value, 2);
    });
  });

  test('drops the data once nobody listened for the gc time', () {
    fakeAsync((async) {
      final providers = container();
      providers.listen(query, (_, _) {}).close();
      async.flushMicrotasks();

      async.elapse(queryGcTime + const Duration(seconds: 1));
      providers.listen(query, (_, _) {});
      async.flushMicrotasks();

      expect(loads, 2);
    });
  });

  test('drops the data when the user leaves the open app', () {
    fakeAsync((async) {
      final providers = container();
      final first = providers.listen(query, (_, _) {});
      async.flushMicrotasks();
      first.close();

      expect(providers.exists(query), isTrue);
      providers.read(epoch.notifier).bump();
      providers.read(sessionEpochProvider);
      async.elapse(const Duration(milliseconds: 10));

      expect(providers.exists(query), isFalse);
    });
  });
}

class _Epoch extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}
