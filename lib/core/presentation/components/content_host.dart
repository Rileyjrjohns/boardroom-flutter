import 'package:boardroom/core/presentation/components/privacy_cover.dart';
import 'package:boardroom/core/presentation/state/ui_state.dart';
import 'package:boardroom/core/presentation/test_ids.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the content of the app and the privacy cover side by side. The content
/// is hidden from the screen reader while the cover is up, and the cover is
/// modal for it.
///
/// In Flutter a dialog is a route of the navigator that is the [child], so the
/// cover drawn over the navigator covers the dialogs too: what a dialog asks is
/// often confidential (the choice of a vote), and the snapshot of the app
/// switcher includes it. That is what the dialog host of the React Native app
/// does by hand with `Modal` windows.
class ContentHost extends ConsumerWidget {
  /// Creates the host around [child].
  const new({required this.child, super.key});

  /// The content of the app: everything the cover comes up over.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final covered = ref.watch(privacyCoverUpProvider);
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          excluding: covered,
          child: KeyedSubtree(
            key: const Key(CoreTestIds.appContent),
            child: child,
          ),
        ),
        if (covered) const PrivacyCover(),
      ],
    );
  }
}
