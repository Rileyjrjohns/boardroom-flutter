import 'package:boardroom/app/router/route_scaffold.dart';
import 'package:boardroom/core/presentation/navigation/routes.dart';
import 'package:boardroom/core/presentation/providers.dart';
import 'package:boardroom/features/auth/presentation/screens/lock_screen.dart';
import 'package:boardroom/features/auth/presentation/screens/sign_in_screen.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:boardroom/features/documents/presentation/providers.dart';
import 'package:boardroom/features/documents/presentation/screen_protection_demo_screen.dart';
import 'package:boardroom/features/documents/presentation/screens/document_screen.dart';
import 'package:boardroom/features/meetings/presentation/screens/meeting_detail_screen.dart';
import 'package:boardroom/features/meetings/presentation/screens/meetings_list_screen.dart';
import 'package:boardroom/features/votes/presentation/screens/pending_votes_screen.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The longest link the app takes, in characters. The links to its screens are
/// a few dozen long; a browser or a share sheet will hand over far more, and
/// nothing the app does needs it. A longer link is dropped without being read.
const int maxLinkLength = 2048;

/// Where the user lands for an access: the one screen that exists for it (the
/// sign-in or the lock screen), or the home of the open app.
String homeOf(Access access) => switch (access) {
  Access.signedOut => AppRoutes.signIn.path,
  Access.locked => AppRoutes.lock.path,
  Access.starting || Access.unlocked => AppRoutes.meetings.path,
};

/// Whether the percent-encoding of [path] can be decoded. A path with a `%`
/// that cannot be decoded is a crafted link: it is dropped instead of reaching
/// a screen that would parse its parameter.
bool _isDecodable(String path) {
  try {
    Uri.decodeComponent(path);
    return true;
  } on Object {
    return false;
  }
}

const Set<String> _openAppPaths = {'/', '/pending-votes'};
const List<String> _openAppPrefixes = ['/meetings/', '/documents/'];

/// Whether [path] is a route that exists for [access]: a protected stack. The
/// sign-in route exists for a signed-out user only, the lock route for a locked
/// app only, and the other four for an open app only. A route whose guard is
/// false is not in the stack at all, which gives the two guarantees of the
/// specification: no deep link reaches a protected screen, and the back stack
/// never returns to one.
bool existsFor(Access access, String path) {
  switch (access) {
    case Access.starting:
      return true;
    case Access.signedOut:
      return path == AppRoutes.signIn.path;
    case Access.locked:
      return path == AppRoutes.lock.path;
    case Access.unlocked:
      if (_openAppPaths.contains(path)) {
        return true;
      }
      for (final prefix in _openAppPrefixes) {
        final rest = path.startsWith(prefix)
            ? path.substring(prefix.length)
            : '';
        if (rest.isNotEmpty && !rest.contains('/')) {
          return true;
        }
      }
      return false;
  }
}

/// The redirect of the router, as a pure function of where the user stands and
/// where the link points (`AppNavigator` and `redirectSystemPath` of the React
/// Native app):
///
/// - a link that is too long or whose percent-encoding is malformed is dropped:
///   the user lands on the home of their access;
/// - a route that does not exist for the access sends the user to the home of
///   that access, and the stack starts anew there. A link to a meeting, opened
///   while the user is signed out or the app is locked, finds no such route and
///   the stack starts on the screen that exists. Once the user is allowed in
///   they land on the list: the link is not remembered, because remembering
///   where a link wanted to go would send whoever signs in next to a meeting
///   they may not have;
/// - the demo screen of the screen protection exists in the dev configuration
///   only, for every access;
/// - nothing is decided while the access is `starting`: the shell shows the
///   loading state and no route is mounted.
///
/// Returns null to stay where the link points.
String? redirectOf({
  required Access access,
  required Uri location,
  required bool demoRoutes,
}) {
  if (access == Access.starting) {
    return null;
  }
  final raw = location.toString();
  if (raw.length > maxLinkLength || !_isDecodable(location.path)) {
    return homeOf(access);
  }
  if (demoRoutes && location.path == AppRoutes.screenProtectionDemo.path) {
    return null;
  }
  return existsFor(access, location.path) ? null : homeOf(access);
}

/// Builds the router of the app. [readAccess] is where the user stands, and
/// [refresh] tells the router to run the redirect again when it changes (the
/// `refreshListenable` of go_router), which also removes the screens of a
/// protected route when its guard turns false, history included.
GoRouter createAppRouter({
  required Access Function() readAccess,
  required bool Function() readDemoRoutes,
  required Listenable refresh,
  String? initialLocation,
}) => GoRouter(
  initialLocation: initialLocation ?? AppRoutes.meetings.path,
  refreshListenable: refresh,
  redirect: (context, state) => redirectOf(
    access: readAccess(),
    location: state.uri,
    demoRoutes: readDemoRoutes(),
  ),
  routes: [
    GoRoute(
      path: AppRoutes.signIn.path,
      name: AppRoutes.signIn.name,
      builder: (context, state) => RouteScaffold(
        title: AppLocalizations.of(context).coreNavigationSignIn,
        child: const SignInScreen(),
      ),
    ),
    GoRoute(
      path: AppRoutes.lock.path,
      name: AppRoutes.lock.name,
      builder: (context, state) => RouteScaffold(
        title: AppLocalizations.of(context).coreNavigationLocked,
        child: const LockScreen(),
      ),
    ),
    GoRoute(
      path: AppRoutes.meetings.path,
      name: AppRoutes.meetings.name,
      builder: (context, state) => RouteScaffold(
        title: AppLocalizations.of(context).coreNavigationMeetings,
        showHeaderActions: true,
        child: const MeetingsListScreen(),
      ),
    ),
    GoRoute(
      path: AppRoutes.meetingDetail.path,
      name: AppRoutes.meetingDetail.name,
      builder: (context, state) => RouteScaffold(
        title: AppLocalizations.of(context).coreNavigationMeeting,
        child: MeetingDetailScreen(
          meetingId: state.pathParameters[RouteParams.meetingId] ?? '',
        ),
      ),
    ),
    GoRoute(
      path: AppRoutes.document.path,
      name: AppRoutes.document.name,
      builder: (context, state) => RouteScaffold(
        title: AppLocalizations.of(context).coreNavigationDocument,
        child: DocumentScreen(
          documentId: state.pathParameters[RouteParams.documentId] ?? '',
        ),
      ),
    ),
    GoRoute(
      path: AppRoutes.pendingVotes.path,
      name: AppRoutes.pendingVotes.name,
      builder: (context, state) => RouteScaffold(
        title: AppLocalizations.of(context).coreNavigationPendingVotes,
        child: const PendingVotesScreen(),
      ),
    ),
    // Development only (the redirect lets it through in the dev configuration):
    // the screen of step 4 that tries the screen protection on a device.
    GoRoute(
      path: AppRoutes.screenProtectionDemo.path,
      name: AppRoutes.screenProtectionDemo.name,
      builder: (context, state) => Consumer(
        builder: (context, ref, _) => ScreenProtectionDemoScreen(
          screenProtection: ref.watch(screenProtectionProvider),
        ),
      ),
    ),
  ],
);

/// The router of the app, tied to the access of the user: it runs its redirect
/// again whenever the access changes.
final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(accessProvider, (_, _) => refresh.value++);
  final router = createAppRouter(
    readAccess: () => ref.read(accessProvider),
    readDemoRoutes: () => ref.read(demoControlsProvider) != null,
    refresh: refresh,
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
