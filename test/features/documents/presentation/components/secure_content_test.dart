import 'package:boardroom/features/documents/presentation/secure_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_protection/screen_protection_view.dart';

// The component that mounts the secure view of the plugin, the one file of the
// presentation that imports it. On the platform of the tests the view renders
// its child in a plain container and keeps the `secure` flag: what is checked
// is that the child is rendered, whether or not it is secure, and that the flag
// reaches the view. What a capture shows can only be seen on a device.

const _child = 'a page of a document';

Widget _host({required bool secure}) => MaterialApp(
  home: SecureContent(secure: secure, child: const Text(_child)),
);

void main() {
  group('SecureContent', () {
    for (final secure in [true, false]) {
      testWidgets('renders its children, with secure=$secure', (tester) async {
        await tester.pumpWidget(_host(secure: secure));

        expect(find.text(_child), findsOneWidget);
      });

      testWidgets('tells the view whether the content is secure: $secure', (
        tester,
      ) async {
        await tester.pumpWidget(_host(secure: secure));

        expect(
          tester.widget<SecureView>(find.byType(SecureView)).secure,
          secure,
        );
      });
    }

    testWidgets('follows the flag when it changes', (tester) async {
      await tester.pumpWidget(_host(secure: false));
      expect(
        tester.widget<SecureView>(find.byType(SecureView)).secure,
        isFalse,
      );

      await tester.pumpWidget(_host(secure: true));

      expect(tester.widget<SecureView>(find.byType(SecureView)).secure, isTrue);
      expect(find.text(_child), findsOneWidget);
    });
  });
}
