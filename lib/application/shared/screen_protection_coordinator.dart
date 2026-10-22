import 'package:boardroom/application/ports/screen_protection.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/ids.dart';

/// What [ScreenProtectionCoordinator] needs.
abstract interface class ScreenProtectionCoordinatorDeps {
  /// The one global switch of the platform.
  ScreenProtection get screenProtection;
}

/// Decides when the screen protection is on, so that no adapter has to. The
/// `ScreenProtection` port is one global switch; this keeps the views that are
/// open and switches the protection off only when the last one is closed.
/// Closing document B while document A is still displayed leaves the screen
/// protected.
///
/// It counts the views of each document, not the documents: a document opened
/// twice (two screens, a screen that opens it again before the first was
/// closed) is two views, and closing one of them leaves the other one
/// protected.
///
/// Calls are serialised. `acquire` and `release` are queued, and each one
/// starts only when the one before has settled, so the calls reach the platform
/// in the order they were made and a slow `disable` of A can never land after
/// the `enable` of B that was asked for later. The queue, the counts and
/// whether a `disable` is owed are the only state, in memory: they die with the
/// app, as does the protection of the screen.
///
/// A view that is closed is gone, whatever the platform answers. When the last
/// one is closed and the platform fails to turn the protection off, the failure
/// is returned, and the coordinator remembers that a `disable` is owed: the
/// next `release` that finds no view open (the closing of the view that failed,
/// again, or of any other) sends it again. An `acquire` needs no retry of its
/// own: its `enable` puts the protection on, and the view it counts will owe
/// the `disable` when it is closed. So a `disable` that failed once can never
/// keep the protection on for the rest of the session.
///
/// One instance must be shared by every use case that opens or closes a
/// document (`OpenDocument`, `CloseDocument`): the composition root creates it
/// once and injects it. Two instances would each count their own views, and
/// each would switch the protection off on its own say-so.
final class ScreenProtectionCoordinator {
  /// Creates a coordinator over the switch of [_deps].
  new(this._deps);

  final ScreenProtectionCoordinatorDeps _deps;
  final Map<DocumentId, int> _views = {};

  /// Set when a `disable` failed with no view open, until one goes through.
  bool _disableOwed = false;
  Future<void> _queue = Future<void>.value();

  /// A view of a document that must be protected is being shown: turns the
  /// protection on, and counts the view only if that worked. A failure is
  /// returned and nothing is counted, so the caller must not show the document.
  Future<Result<void, ScreenProtectionError>> acquire(DocumentId documentId) =>
      _enqueue<Result<void, ScreenProtectionError>>(() async {
        final enabled = await _deps.screenProtection.enable();
        if (enabled is Err) {
          return enabled;
        }

        _views[documentId] = (_views[documentId] ?? 0) + 1;
        return ok<void>(null);
      });

  /// A view of a document is closed, and is no longer counted, whatever happens
  /// next. A document with no view is ignored (no effect, success), unless a
  /// `disable` is owed and no view of any document is open: then it is sent
  /// again. When this was the last view of all, turns the protection off. If
  /// that fails, the failure is returned and the `disable` is owed (see the
  /// class).
  Future<Result<void, ScreenProtectionError>> release(DocumentId documentId) =>
      _enqueue<Result<void, ScreenProtectionError>>(() async {
        if ((_views[documentId] ?? 0) > 0) {
          _drop(documentId);
        } else if (!_disableOwed) {
          return ok<void>(null);
        }

        if (_totalViews() > 0) {
          return ok<void>(null);
        }

        final disabled = await _deps.screenProtection.disable();
        _disableOwed = disabled is Err;
        return disabled;
      });

  /// Runs a task once every task queued before it has settled, whatever their
  /// outcome.
  Future<T> _enqueue<T>(Future<T> Function() task) {
    final result = _queue.then((_) => task());
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  int _totalViews() => _views.values.fold(0, (total, count) => total + count);

  void _drop(DocumentId documentId) {
    final count = _views[documentId] ?? 0;
    if (count <= 1) {
      _views.remove(documentId);
    } else {
      _views[documentId] = count - 1;
    }
  }
}
