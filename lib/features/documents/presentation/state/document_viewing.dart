import 'dart:async';

import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/features/documents/application/use_cases/close_document.dart';
import 'package:boardroom/features/documents/application/use_cases/open_document.dart';
import 'package:flutter/foundation.dart';

/// What the screen of a document shows while a document is being viewed.
sealed class DocumentViewState {
  const new();
}

/// The document is being opened: fetched, or read from the copy saved on the
/// device.
final class DocumentLoading extends DocumentViewState {
  /// Creates the state.
  const new();
}

/// Opened: the screen is protected if the document needs it, and the content
/// can be shown.
final class DocumentReady extends DocumentViewState {
  /// Creates the state of the document [opened].
  const new(this.opened);

  /// What the viewer needs to show the document.
  final OpenedDocument opened;
}

/// Could not be opened.
final class DocumentFailed extends DocumentViewState {
  /// Creates the state of an open that failed with [code].
  const new(this.code);

  /// Why the document could not be opened.
  final String code;
}

/// One viewing of a document, outside the widget tree: opens it with
/// [OpenDocument] when it is started and releases it with [CloseDocument] when
/// it is stopped, exactly once for each time it was opened, and holds what the
/// screen shows meanwhile in [state].
///
/// It is a lifecycle and not a query, on purpose. Opening a document does
/// something: it turns the screen protection on, counts a view of the document
/// and logs the access, so running it again (a refresh, a second reader of the
/// same query) would count a second view that nothing would release, and the
/// protection would stay on after the screen is gone. A query would also keep
/// the location of the content and the name of the reader in memory for as long
/// as it keeps data. Here the document lives in the state of the screen and
/// goes with it.
///
/// [OpenDocument] can take long (it asks the server, and the server can be
/// slow), so the viewing may be stopped before it answers. A document that
/// opens for a viewing that has stopped is released at once: the view it
/// counted would otherwise stay counted, and the protection with it.
///
/// A failure that ends the session is told to the session end handler with the
/// epoch of the access the viewing started under.
class DocumentViewing {
  /// Creates the viewing of [documentId].
  new({
    required this.documentId,
    required this._openDocument,
    required this._closeDocument,
    required this._epoch,
    required this._onSessionEnd,
  });

  /// The document viewed.
  final DocumentId documentId;

  final OpenDocument _openDocument;
  final CloseDocument _closeDocument;
  final int Function() _epoch;
  final void Function(String code, int epoch) _onSessionEnd;

  static const DocumentViewState _loading = DocumentLoading();

  /// What the screen shows.
  final ValueNotifier<DocumentViewState> state = ValueNotifier(_loading);

  void Function()? _stopViewing;

  /// Starts opening the document. Does nothing if it is already started.
  void start() {
    if (_stopViewing != null) {
      return;
    }
    var here = true;
    var held = false;
    final epoch = _epoch();

    void release() {
      if (!held) {
        return;
      }
      held = false;
      unawaited(_closeDocument.execute(documentId: documentId));
    }

    void settle(DocumentViewState next) {
      if (here) {
        state.value = next;
      }
    }

    void fail(String code) {
      _onSessionEnd(code, epoch);
      settle(DocumentFailed(code));
    }

    _stopViewing = () {
      here = false;
      release();
    };
    state.value = _loading;

    unawaited(() async {
      try {
        final opened = await _openDocument.execute(documentId: documentId);
        switch (opened) {
          case Err(:final error):
            fail(error.code);
          case Ok(:final value):
            held = true;
            if (here) {
              state.value = DocumentReady(value);
            } else {
              release();
            }
        }
      } on Object {
        // A use case does not throw; if one does, it is a failure like any
        // other.
        fail(RepositoryErrorCode.unexpected.value);
      }
    }());
  }

  /// Stops the viewing: the document is released, and the screen holds nothing
  /// of it any more.
  void stop() {
    _stopViewing?.call();
    _stopViewing = null;
    state.value = _loading;
  }

  /// Stops the viewing for good, when the screen goes.
  void dispose() {
    _stopViewing?.call();
    _stopViewing = null;
    state.dispose();
  }
}
