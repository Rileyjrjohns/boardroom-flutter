import 'package:boardroom/features/documents/application/ports/screen_protection.dart';
import 'package:boardroom/features/documents/application/use_cases/close_document.dart';
import 'package:boardroom/features/documents/application/use_cases/observe_screen_capture.dart';
import 'package:boardroom/features/documents/application/use_cases/open_document.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'providers.g.dart';

// What the screens of the documents need from the outside. They throw until
// `lib/app/providers` overrides them in the root `ProviderScope` (a widget test
// overrides them with use cases over fakes).

/// Opens a document: turns the screen protection on, counts a view, logs the
/// access.
@Riverpod(keepAlive: true)
OpenDocument openDocumentUseCase(Ref ref) =>
    throw UnimplementedError('openDocumentUseCaseProvider');

/// Closes a document: one close for each successful open.
@Riverpod(keepAlive: true)
CloseDocument closeDocumentUseCase(Ref ref) =>
    throw UnimplementedError('closeDocumentUseCaseProvider');

/// Watches the captures (screenshot, recording) the system reports.
@Riverpod(keepAlive: true)
ObserveScreenCapture observeScreenCaptureUseCase(Ref ref) =>
    throw UnimplementedError('observeScreenCaptureUseCaseProvider');

/// The screen protection port itself, for the demo screen of step 4 that drives
/// it directly. The documents go through the use cases.
@Riverpod(keepAlive: true)
ScreenProtection screenProtection(Ref ref) =>
    throw UnimplementedError('screenProtectionProvider');
