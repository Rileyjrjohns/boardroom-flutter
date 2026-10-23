import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_protection/screen_protection_view.dart';
import 'package:screen_protection/src/messages.g.dart';

const Key _childKey = Key('child');
const Widget _child = SizedBox(key: _childKey, width: 10, height: 10);

final TargetPlatformVariant _ios = TargetPlatformVariant.only(
  TargetPlatform.iOS,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final created = <String>[];
  final messenger = TestWidgetsFlutterBinding.instance.defaultBinaryMessenger;

  setUp(() {
    created.clear();
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') {
        final arguments = call.arguments as Map<Object?, Object?>;
        created.add(arguments['viewType']! as String);
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  Future<void> pump(
    WidgetTester tester, {
    required bool secure,
    Stream<SecureLayerFallbackMessage>? fallbacks,
    void Function(String reason)? onFallback,
  }) => tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SecureView(
          secure: secure,
          fallbacks: fallbacks,
          onFallback: onFallback,
          child: _child,
        ),
      ),
    ),
  );

  testWidgets(
    'renders the child as it is on Android: the window flag does the work',
    (tester) async {
      await pump(tester, secure: true);

      expect(find.byKey(_childKey), findsOneWidget);
      expect(find.byType(UiKitView), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('renders the child as it is on the other platforms', (
    tester,
  ) async {
    await pump(tester, secure: true);

    expect(find.byKey(_childKey), findsOneWidget);
    expect(find.byType(UiKitView), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
    'mounts the native secure view next to the child on iOS while secure',
    (tester) async {
      await pump(tester, secure: true, fallbacks: const Stream.empty());
      await tester.pump();

      expect(find.byKey(_childKey), findsOneWidget);
      expect(find.byType(UiKitView), findsOneWidget);
      expect(created, equals([secureViewType]));
    },
    variant: _ios,
  );

  testWidgets('is a plain container on iOS when it is not secure', (
    tester,
  ) async {
    await pump(tester, secure: false);

    expect(find.byKey(_childKey), findsOneWidget);
    expect(find.byType(UiKitView), findsNothing);
  }, variant: _ios);

  testWidgets('mounts and removes the native view as secure changes', (
    tester,
  ) async {
    await pump(tester, secure: false);

    await pump(tester, secure: true, fallbacks: const Stream.empty());
    expect(find.byType(UiKitView), findsOneWidget);

    await pump(tester, secure: false);
    expect(find.byType(UiKitView), findsNothing);
    expect(find.byKey(_childKey), findsOneWidget);
  }, variant: _ios);

  testWidgets('tells the fallback of the native side with its reason', (
    tester,
  ) async {
    final fallbacks = StreamController<SecureLayerFallbackMessage>();
    addTearDown(fallbacks.close);
    final reasons = <String>[];

    await pump(
      tester,
      secure: true,
      fallbacks: fallbacks.stream,
      onFallback: reasons.add,
    );
    fallbacks.add(SecureLayerFallbackMessage(reason: 'no property'));
    await tester.pump();

    expect(reasons, equals(['no property']));
  }, variant: _ios);

  testWidgets('stops listening to the fallback once it is not secure', (
    tester,
  ) async {
    final fallbacks = StreamController<SecureLayerFallbackMessage>.broadcast();
    addTearDown(fallbacks.close);
    final reasons = <String>[];
    await pump(
      tester,
      secure: true,
      fallbacks: fallbacks.stream,
      onFallback: reasons.add,
    );

    await pump(
      tester,
      secure: false,
      fallbacks: fallbacks.stream,
      onFallback: reasons.add,
    );
    fallbacks.add(SecureLayerFallbackMessage(reason: 'late'));
    await tester.pump();

    expect(reasons, isEmpty);
    expect(fallbacks.hasListener, isFalse);
  }, variant: _ios);
}
