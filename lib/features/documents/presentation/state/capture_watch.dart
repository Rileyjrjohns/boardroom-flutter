import 'dart:async';

import 'package:boardroom/core/application/ports/types/unsubscribe.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/features/documents/application/ports/screen_protection.dart';
import 'package:boardroom/features/documents/application/use_cases/observe_screen_capture.dart';
import 'package:flutter/foundation.dart';

/// A capture of the screen the user has to be told about.
@immutable
final class CaptureNoticeValue {
  /// Creates the notice number [sequence] for a capture of [kind].
  const new({required this.kind, required this.sequence});

  /// What was seen: a screenshot or the start of a recording.
  final ScreenCaptureKind kind;

  /// Counts the notices of the screen. Two screenshots in a row say the same
  /// words, which a screen reader does not say twice: the number is what makes
  /// the second one a new notice.
  final int sequence;
}

/// The watch for captures of one screen, outside the widget tree: subscribes
/// through [ObserveScreenCapture] when it is started, unsubscribes when it is
/// stopped, and holds the last capture worth telling in [notice].
/// [ObserveScreenCapture] can take a moment to answer, and a watch that was
/// stopped before it did stops the subscription as soon as it exists.
class CaptureWatch {
  /// Creates the watch of [documentId].
  new({
    required ObserveScreenCapture observeScreenCapture,
    required this.documentId,
  }) : _observe = observeScreenCapture;

  /// The document on the screen.
  final DocumentId documentId;

  final ObserveScreenCapture _observe;

  /// The last capture worth telling, or nothing.
  final ValueNotifier<CaptureNoticeValue?> notice = ValueNotifier(null);

  int _sequence = 0;
  void Function()? _stopWatching;

  /// Hides the notice.
  void dismiss() => notice.value = null;

  /// Starts watching. Does nothing if it is already started.
  void start() {
    if (_stopWatching != null) {
      return;
    }
    var here = true;
    Unsubscribe? stop;

    _stopWatching = () {
      here = false;
      stop?.call();
      stop = null;
    };

    unawaited(() async {
      final subscribed = await _observe.execute(
        documentId: documentId,
        onCapture: (event) {
          // The end of a recording says nothing new.
          if (!here || event.kind == ScreenCaptureKind.recordingStopped) {
            return;
          }
          _sequence += 1;
          notice.value = CaptureNoticeValue(
            kind: event.kind,
            sequence: _sequence,
          );
        },
      );
      // Without a session there is nothing to watch for, and the screen is on
      // its way out.
      if (subscribed case Ok(:final value)) {
        if (here) {
          stop = value;
        } else {
          value();
        }
      }
    }());
  }

  /// Stops watching and hides the notice.
  void stop() {
    _stopWatching?.call();
    _stopWatching = null;
    notice.value = null;
  }

  /// Stops watching for good, when the screen goes.
  void dispose() {
    _stopWatching?.call();
    _stopWatching = null;
    notice.dispose();
  }
}
