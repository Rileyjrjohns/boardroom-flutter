import 'package:boardroom/app/shell/app_lifecycle.dart';
import 'package:boardroom/app/shell/connectivity_observer.dart';
import 'package:boardroom/core/presentation/components/content_host.dart';
import 'package:boardroom/core/presentation/components/loading_state.dart';
import 'package:boardroom/core/presentation/test_ids.dart';
import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:boardroom/features/auth/presentation/components/restore_failure.dart';
import 'package:boardroom/features/auth/presentation/session/restore_session_controller.dart';
import 'package:boardroom/features/auth/presentation/session/session_ended.dart';
import 'package:boardroom/features/auth/presentation/session/session_watch.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:boardroom/features/votes/presentation/state/vote_sync.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Everything that follows the session and the life of the app, mounted once
/// above the navigator (the `SessionController` of the React Native app):
///
/// - at the start, `RestoreSession` is asked who was signed in, and until it
///   answers the user sees the loading state (and its failure, with a way to
///   ask again);
/// - the connection of the device is followed, for the banner and for the
///   synchronisation;
/// - the app going to the background and coming back is followed: the privacy
///   cover, and the lock and the session evaluated before anything is shown;
/// - an app that stays open is asked, on a timer, whether its session is still
///   good;
/// - while the privacy cover is over the content, the content is out of reach
///   of the screen reader (`ContentHost`);
/// - the votes that wait are sent when the connection comes back, when the app
///   returns to the foreground and when the user signs in or unlocks;
/// - a session that ended in use (not by the user's own sign-out) is also ended
///   on the device, so that a restart does not find a session the server has
///   refused.
///
/// The screens the user can reach follow the access, in the router.
class SessionController extends ConsumerStatefulWidget {
  /// Creates the controller around [child], the navigator.
  const new({required this.child, super.key});

  /// The navigator: what the user sees once the session is known.
  final Widget child;

  @override
  ConsumerState<SessionController> createState() => _SessionControllerState();
}

class _SessionControllerState extends ConsumerState<SessionController> {
  late final AppLifecycleListener _listener;

  @override
  void initState() {
    super.initState();
    final handler = ref.read(appLifecycleHandlerProvider);
    _listener = AppLifecycleListener(onStateChange: handler.onChanged);
    // After the first frame: a provider cannot be modified while the tree is
    // being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      handler.start(WidgetsBinding.instance.lifecycleState);
      // After a sign-in or an unlock, what waits is sent. A start that is
      // already open (a test, a session opened by the configuration) does the
      // same.
      ref.listenManual(accessProvider, fireImmediately: true, (_, access) {
        if (access == Access.unlocked) {
          ref.read(requestVoteSyncProvider)();
        }
      });
    });
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref
      ..watch(connectivityObserverProvider)
      ..watch(sessionWatchProvider)
      ..watch(signOutEndedSessionProvider);
    final access = ref.watch(accessProvider);
    final restoreFailure = ref.watch(restoreSessionControllerProvider);
    final l10n = AppLocalizations.of(context);

    final Widget content;
    if (access == Access.starting) {
      content = Material(
        color: AppColors.background,
        child: restoreFailure == null
            ? LoadingState(
                key: const Key(CoreTestIds.startupLoading),
                label: l10n.coreStartupLoading,
              )
            : RestoreFailure(
                error: restoreFailure,
                onRetry: () =>
                    ref.read(restoreSessionControllerProvider.notifier).retry(),
              ),
      );
    } else {
      content = widget.child;
    }
    return ContentHost(child: content);
  }
}
