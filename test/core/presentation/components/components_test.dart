import 'package:boardroom/core/application/ports/connectivity.dart';
import 'package:boardroom/core/presentation/components/app_button.dart';
import 'package:boardroom/core/presentation/components/app_dialog.dart';
import 'package:boardroom/core/presentation/components/app_text_field.dart';
import 'package:boardroom/core/presentation/components/badge.dart';
import 'package:boardroom/core/presentation/components/content_host.dart';
import 'package:boardroom/core/presentation/components/error_views.dart';
import 'package:boardroom/core/presentation/components/loading_state.dart';
import 'package:boardroom/core/presentation/components/message.dart';
import 'package:boardroom/core/presentation/components/status_banner.dart';
import 'package:boardroom/core/presentation/notices/app_notices.dart';
import 'package:boardroom/core/presentation/state/ui_state.dart';
import 'package:boardroom/core/presentation/test_ids.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders/builders.dart';
import '../../../support/presentation/test_app.dart';

final class _Notices implements AppNotices {
  new({required this.localDataReset});

  @override
  bool localDataReset;

  int acknowledged = 0;

  @override
  Future<void> acknowledgeLocalDataReset() async => acknowledged++;
}

void main() {
  final en = l10nOf();

  group('ErrorState and InlineError', () {
    for (final inline in [false, true]) {
      final name = inline ? 'InlineError' : 'ErrorState';
      Widget build(String code, VoidCallback? onRetry) => inline
          ? InlineError(code: code, onRetry: onRetry)
          : ErrorState(code: code, onRetry: onRetry);

      testWidgets('$name tells a retryable code with a retry button', (
        tester,
      ) async {
        var retried = 0;
        await pumpScreen(tester, build('networkUnavailable', () => retried++));

        expect(find.text(en.coreErrorsNetworkUnavailable), findsOneWidget);
        await tester.tap(byTestId(CoreTestIds.retryButton));
        expect(retried, 1);
      });

      testWidgets('$name tells a final code without a retry button', (
        tester,
      ) async {
        await pumpScreen(tester, build('forbidden', () {}));

        expect(find.text(en.coreErrorsForbidden), findsOneWidget);
        expect(byTestId(CoreTestIds.retryButton), findsNothing);
      });

      testWidgets('$name has no button without a callback, and reads an '
          'unknown code as unexpected', (tester) async {
        await pumpScreen(tester, build('somethingNew', null));

        expect(find.text(en.coreErrorsUnexpected), findsOneWidget);
        expect(byTestId(CoreTestIds.retryButton), findsNothing);
      });
    }
  });

  group('StatusBanner', () {
    testWidgets('shows nothing when there is nothing to say', (tester) async {
      await pumpScreen(tester, const StatusBanner());

      expect(byTestId(CoreTestIds.statusBanner), findsNothing);
    });

    testWidgets('tells the device is offline, apart from a saved copy', (
      tester,
    ) async {
      final providers = await pumpScreen(tester, StatusBanner(staleSince: now));
      expect(byTestId(CoreTestIds.staleBanner), findsOneWidget);
      expect(byTestId(CoreTestIds.offlineBanner), findsNothing);

      providers
          .read(connectivityStateProvider.notifier)
          .set(ConnectivityStatus.offline);
      await tester.pump();

      expect(byTestId(CoreTestIds.offlineBanner), findsOneWidget);
      expect(byTestId(CoreTestIds.staleBanner), findsOneWidget);
    });

    testWidgets('dates the saved copy in the language of the screen', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        StatusBanner(staleSince: now),
        locale: const Locale('fr'),
      );

      final text = tester.widget<Text>(
        find.descendant(
          of: byTestId(CoreTestIds.staleBanner),
          matching: find.byType(Text),
        ),
      );
      expect(text.data, contains('2030'));
      expect(text.data, startsWith('Affichage'));
    });

    testWidgets('tells the local data was reset until it is dismissed', (
      tester,
    ) async {
      final notices = _Notices(localDataReset: true);
      await pumpScreen(
        tester,
        const StatusBanner(),
        app: TestApp(notices: notices),
      );

      expect(byTestId(CoreTestIds.localDataResetNotice), findsOneWidget);
      await tester.tap(byTestId(CoreTestIds.localDataResetDismiss));
      await tester.pump();

      expect(byTestId(CoreTestIds.statusBanner), findsNothing);
      expect(notices.acknowledged, 1);
    });

    testWidgets('shows what a feature plugs into it', (tester) async {
      final notices = BannerNotices(
        hasNotices: Provider<bool>((ref) => true),
        builder: (context) => const Text('plugged'),
      );
      await pumpScreen(
        tester,
        const StatusBanner(),
        extra: [bannerNoticesProvider.overrideWithValue(notices)],
      );

      expect(find.text('plugged'), findsOneWidget);
      expect(byTestId(CoreTestIds.statusBanner), findsOneWidget);
    });

    testWidgets('the connection banner tells only that the device is offline', (
      tester,
    ) async {
      final providers = await pumpScreen(tester, const ConnectionBanner());
      expect(byTestId(CoreTestIds.statusBanner), findsNothing);

      providers
          .read(connectivityStateProvider.notifier)
          .set(ConnectivityStatus.offline);
      await tester.pump();

      expect(byTestId(CoreTestIds.offlineBanner), findsOneWidget);
    });
  });

  group('ContentHost and PrivacyCover', () {
    testWidgets('covers the content with the name of the app and nothing else '
        'while the cover is up', (tester) async {
      final providers = await pumpScreen(
        tester,
        const ContentHost(child: Text('confidential')),
      );
      expect(byTestId(CoreTestIds.privacyCover), findsNothing);
      expect(byTestId(CoreTestIds.appContent), findsOneWidget);

      providers.read(privacyCoverUpProvider.notifier).set(true);
      await tester.pump();

      expect(byTestId(CoreTestIds.privacyCover), findsOneWidget);
      expect(find.text(en.coreAppName), findsOneWidget);
      final hidden = tester.widget<ExcludeSemantics>(
        find.ancestor(
          of: byTestId(CoreTestIds.appContent),
          matching: find.byType(ExcludeSemantics),
        ),
      );
      expect(hidden.excluding, isTrue);
    });
  });

  group('AppDialog', () {
    testWidgets(
      'shows its title, body and actions, and refuses a tap outside',
      (tester) async {
        await pumpScreen(
          tester,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppDialog<void>(
                context,
                builder: (_) => AppDialog(
                  title: 'Title',
                  content: const Text('Body'),
                  actions: [AppButton(title: 'Close', onPressed: () {})],
                ),
              ),
              child: const Text('open'),
            ),
          ),
        );

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.text('Title'), findsOneWidget);
        expect(find.text('Body'), findsOneWidget);

        await tester.tapAt(const Offset(2, 2));
        await tester.pumpAndSettle();
        expect(find.text('Title'), findsOneWidget);
      },
    );

    testWidgets('asks to be dismissed by the back gesture, unless it refuses', (
      tester,
    ) async {
      var dismissed = 0;
      await pumpScreen(
        tester,
        AppDialog(
          title: 'Title',
          content: const SizedBox.shrink(),
          actions: const [],
          onDismiss: () => dismissed++,
        ),
      );

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(dismissed, 1);
    });
  });

  group('AppButton', () {
    testWidgets('is busy and cannot be pressed', (tester) async {
      var pressed = 0;
      await pumpScreen(
        tester,
        AppButton(title: 'Go', busy: true, onPressed: () => pressed++),
      );

      await tester.tap(find.text('Go'));

      expect(pressed, 0);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('draws the three variants and presses', (tester) async {
      var pressed = 0;
      await pumpScreen(
        tester,
        Column(
          children: [
            for (final variant in AppButtonVariant.values)
              AppButton(
                title: variant.name,
                variant: variant,
                hint: 'hint',
                onPressed: () => pressed++,
              ),
          ],
        ),
      );

      for (final variant in AppButtonVariant.values) {
        await tester.tap(find.text(variant.name));
      }

      expect(pressed, 3);
    });
  });

  group('small components', () {
    testWidgets('AppTextField shows its label and error, and passes edits', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      String? changed;
      await pumpScreen(
        tester,
        AppTextField(
          key: const Key('field'),
          errorKey: const Key('field-error'),
          label: 'Name',
          controller: controller,
          error: 'Wrong',
          onChanged: (text) => changed = text,
        ),
      );

      await tester.enterText(find.byKey(const Key('field')), 'abc');

      expect(find.text('Name'), findsOneWidget);
      expect(find.byKey(const Key('field-error')), findsOneWidget);
      expect(changed, 'abc');
    });

    testWidgets('AppBadge, Message and LoadingState draw their text', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const Column(
          children: [
            AppBadge(label: 'Confidential', tone: BadgeTone.confidential),
            AppBadge(label: 'Open', tone: BadgeTone.positive),
            AppBadge(label: 'Neutral'),
            Message(message: 'Nothing here', centered: true),
            SizedBox(height: 100, child: LoadingState(label: 'Loading')),
          ],
        ),
      );

      expect(find.text('Confidential'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Nothing here'), findsOneWidget);
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    });
  });
}
