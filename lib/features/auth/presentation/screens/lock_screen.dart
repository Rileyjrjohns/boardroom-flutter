import 'package:boardroom/features/auth/presentation/test_ids.dart';
import 'package:flutter/widgets.dart';

/// The lock screen (docs/spec/screens.md "Lock").
///
/// A placeholder until the auth feature agent writes the screen: the router
/// mounts this class with this constructor, so the file is replaced in place.
/// Port `LockScreen.tsx` of the React Native app with `UnlockAction`,
/// `SignOutDialog`, `SessionNotice`, `ConnectionBanner` and
/// `DemoOfflineSwitch`.
class LockScreen extends StatelessWidget {
  /// Creates the screen.
  const new({super.key});

  @override
  Widget build(BuildContext context) =>
      const SizedBox.expand(key: Key(AuthTestIds.lockScreen));
}
