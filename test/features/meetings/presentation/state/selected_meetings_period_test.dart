import 'package:boardroom/features/meetings/domain/value_objects/meeting_period.dart';
import 'package:boardroom/features/meetings/presentation/state/selected_meetings_period.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// The period of the meetings list is state of the interface, one per app (per
// provider container). The scenarios are the ones of meetingsStore.test.tsx of
// the React Native app.

ProviderContainer _container() {
  final created = ProviderContainer();
  addTearDown(created.dispose);
  return created;
}

void main() {
  group('createMeetingsStore', () {
    test('starts on the upcoming meetings', () {
      expect(
        _container().read(selectedMeetingsPeriodProvider),
        MeetingPeriod.upcoming,
      );
    });

    test('selects a period', () {
      final container = _container();

      container
          .read(selectedMeetingsPeriodProvider.notifier)
          .select(MeetingPeriod.past);

      expect(
        container.read(selectedMeetingsPeriodProvider),
        MeetingPeriod.past,
      );
    });

    test('notifies its subscribers of a change', () {
      final container = _container();
      final periods = <MeetingPeriod>[];
      container.listen(
        selectedMeetingsPeriodProvider,
        (_, next) => periods.add(next),
      );

      container
          .read(selectedMeetingsPeriodProvider.notifier)
          .select(MeetingPeriod.past);

      expect(periods, [MeetingPeriod.past]);
    });

    test(
      'creates a new store at every call: no state is shared between two',
      () {
        final first = _container();
        final second = _container();

        first
            .read(selectedMeetingsPeriodProvider.notifier)
            .select(MeetingPeriod.past);

        expect(
          second.read(selectedMeetingsPeriodProvider),
          MeetingPeriod.upcoming,
        );
      },
    );
  });
}
