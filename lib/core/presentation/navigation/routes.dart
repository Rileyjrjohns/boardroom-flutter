// The routes of the app, written once, in pure Dart so that the conformance
// test of the specification can read them. The paths are the ones of
// docs/spec/screens.md (the expo-router paths of the React Native app), and a
// link means the same on both apps.

/// A route of the app: its path pattern, its name in the router and the
/// parameters of its path.
class AppRoute {
  /// Creates a route.
  const new({
    required this.path,
    required this.name,
    this.parameters = const [],
  });

  /// The path pattern, with `:name` for a dynamic segment.
  final String path;

  /// The name the router knows the route by (`context.goNamed(name)`).
  final String name;

  /// The dynamic segments of the path.
  final List<String> parameters;

  /// The path with the parameters filled in (each one percent-encoded).
  String location([Map<String, String> values = const {}]) {
    var result = path;
    for (final parameter in parameters) {
      final value = values[parameter];
      if (value == null) {
        throw ArgumentError.value(values, 'values', 'missing $parameter');
      }
      result = result.replaceFirst(':$parameter', Uri.encodeComponent(value));
    }
    return result;
  }
}

/// The names of the dynamic segments.
abstract final class RouteParams {
  /// The id of a meeting.
  static const String meetingId = 'meetingId';

  /// The id of a document.
  static const String documentId = 'documentId';
}

/// The routes of the specification, plus the development-only ones.
abstract final class AppRoutes {
  /// The meetings list, the home of the open app.
  static const AppRoute meetings = AppRoute(path: '/', name: 'meetings');

  /// The detail of a meeting.
  static const AppRoute meetingDetail = AppRoute(
    path: '/meetings/:${RouteParams.meetingId}',
    name: 'meetingDetail',
    parameters: [RouteParams.meetingId],
  );

  /// A document, in the viewer.
  static const AppRoute document = AppRoute(
    path: '/documents/:${RouteParams.documentId}',
    name: 'document',
    parameters: [RouteParams.documentId],
  );

  /// The votes waiting to be sent and the rejected ones.
  static const AppRoute pendingVotes = AppRoute(
    path: '/pending-votes',
    name: 'pendingVotes',
  );

  /// The sign-in form.
  static const AppRoute signIn = AppRoute(path: '/sign-in', name: 'signIn');

  /// The lock screen.
  static const AppRoute lock = AppRoute(path: '/lock', name: 'lock');

  /// The six routes of the specification (docs/spec/screens.md "Routes").
  static const List<AppRoute> specified = [
    meetings,
    signIn,
    lock,
    pendingVotes,
    meetingDetail,
    document,
  ];

  /// Development only, not in the specification: the screen of step 4 that
  /// tries the screen protection on a device. Reachable in the dev
  /// configuration only, whatever the access.
  static const AppRoute screenProtectionDemo = AppRoute(
    path: '/screen-protection-demo',
    name: 'screenProtectionDemo',
  );
}
