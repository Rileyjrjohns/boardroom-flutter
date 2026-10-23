import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:boardroom/features/meetings/domain/entities/resolution.dart';
import 'package:boardroom/features/meetings/presentation/screens/meeting_detail_screen.dart';
import 'package:boardroom/features/meetings/presentation/slots/resolution_actions.dart';
import 'package:boardroom/features/meetings/presentation/test_ids.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/builders/builders.dart';
import '../../../../support/presentation/test_app.dart';
import '../support/meetings_screen_support.dart';

// The meetings show what a feature plugs into their resolutions, and know
// nothing of the votes: the slot of these tests is made of one sentence. (The
// votes in the slot are tested with the votes.)

const String _actions = 'Something to do about';

final Meeting _meeting = aMeetingWithAgenda();

String _actionsText(String title) => '$_actions $title';

Iterable<Resolution> get _resolutions => [
  for (final item in _meeting.agenda) ?item.resolution,
];

Future<ProviderContainer> _render(
  WidgetTester tester, {
  ResolutionActionsBuilder? builder,
}) async {
  final app = TestApp();
  app.fakes.meetings.addMeeting(_meeting);
  // The slot is filled in a scope of its own, over the root container that
  // already holds the one of the composition.
  final providers = await pumpScreen(
    tester,
    ProviderScope(
      overrides: [resolutionActionsProvider.overrideWithValue(builder)],
      child: MeetingDetailScreen(meetingId: _meeting.id),
    ),
    app: app,
  );
  await tester.pumpAndSettle();
  return providers;
}

void main() {
  final en = l10nOf();

  group('MeetingDetailScreen, with a feature plugged into its resolutions', () {
    testWidgets(
      'shows what the feature adds under each resolution, in the place of the '
      'line about the vote',
      (tester) async {
        final providers = await _render(
          tester,
          builder: (context, {required meeting, required resolution}) =>
              Text(_actionsText(resolution.title)),
        );

        expect(_resolutions, isNotEmpty);
        for (final resolution in _resolutions) {
          expect(find.text(_actionsText(resolution.title)), findsOneWidget);
        }
        expect(find.text(en.meetingsMeetingResolutionNoVote), findsNothing);
        await finish(tester, providers);
      },
    );

    testWidgets(
      'gives the feature the meeting and the resolution it is shown under',
      (tester) async {
        final seen = <(Meeting, Resolution)>[];
        final providers = await _render(
          tester,
          builder: (context, {required meeting, required resolution}) {
            seen.add((meeting, resolution));
            return const SizedBox.shrink();
          },
        );

        expect(seen.map((pair) => pair.$1.id).toSet(), {_meeting.id});
        expect(seen.map((pair) => pair.$2.id).toSet(), {
          for (final resolution in _resolutions) resolution.id,
        });
        await finish(tester, providers);
      },
    );

    testWidgets(
      'is display only when the feature adds nothing: the vote the server '
      'recorded, and nothing to do',
      (tester) async {
        final providers = await _render(tester);

        expect(
          find.text(en.meetingsMeetingResolutionNoVote),
          findsNWidgets(_resolutions.length),
        );
        expect(
          byTestId(resolutionTestId(_resolutions.first.id)),
          findsOneWidget,
        );
        await finish(tester, providers);
      },
    );
  });

  group('the slot of the resolution actions', () {
    test('adds nothing when nothing is plugged into it: '
        'the meeting is display only', () {
      final providers = ProviderContainer();
      addTearDown(providers.dispose);

      expect(providers.read(resolutionActionsProvider), isNull);
    });

    test(
      'gives what is plugged into it to the components below the provider',
      () {
        Widget builder(
          BuildContext context, {
          required Meeting meeting,
          required Resolution resolution,
        }) => const SizedBox.shrink();
        final providers = ProviderContainer(
          overrides: [resolutionActionsProvider.overrideWithValue(builder)],
        );
        addTearDown(providers.dispose);

        expect(providers.read(resolutionActionsProvider), same(builder));
      },
    );
  });
}
