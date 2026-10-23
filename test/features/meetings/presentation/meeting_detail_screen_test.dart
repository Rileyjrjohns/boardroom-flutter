import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/core/presentation/format/formatters.dart';
import 'package:boardroom/core/presentation/test_ids.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:boardroom/features/meetings/domain/entities/agenda_item.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:boardroom/features/meetings/domain/entities/participant.dart';
import 'package:boardroom/features/meetings/domain/entities/resolution.dart';
import 'package:boardroom/features/meetings/domain/value_objects/vote_choice.dart';
import 'package:boardroom/features/meetings/presentation/screens/meeting_detail_screen.dart';
import 'package:boardroom/features/meetings/presentation/state/meeting_query.dart';
import 'package:boardroom/features/meetings/presentation/test_ids.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../../support/builders/builders.dart';
import '../../../support/fakes/create_fakes.dart';
import '../../../support/presentation/test_app.dart';
import 'support/meetings_screen_support.dart';

// The meeting detail over the real use cases and the fakes. The scenarios are
// the ones of MeetingDetailScreen.test.tsx of the React Native app.

final Instant _closesAt = at(millisPerDay);

final Meeting _meeting = aMeeting(
  agenda: [
    unwrap(
      createAgendaItem(
        AgendaItemInput(
          id: anAgendaItemId('opening'),
          position: 1,
          title: 'Opening',
          description: 'Welcome and apologies.',
        ),
      ),
    ),
    anAgendaItem(
      id: anAgendaItemId('budget'),
      position: 2,
      resolution: aResolution(
        id: aResolutionId('budget-vote'),
        closesAt: _closesAt,
        recordedVote: VoteChoice.against,
      ),
    ),
    anAgendaItem(
      id: anAgendaItemId('elections'),
      position: 3,
      title: 'Elections',
      resolution: aResolution(
        id: aResolutionId('elections-vote'),
        title: 'Elect the chair',
        status: ResolutionStatus.closed,
      ),
    ),
  ],
  documents: [
    aConfidentialDocument(
      id: aDocumentId('report'),
      title: 'Remuneration report',
      pageCount: 12,
    ),
    aDocument(id: aDocumentId('pack'), title: 'Board pack', pageCount: 1),
  ],
  participants: [
    aParticipant(fullName: 'Alice Martin'),
    aParticipant(
      userId: aUserId('user-2'),
      fullName: 'Bruno Durand',
      role: ParticipantRole.chair,
    ),
    aParticipant(
      userId: aUserId('user-4'),
      fullName: 'David Roux',
      role: ParticipantRole.guest,
    ),
  ],
);

/// The screen for what the router gives as `meetingId`, with the standard
/// meeting on the server.
Future<({TestApp app, ProviderContainer providers})> _renderDetailAt(
  WidgetTester tester,
  String meetingId, {
  TestApp? given,
  Locale locale = const Locale('en'),
}) async {
  final app = given ?? TestApp(meetingsPageSize: testPageSize);
  app.fakes.meetings.addMeeting(_meeting);
  final providers = await pumpScreen(
    tester,
    MeetingDetailScreen(meetingId: meetingId),
    app: app,
    locale: locale,
  );
  return (app: app, providers: providers);
}

Future<({TestApp app, ProviderContainer providers})> _renderDetail(
  WidgetTester tester, {
  TestApp? given,
  Locale locale = const Locale('en'),
}) => _renderDetailAt(tester, _meeting.id, given: given, locale: locale);

Finder _within(String id, Finder finder) =>
    find.descendant(of: byTestId(id), matching: finder);

/// The ids of the agenda items built, in the order of the tree.
List<String> _agendaIds(WidgetTester tester) => [
  for (final item in tester.widgetList(
    find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith('agenda-item-');
    }),
  ))
    (item.key! as ValueKey<String>).value,
];

/// The world of the use cases with the clock at [instant], and a session that
/// outlasts it.
TestApp _appAt(int instant) {
  final fakes = createFakes();
  fakes.auth.session = aSession(expiresAt: at(30 * millisPerDay));
  fakes.clock.set(at(instant));
  return TestApp(fakes: fakes, meetingsPageSize: testPageSize);
}

