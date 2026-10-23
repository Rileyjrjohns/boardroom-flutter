import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

/// Tells the screen reader on iOS that something is under way. The other
/// platforms announce the refresh indicator by themselves, so a second
/// announcement there would be said twice.
void announceOnIos(BuildContext context, String message) {
  if (defaultTargetPlatform != TargetPlatform.iOS) {
    return;
  }
  // The announcement is fire and forget.
  // ignore: discarded_futures
  SemanticsService.sendAnnouncement(
    View.of(context),
    message,
    Directionality.of(context),
  );
}
