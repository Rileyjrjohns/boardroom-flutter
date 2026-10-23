import 'dart:async';

import 'package:boardroom/core/presentation/navigation/routes.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Pushes [route] unless the screen on top of the stack already shows the same
/// location. The same meeting (or document) is never stacked twice: a second
/// tap on a row before its screen has come up, or a link opened twice, goes to
/// the screen that is open (docs/spec/screens.md "Guards and the diagram").
void pushOnce(
  BuildContext context,
  AppRoute route, [
  Map<String, String> parameters = const {},
]) {
  final router = GoRouter.of(context);
  final target = route.location(parameters);
  // The location of the screen on top, an imperative push included.
  final current = router.routerDelegate.currentConfiguration.last;
  if (current.matchedLocation == target) {
    return;
  }
  unawaited(router.push(target));
}

/// Opens the meeting with the id [meetingId] (a tap on a row of the list, the
/// "open meeting" button of a pending vote).
void openMeeting(BuildContext context, String meetingId) => pushOnce(
  context,
  AppRoutes.meetingDetail,
  {RouteParams.meetingId: meetingId},
);

/// Opens the document with the id [documentId] (a tap on a document row).
void openDocument(BuildContext context, String documentId) =>
    pushOnce(context, AppRoutes.document, {RouteParams.documentId: documentId});

/// Opens the pending votes (the header of the list).
void openPendingVotes(BuildContext context) =>
    pushOnce(context, AppRoutes.pendingVotes);