void main() {
  final en = l10nOf();
  late Formatters format;
  setUpAll(() async {
    await initializeDateFormatting();
    format = Formatters('en');
  });

  group('MeetingDetailScreen', () {
    testWidgets('shows a loading state, then the meeting', (tester) async {
      final (:providers, app: _) = await _renderDetail(tester);
      expect(byTestId(MeetingsTestIds.meetingLoading), findsOneWidget);

      await tester.pumpAndSettle();

      expect(byTestId(MeetingsTestIds.meetingDetail), findsOneWidget);
      expect(byTestId(MeetingsTestIds.meetingLoading), findsNothing);
      await finish(tester, providers);
    });

    group('the header', () {
      testWidgets('shows the title as a header, the date and the location', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        final (:providers, app: _) = await _renderDetail(tester);
        await tester.pumpAndSettle();

        expect(
          tester.getSemantics(byTestId(MeetingsTestIds.meetingTitle)),
          isSemantics(label: _meeting.title, isHeader: true),
        );
        expect(
          find.text(format.fullDateTime(_meeting.scheduledAt)),
          findsOneWidget,
        );
        expect(find.text(_meeting.location), findsOneWidget);
        semantics.dispose();
        await finish(tester, providers);
      });

      testWidgets('marks the sections as headers', (tester) async {
        final semantics = tester.ensureSemantics();
        final (:providers, app: _) = await _renderDetail(tester);
        await tester.pumpAndSettle();

        for (final label in [
          en.meetingsMeetingAgenda,
          en.meetingsMeetingDocuments,
          en.meetingsMeetingParticipants,
        ]) {
          expect(
            tester.getSemantics(find.text(label)),
            isSemantics(label: label, isHeader: true),
          );
        }
        semantics.dispose();
        await finish(tester, providers);
      });
    });

    group('the agenda', () {
      testWidgets('lists the items in order, numbered by their position', (
        tester,
      ) async {
        final (:providers, app: _) = await _renderDetail(tester);
        await tester.pumpAndSettle();

        expect(_agendaIds(tester), [
          agendaItemTestId('opening'),
          agendaItemTestId('budget'),
          agendaItemTestId('elections'),
        ]);
        expect(find.text('1. Opening'), findsOneWidget);
        expect(find.text('2. Budget'), findsOneWidget);
        expect(find.text('3. Elections'), findsOneWidget);
        expect(find.text('Welcome and apologies.'), findsOneWidget);
        await finish(tester, providers);
      });

      testWidgets(
        'shows the resolution of an item: where voting stands, its deadline '
        'and the vote of the user',
        (tester) async {
          final (:providers, app: _) = await _renderDetail(tester);
          await tester.pumpAndSettle();

          Finder open(Finder finder) =>
              _within(resolutionTestId('budget-vote'), finder);
          expect(open(find.text('Approve the budget')), findsOneWidget);
          expect(open(find.text(en.meetingsVotingStateOpen)), findsOneWidget);
          expect(
            open(
              find.text(
                en.meetingsMeetingVotingDeadline(format.dateTime(_closesAt)),
              ),
            ),
            findsOneWidget,
          );
          expect(
            open(
              find.text(
                en.meetingsMeetingResolutionYourVote(en.votesVoteChoiceAgainst),
              ),
            ),
            findsOneWidget,
          );
          await finish(tester, providers);
        },
      );

      testWidgets(
        'shows a closed resolution the user did not vote on, without a date '
        'it has none to give',
        (tester) async {
          final (:providers, app: _) = await _renderDetail(tester);
          await tester.pumpAndSettle();

          Finder closed(Finder finder) =>
              _within(resolutionTestId('elections-vote'), finder);
          expect(
            closed(find.text(en.meetingsVotingStateClosed)),
            findsOneWidget,
          );
          expect(
            closed(find.text(en.meetingsMeetingResolutionNoVote)),
            findsOneWidget,
          );
          expect(
            closed(
              find.textContaining(en.meetingsMeetingVotingDeadline('').trim()),
            ),
            findsNothing,
          );
          expect(
            closed(
              find.textContaining(en.meetingsMeetingVotingClosedOn('').trim()),
            ),
            findsNothing,
          );
          await finish(tester, providers);
        },
      );

      testWidgets('shows no resolution for an item that has none', (
        tester,
      ) async {
        final (:providers, app: _) = await _renderDetail(tester);
        await tester.pumpAndSettle();

        expect(
          _within(
            agendaItemTestId('opening'),
            byTestId(resolutionTestId('budget-vote')),
          ),
          findsNothing,
        );
        await finish(tester, providers);
      });
    });

    group('the documents', () {
      testWidgets(
        'shows the title, the confidentiality and the number of pages of each',
        (tester) async {
          final (:providers, app: _) = await _renderDetail(tester);
          await tester.pumpAndSettle();

          Finder report(Finder finder) =>
              _within(documentTestId('report'), finder);
          Finder pack(Finder finder) => _within(documentTestId('pack'), finder);
          expect(report(find.text('Remuneration report')), findsOneWidget);
          expect(
            report(find.text(en.meetingsConfidentialityConfidential)),
            findsOneWidget,
          );
          expect(report(find.text('12 pages')), findsOneWidget);
          expect(
            pack(find.text(en.meetingsConfidentialityInternal)),
            findsOneWidget,
          );
          expect(pack(find.text('1 page')), findsOneWidget);
          await finish(tester, providers);
        },
      );
    });

    group('the participants', () {
      testWidgets('shows the name and the role of each', (tester) async {
        final (:providers, app: _) = await _renderDetail(tester);
        await tester.pumpAndSettle();

        Finder person(String id, Finder finder) =>
            _within(participantTestId(id), finder);
        expect(person('user-2', find.text('Bruno Durand')), findsOneWidget);
        expect(
          person('user-2', find.text(en.meetingsParticipantRoleChair)),
          findsOneWidget,
        );
        expect(
          person('user-4', find.text(en.meetingsParticipantRoleGuest)),
          findsOneWidget,
        );
        expect(
          person('user-1', find.text(en.meetingsParticipantRoleMember)),
          findsOneWidget,
        );
        await finish(tester, providers);
      });
    });

    group('opening a document', () {
      testWidgets(
        'makes each document a button that opens it, and nothing else on the '
        'screen a button',
        (tester) async {
          final app = TestApp(meetingsPageSize: testPageSize);
          app.fakes.meetings.addMeeting(_meeting);
          final (:providers, :opened) = await pumpInRouter(
            tester,
            MeetingDetailScreen(meetingId: _meeting.id),
            app: app,
          );
          await tester.pumpAndSettle();

          expect(find.byType(InkWell), findsNWidgets(2));
          await tester.ensureVisible(byTestId(documentTestId('report')));
          await tester.tap(byTestId(documentTestId('report')));
          await tester.pumpAndSettle();

          expect(opened, ['report']);
          await finish(tester, providers);
        },
      );

      testWidgets(
        'names a document by its title, its confidentiality and its pages, '
        'and says where it leads',
        (tester) async {
          final semantics = tester.ensureSemantics();
          final (:providers, app: _) = await _renderDetail(tester);
          await tester.pumpAndSettle();

          expect(
            tester.getSemantics(byTestId(documentTestId('report'))),
            isSemantics(
              isButton: true,
              label:
                  'Remuneration report, '
                  '${en.meetingsConfidentialityConfidential}, 12 pages',
              hint: en.meetingsMeetingOpenDocumentHint,
            ),
          );
          semantics.dispose();
          await finish(tester, providers);
        },
      );
    });

    group('the states', () {
      testWidgets(
        'says the meeting is not found when the server does not have it, with '
        'no way to retry',
        (tester) async {
          final app = TestApp(meetingsPageSize: testPageSize);
          app.fakes.meetings.removeMeeting(_meeting.id);
          final providers = await pumpScreen(
            tester,
            MeetingDetailScreen(meetingId: _meeting.id),
            app: app,
          );
          await tester.pumpAndSettle();

          expect(
            _within(
              MeetingsTestIds.meetingNotFound,
              find.text(en.coreErrorsNotFound),
            ),
            findsOneWidget,
          );
          expect(byTestId(CoreTestIds.retryButton), findsNothing);
          expect(app.fakes.meetings.getCalls, hasLength(1));
          await finish(tester, providers);
        },
      );

      for (final (name, meetingId) in [
        ('a blank identifier', '   '),
        ('an empty identifier', ''),
      ]) {
        testWidgets(
          'says the meeting is not found for $name, without asking the server',
          (tester) async {
            final (:providers, :app) = await _renderDetailAt(tester, meetingId);

            expect(byTestId(MeetingsTestIds.meetingNotFound), findsOneWidget);
            expect(app.fakes.meetings.getCalls, isEmpty);
            await finish(tester, providers);
          },
        );
      }

      testWidgets(
        'says the meeting is forbidden to the user, with no way to retry, and '
        'drops the saved copy',
        (tester) async {
          final app = TestApp(meetingsPageSize: testPageSize);
          await app.fakes.meetingCache.saveMeeting(aUserId(), _meeting, now);
          app.fakes.meetings.forbid(_meeting.id);
          final (:providers, app: _) = await _renderDetail(tester, given: app);
          await tester.pumpAndSettle();

          expect(
            _within(
              MeetingsTestIds.meetingError,
              find.text(en.coreErrorsForbidden),
            ),
            findsOneWidget,
          );
          expect(
            _within(
              MeetingsTestIds.meetingError,
              byTestId(CoreTestIds.retryButton),
            ),
            findsNothing,
          );
          expect(app.fakes.meetingCache.isEmpty(), isTrue);
          await finish(tester, providers);
        },
      );

      testWidgets(
        'sends the user to the lock screen, without asking the server, when '
        'the app is locked',
        (tester) async {
          final app = TestApp(meetingsPageSize: testPageSize);
          await lockApp(app);
          final (:providers, app: _) = await _renderDetail(tester, given: app);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));

          expect(accessOf(providers), Access.locked);
          expect(
            providers.read(accessControllerProvider).sessionEndedBy,
            'appLocked',
          );
          expect(app.fakes.meetings.getCalls, isEmpty);
          await finish(tester, providers);
        },
      );

      testWidgets(
        'shows an error with a way to retry, and the meeting when the retry '
        'succeeds',
        (tester) async {
          final app = TestApp(meetingsPageSize: testPageSize);
          app.fakes.meetings.failure = unexpected();
          final (:providers, app: _) = await _renderDetail(tester, given: app);
          await tester.pumpAndSettle();

          expect(
            _within(
              MeetingsTestIds.meetingError,
              find.text(en.coreErrorsUnexpected),
            ),
            findsOneWidget,
          );

          app.fakes.meetings.failure = null;
          await tester.tap(
            _within(
              MeetingsTestIds.meetingError,
              byTestId(CoreTestIds.retryButton),
            ),
          );
          await tester.pumpAndSettle();

          expect(byTestId(MeetingsTestIds.meetingDetail), findsOneWidget);
          expect(byTestId(MeetingsTestIds.meetingError), findsNothing);
          await finish(tester, providers);
        },
      );

      testWidgets(
        'keeps the meeting on the screen, with an error, when a refresh fails',
        (tester) async {
          final (:providers, :app) = await _renderDetail(tester);
          await tester.pumpAndSettle();
          app.fakes.meetings.failure = unexpected();

          providers.invalidate(meetingQueryProvider(_meeting.id));
          await tester.pumpAndSettle();

          expect(
            _within(
              CoreTestIds.refreshError,
              find.text(en.coreErrorsUnexpected),
            ),
            findsOneWidget,
          );
          expect(byTestId(MeetingsTestIds.meetingDetail), findsOneWidget);
          await finish(tester, providers);
        },
      );

      testWidgets('shows no banner for a meeting fresh from the server', (
        tester,
      ) async {
        final (:providers, app: _) = await _renderDetail(tester);
        await tester.pumpAndSettle();

        expect(byTestId(CoreTestIds.staleBanner), findsNothing);
        await finish(tester, providers);
      });

      testWidgets(
        'says since when a meeting is a saved copy, when the server cannot be '
        'reached',
        (tester) async {
          final app = TestApp(meetingsPageSize: testPageSize);
          await app.fakes.meetingCache.saveMeeting(aUserId(), _meeting, now);
          app.fakes.auth.session = aSession(expiresAt: at(2 * millisPerDay));
          app.fakes.clock.advance(millisPerDay);
          app.fakes.network.goOffline();
          final (:providers, app: _) = await _renderDetail(tester, given: app);
          await tester.pumpAndSettle();

          expect(
            _within(
              CoreTestIds.staleBanner,
              find.text(en.coreStatesStaleData(format.dateTime(now))),
            ),
            findsOneWidget,
          );
          expect(find.text(_meeting.title), findsOneWidget);
          expect(byTestId(agendaItemTestId('budget')), findsOneWidget);
          await finish(tester, providers);
        },
      );

      testWidgets(
        'reads the meeting again on a pull to refresh, and drops the banner '
        'once the server answers',
        (tester) async {
          final app = TestApp(meetingsPageSize: testPageSize);
          await app.fakes.meetingCache.saveMeeting(aUserId(), _meeting, now);
          app.fakes.network.goOffline();
          final (:providers, app: _) = await _renderDetail(tester, given: app);
          await tester.pumpAndSettle();
          expect(byTestId(CoreTestIds.staleBanner), findsOneWidget);

          app.fakes.network.goOnline();
          await pullToRefresh(
            tester,
            finder: byTestId(MeetingsTestIds.meetingDetail),
          );

          expect(byTestId(CoreTestIds.staleBanner), findsNothing);
          expect(find.text(_meeting.title), findsOneWidget);
          await finish(tester, providers);
        },
      );

      testWidgets('shows the network error of a meeting that was never saved', (
        tester,
      ) async {
        final app = TestApp(meetingsPageSize: testPageSize);
        app.fakes.network.goOffline();
        final (:providers, app: _) = await _renderDetail(tester, given: app);
        await tester.pumpAndSettle();

        expect(
          _within(
            MeetingsTestIds.meetingError,
            find.text(en.coreErrorsNetworkUnavailable),
          ),
          findsOneWidget,
        );
        await finish(tester, providers);
      });
    });

    group('in each language', () {
      for (final locale in AppLocalizations.supportedLocales) {
        testWidgets(
          'shows the sections and the codes in ${locale.languageCode}',
          (tester) async {
            final texts = l10nOf(locale);
            final (:providers, app: _) = await _renderDetail(
              tester,
              locale: locale,
            );
            await tester.pumpAndSettle();

            expect(find.text(texts.meetingsMeetingAgenda), findsOneWidget);
            expect(
              find.text(texts.meetingsParticipantRoleChair),
              findsOneWidget,
            );
            expect(
              find.text(
                texts.meetingsMeetingResolutionYourVote(
                  texts.votesVoteChoiceAgainst,
                ),
              ),
              findsOneWidget,
            );
            await finish(tester, providers);
          },
        );
      }

      testWidgets(
        'translates the meeting into French: sections, roles, statuses, vote '
        'and plurals',
        (tester) async {
          final fr = l10nOf(const Locale('fr'));
          final (:providers, app: _) = await _renderDetail(
            tester,
            locale: const Locale('fr'),
          );
          await tester.pumpAndSettle();

          expect(find.text(fr.meetingsMeetingAgenda), findsOneWidget);
          expect(find.text(fr.meetingsMeetingParticipants), findsOneWidget);
          expect(find.text(fr.meetingsParticipantRoleChair), findsOneWidget);
          expect(find.text(fr.meetingsParticipantRoleGuest), findsOneWidget);
          expect(
            find.text(fr.meetingsConfidentialityConfidential),
            findsOneWidget,
          );
          expect(find.text(fr.meetingsVotingStateOpen), findsOneWidget);
          expect(find.text(fr.meetingsVotingStateClosed), findsOneWidget);
          expect(
            find.text(
              fr.meetingsMeetingResolutionYourVote(fr.votesVoteChoiceAgainst),
            ),
            findsOneWidget,
          );
          expect(find.text(fr.meetingsMeetingPageCount(12)), findsOneWidget);
          expect(find.text(fr.meetingsMeetingPageCount(1)), findsOneWidget);
          expect(find.text(fr.meetingsMeetingResolutionNoVote), findsOneWidget);
          await finish(tester, providers);
        },
      );

      testWidgets('translates a meeting that is not found into French', (
        tester,
      ) async {
        final app = TestApp(meetingsPageSize: testPageSize);
        final providers = await pumpScreen(
          tester,
          MeetingDetailScreen(meetingId: aMeetingId('unknown')),
          app: app,
          locale: const Locale('fr'),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(l10nOf(const Locale('fr')).coreErrorsNotFound),
          findsOneWidget,
        );
        await finish(tester, providers);
      });
    });

    group('where voting stands', () {
      testWidgets(
        'shows the voting as ended, and not as open, once the window has '
        'passed at the instant of the load',
        (tester) async {
          final (:providers, app: _) = await _renderDetail(
            tester,
            given: _appAt(2 * millisPerDay),
          );
          await tester.pumpAndSettle();

          Finder budget(Finder finder) =>
              _within(resolutionTestId('budget-vote'), finder);
          expect(budget(find.text(en.meetingsVotingStateOpen)), findsNothing);
          expect(
            budget(find.text(en.meetingsVotingStateWindowOver)),
            findsOneWidget,
          );
          expect(
            budget(
              find.text(
                en.meetingsMeetingVotingClosedOn(format.dateTime(_closesAt)),
              ),
            ),
            findsOneWidget,
          );
          await finish(tester, providers);
        },
      );

      testWidgets(
        'judges a saved copy at the instant it is shown at, not at the '
        'instant it was saved',
        (tester) async {
          final app = _appAt(2 * millisPerDay);
          await app.fakes.meetingCache.saveMeeting(aUserId(), _meeting, now);
          app.fakes.network.goOffline();
          final (:providers, app: _) = await _renderDetail(tester, given: app);
          await tester.pumpAndSettle();

          expect(byTestId(CoreTestIds.staleBanner), findsOneWidget);
          Finder budget(Finder finder) =>
              _within(resolutionTestId('budget-vote'), finder);
          expect(
            budget(find.text(en.meetingsVotingStateWindowOver)),
            findsOneWidget,
          );
          expect(budget(find.text(en.meetingsVotingStateOpen)), findsNothing);
          await finish(tester, providers);
        },
      );

      testWidgets(
        'keeps the state it had at the load until the meeting is loaded again',
        (tester) async {
          final app = _appAt(millisPerHour);
          final (:providers, app: _) = await _renderDetail(tester, given: app);
          await tester.pumpAndSettle();
          Finder budget(Finder finder) =>
              _within(resolutionTestId('budget-vote'), finder);
          expect(budget(find.text(en.meetingsVotingStateOpen)), findsOneWidget);

          app.fakes.clock.set(at(2 * millisPerDay));
          await tester.pump(const Duration(hours: 1));
          expect(budget(find.text(en.meetingsVotingStateOpen)), findsOneWidget);

          providers.invalidate(meetingQueryProvider(_meeting.id));
          await tester.pumpAndSettle();
          expect(
            budget(find.text(en.meetingsVotingStateWindowOver)),
            findsOneWidget,
          );
          await finish(tester, providers);
        },
      );
    });

    group('for the screen reader and the region', () {
      testWidgets('tells that the meeting is loading, with a name', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        final (:providers, app: _) = await _renderDetail(tester);

        expect(
          find.bySemanticsLabel(en.meetingsMeetingLoading),
          findsOneWidget,
        );
        await tester.pumpAndSettle();
        semantics.dispose();
        await finish(tester, providers);
      });

      testWidgets('announces on iOS that it is refreshing', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        final announced = <Object?>[];
        tester.binding.defaultBinaryMessenger
            .setMockDecodedMessageHandler<dynamic>(
              SystemChannels.accessibility,
              (message) async {
                announced.add(message);
                return null;
              },
            );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger
              .setMockDecodedMessageHandler<dynamic>(
                SystemChannels.accessibility,
                null,
              ),
        );
        final (:providers, app: _) = await _renderDetail(tester);
        await tester.pumpAndSettle();
        announced.clear();

        await pullToRefresh(
          tester,
          finder: byTestId(MeetingsTestIds.meetingDetail),
        );

        debugDefaultTargetPlatformOverride = null;
        expect(announced.toString(), contains(en.coreStatesRefreshing));
        await finish(tester, providers);
      });

      testWidgets(
        'writes the number of pages with the grouping of the locale',
        (tester) async {
          final app = TestApp(meetingsPageSize: testPageSize);
          app.fakes.meetings.addMeeting(
            unwrap(
              createMeeting(
                MeetingInput(
                  summary: _meeting,
                  agenda: const [],
                  documents: [
                    aDocument(
                      id: aDocumentId('big'),
                      title: 'Annual record',
                      pageCount: 4321,
                    ),
                  ],
                  participants: _meeting.participants,
                ),
              ),
            ),
          );
          final providers = await pumpScreen(
            tester,
            MeetingDetailScreen(meetingId: _meeting.id),
            app: app,
          );
          await tester.pumpAndSettle();

          expect(
            _within(documentTestId('big'), find.text('4,321 pages')),
            findsOneWidget,
          );
          await finish(tester, providers);
        },
      );
    });
  });
}
