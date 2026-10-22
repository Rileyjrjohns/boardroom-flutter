import 'dart:async';

import 'package:boardroom/application/ports/monitoring.dart';
import 'package:boardroom/application/ports/screen_protection.dart';
import 'package:boardroom/application/ports/types/unsubscribe.dart';
import 'package:boardroom/application/shared/require_session.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/ids.dart';

/// What [ObserveScreenCapture] needs, on top of what the session guard needs.
abstract interface class ObserveScreenCaptureDeps
    implements RequireSessionDeps {
  /// The platform switch, which reports the captures.
  ScreenProtection get screenProtection;
}

/// Watches for screenshots and screen recordings while a document is shown.
/// Requires a valid session to start. Each event is given to `onCapture` at
/// once (the screen shows a warning, say), then logged with the id of the
/// document and the id of the user who is signed in when the event happens,
/// checked again at that moment: the subscription can outlive a sign-out and a
/// sign-in, and the capture must not be attributed to the user who started
/// watching. When nobody is signed in, or the session is not usable, the event
/// is logged without a user. Identifiers only, no name nor email. Succeeds with
/// the function that stops watching.
final class ObserveScreenCapture {
  /// Creates the use case over [_deps].
  const new(this._deps);

  final ObserveScreenCaptureDeps _deps;

  /// Starts watching while [documentId], the document on the screen, is
  /// shown, calling [onCapture] for each event.
  Future<Result<Unsubscribe, SessionRequiredError>> execute({
    required DocumentId documentId,
    required void Function(ScreenCaptureEvent event) onCapture,
  }) async {
    switch (await requireSession(_deps)) {
      case Err(:final error):
        return err(error);
      case Ok():
        return ok(
          _deps.screenProtection.subscribe((event) {
            onCapture(event);
            unawaited(_log(documentId, event));
          }),
        );
    }
  }

  Future<void> _log(DocumentId documentId, ScreenCaptureEvent event) async {
    final session = await requireSession(_deps);
    final attributes = <LogAttribute, Object>{
      LogAttribute.captureKind: event.kind.value,
      LogAttribute.documentId: documentId,
      if (session case Ok(:final value)) LogAttribute.userId: value.user.id,
    };
    _deps.monitoring.log(
      LogLevel.warn,
      MonitoringEvent.screenCaptureDetected,
      attributes,
    );
  }
}
