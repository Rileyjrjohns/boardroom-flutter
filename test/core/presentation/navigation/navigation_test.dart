import 'package:boardroom/core/presentation/navigation/navigate.dart';
import 'package:boardroom/core/presentation/navigation/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  group('AppRoute', () {
    test('fills the parameters of the path, percent-encoded', () {
      expect(
        AppRoutes.meetingDetail.location({RouteParams.meetingId: 'm 1/2'}),
        '/meetings/m%201%2F2',
      );
      expect(AppRoutes.pendingVotes.location(), '/pending-votes');
    });

    test('refuses a missing parameter', () {
      expect(AppRoutes.document.location, throwsArgumentError);
    });

    test('the specified routes are the six of the specification, with their '
        'parameters', () {
      expect(AppRoutes.specified.map((route) => route.path), [
        '/',
        '/sign-in',
        '/lock',
        '/pending-votes',
        '/meetings/:meetingId',
        '/documents/:documentId',
      ]);
      expect({
        for (final route in AppRoutes.specified) route.name,
      }, hasLength(6));
    });
  });

  group('pushOnce', () {
    late List<String> shown;

    Future<void> pump(WidgetTester tester) async {
      shown = [];
      GoRoute route(AppRoute route, Widget Function(GoRouterState) page) =>
          GoRoute(
            path: route.path,
            name: route.name,
            builder: (context, state) => page(state),
          );
      final router = GoRouter(
        routes: [
          route(
            AppRoutes.meetings,
            (_) => Builder(
              builder: (context) => Column(
                children: [
                  TextButton(
                    onPressed: () => openMeeting(context, 'm1'),
                    child: const Text('open meeting'),
                  ),
                  TextButton(
                    onPressed: () => openPendingVotes(context),
                    child: const Text('open votes'),
                  ),
                ],
              ),
            ),
          ),
          route(
            AppRoutes.meetingDetail,
            (state) => Builder(
              builder: (context) {
                shown.add(state.pathParameters[RouteParams.meetingId]!);
                return TextButton(
                  onPressed: () {
                    openMeeting(context, 'm1');
                    openDocument(context, 'd1');
                  },
                  child: const Text('detail'),
                );
              },
            ),
          ),
          route(AppRoutes.document, (_) => const Text('document')),
          route(AppRoutes.pendingVotes, (_) => const Text('votes')),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    }

    testWidgets('pushes a route, with its parameter', (tester) async {
      await pump(tester);

      await tester.tap(find.text('open meeting'));
      await tester.pumpAndSettle();

      expect(find.text('detail'), findsOneWidget);
      expect(shown, ['m1']);
    });

    testWidgets('does not stack the screen that is already on top', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('open meeting'));
      await tester.pumpAndSettle();

      // openMeeting for the open meeting does nothing; openDocument pushes.
      await tester.tap(find.text('detail'));
      await tester.pumpAndSettle();
      expect(find.text('document'), findsOneWidget);

      final context = tester.element(find.text('document'));
      GoRouter.of(context).pop();
      await tester.pumpAndSettle();
      expect(find.text('detail'), findsOneWidget);
      GoRouter.of(tester.element(find.text('detail'))).pop();
      await tester.pumpAndSettle();
      expect(find.text('open meeting'), findsOneWidget);
    });

    testWidgets('opens the pending votes', (tester) async {
      await pump(tester);

      await tester.tap(find.text('open votes'));
      await tester.pumpAndSettle();

      expect(find.text('votes'), findsOneWidget);
    });
  });
}
