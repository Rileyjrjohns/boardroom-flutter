// Each step of these tests is a call of its own on a notifier or a container;
// a cascade would hide the order.
// ignore_for_file: cascade_invocations

import 'dart:async';

import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/presentation/providers.dart';
import 'package:boardroom/core/presentation/query/result_action.dart';
import 'package:boardroom/features/auth/domain/errors/authentication_error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// The scenarios of `useResultMutation.test.tsx`.

final NotifierProvider<_Action, ActionState> _action =
    NotifierProvider.autoDispose<_Action, ActionState>(_Action.new);

class _Action extends Notifier<ActionState> {
  Future<Result<int, AppError>> Function() execute = () async => ok(1);
  final List<int> successes = [];
  final List<(String, int)> failures = [];

  @override
  ActionState build() => const ActionState.idle();

  Future<void> run() => runResultAction<int>(
    ref: ref,
    current: () => state,
    emit: (next) => state = next,
    execute: () => execute(),
    onSuccess: (output, startedUnder) => successes.add(output + startedUnder),
    onFailure: (failure, startedUnder) =>
        failures.add((failure.code, startedUnder)),
  );
}

void main() {
  late List<(String, int?)> ended;

  ProviderContainer container() {
    final created = ProviderContainer(
      overrides: [
        sessionEpochProvider.overrideWithValue(7),
        sessionEndHandlerProvider.overrideWithValue(
          (code, startedUnder) => ended.add((code, startedUnder)),
        ),
      ],
    );
    addTearDown(created.dispose);
    return created;
  }

  setUp(() => ended = []);

  test('goes pending, then idle after a success, telling the epoch it started '
      'under', () async {
    final providers = container();
    final states = <ActionState>[];
    providers.listen(_action, (_, next) => states.add(next));

    await providers.read(_action.notifier).run();

    expect(states, [const ActionState.pending(), const ActionState.idle()]);
    expect(providers.read(_action.notifier).successes, [8]);
  });

  test(
    'keeps the failure, and tells a session-ending code to the handler',
    () async {
      final providers = container();
      providers.listen(_action, (_, _) {});
      providers.read(_action.notifier).execute = () async =>
          err(sessionExpired());

      await providers.read(_action.notifier).run();

      expect(providers.read(_action).failure, sessionExpired());
      expect(providers.read(_action).isPending, isFalse);
      expect(ended, [('sessionExpired', 7)]);
      expect(providers.read(_action.notifier).failures, [
        ('sessionExpired', 7),
      ]);
    },
  );

  test('reads a thrown error as unexpected', () async {
    final providers = container();
    providers.listen(_action, (_, _) {});
    providers.read(_action.notifier).execute = () async =>
        throw StateError('x');

    await providers.read(_action.notifier).run();

    expect(providers.read(_action).failure, unexpected());
  });

  test('ignores a second call while one is under way', () async {
    final providers = container();
    providers.listen(_action, (_, _) {});
    final gate = Completer<Result<int, AppError>>();
    var calls = 0;
    providers.read(_action.notifier).execute = () {
      calls++;
      return gate.future;
    };

    final first = providers.read(_action.notifier).run();
    await providers.read(_action.notifier).run();
    gate.complete(ok(1));
    await first;

    expect(calls, 1);
  });

  test('writes nothing once the notifier is gone', () async {
    final providers = container();
    final subscription = providers.listen(_action, (_, _) {});
    final gate = Completer<Result<int, AppError>>();
    final notifier = providers.read(_action.notifier)
      ..execute = () => gate.future;

    final running = notifier.run();
    subscription.close();
    await Future<void>.delayed(Duration.zero);
    gate.complete(err(forbidden()));
    await running;

    expect(ended, isEmpty);
  });

  test('can be reset to idle and compared by value', () {
    expect(const ActionState.idle(), const ActionState.idle());
    expect(const ActionState.idle(), isNot(const ActionState.pending()));
    expect(
      const ActionState.idle().hashCode,
      const ActionState.idle().hashCode,
    );
  });
}
