import 'package:boardroom/core/application/offline/loaded.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/core/presentation/components/app_button.dart';
import 'package:boardroom/core/presentation/components/badge.dart';
import 'package:boardroom/core/presentation/components/demo_controls_view.dart';
import 'package:boardroom/core/presentation/components/live_text.dart';
import 'package:boardroom/core/presentation/components/loading_state.dart';
import 'package:boardroom/core/presentation/components/message.dart';
import 'package:boardroom/core/presentation/components/status_banner.dart';
import 'package:boardroom/core/presentation/format/formatters.dart';
import 'package:boardroom/core/presentation/providers.dart';
import 'package:boardroom/core/presentation/state/ui_state.dart';
import 'package:boardroom/core/presentation/test_ids.dart';
import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:boardroom/features/documents/application/use_cases/open_document.dart';
import 'package:boardroom/features/documents/presentation/components/capture_notice.dart';
import 'package:boardroom/features/documents/presentation/components/document_error_state.dart';
import 'package:boardroom/features/documents/presentation/components/document_watermark.dart';
import 'package:boardroom/features/documents/presentation/components/pdf_view_builder.dart';
import 'package:boardroom/features/documents/presentation/providers.dart';
import 'package:boardroom/features/documents/presentation/secure_content.dart';
import 'package:boardroom/features/documents/presentation/state/capture_watch.dart';
import 'package:boardroom/features/documents/presentation/state/document_viewing.dart';
import 'package:boardroom/features/documents/presentation/test_ids.dart';
import 'package:boardroom/features/meetings/presentation/messages.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The document viewer (docs/spec/screens.md "Document").
///
/// A document, in the viewer. The route parameter is a string from outside, so
/// it is parsed first: one that is no document id cannot be a document that
/// exists, and is shown as not found, without asking for anything.
class DocumentScreen extends ConsumerWidget {
  /// Creates the screen for the document with the raw id [documentId].
  const new({required this.documentId, super.key});

  /// The raw `documentId` path parameter.
  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      switch (parseDocumentId(documentId)) {
        Err() => const _NotFound(),
        Ok(:final value) => _DocumentViewer(key: ValueKey(value), id: value),
      };
}

class _NotFound extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => KeyedSubtree(
    key: const Key(DocumentsTestIds.documentNotFound),
    child: Message(
      message: AppLocalizations.of(context).documentsDocumentNotFound,
      centered: true,
    ),
  );
}

/// Opens the document while the screen is shown to the user, and lets go of it
/// when it is not.
///
/// The document is open while the screen is the one the user is looking at (its
/// route is the current one) and the app is open (the access is unlocked), and
/// released when either stops being true: the user goes back, another screen is
/// put over this one, the app locks, the user signs out or the session ends.
/// The router removes the screens of an app that is no longer open, which
/// disposes this one, so the release does not depend on this widget noticing;
/// the second condition is there for a screen that stays mounted for a frame.
class _DocumentViewer extends ConsumerWidget {
  const new({required this.id, super.key});

  final DocumentId id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(sessionOpenProvider);
    final focused = ModalRoute.isCurrentOf(context) ?? true;
    return _Viewing(id: id, shown: open && focused);
  }
}

class _Viewing extends ConsumerStatefulWidget {
  const new({required this.id, required this.shown});

  final DocumentId id;
  final bool shown;

  @override
  ConsumerState<_Viewing> createState() => _ViewingState();
}

class _ViewingState extends ConsumerState<_Viewing> {
  late final DocumentViewing _viewing = DocumentViewing(
    openDocument: ref.read(openDocumentUseCaseProvider),
    closeDocument: ref.read(closeDocumentUseCaseProvider),
    documentId: widget.id,
    epoch: () => ref.read(sessionEpochProvider),
    onSessionEnd: (code, epoch) =>
        ref.read(sessionEndHandlerProvider)(code, epoch),
  );
  late final CaptureWatch _watch = CaptureWatch(
    observeScreenCapture: ref.read(observeScreenCaptureUseCaseProvider),
    documentId: widget.id,
  );

  @override
  void initState() {
    super.initState();
    if (widget.shown) {
      _start();
    }
  }

  @override
  void didUpdateWidget(_Viewing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shown == oldWidget.shown) {
      return;
    }
    if (widget.shown) {
      _start();
    } else {
      _stop();
    }
  }

  @override
  void dispose() {
    _viewing.dispose();
    _watch.dispose();
    super.dispose();
  }

  void _start() {
    _viewing.start();
    _watch.start();
  }

  void _stop() {
    _viewing.stop();
    _watch.stop();
  }

  /// Opens the document again: after a failure, or when what was opened could
  /// not be displayed. The first viewing is released before the second opens.
  void _retry() {
    _viewing
      ..stop()
      ..start();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    key: const Key(DocumentsTestIds.documentScreen),
    color: AppColors.background,
    child: ValueListenableBuilder<DocumentViewState>(
      valueListenable: _viewing.state,
      builder: (context, state, _) => Column(
        children: [
          StatusBanner(staleSince: _staleSince(state)),
          const DemoOfflineSwitch(),
          ValueListenableBuilder<CaptureNoticeValue?>(
            valueListenable: _watch.notice,
            builder: (context, notice, _) => notice == null
                ? const SizedBox.shrink()
                : CaptureNotice(notice: notice, onDismiss: _watch.dismiss),
          ),
          Expanded(child: _body(context, state)),
        ],
      ),
    ),
  );

  Widget _body(BuildContext context, DocumentViewState state) =>
      switch (state) {
        DocumentLoading() => LoadingState(
          key: const Key(DocumentsTestIds.documentLoading),
          label: AppLocalizations.of(context).documentsDocumentLoading,
        ),
        DocumentFailed(:final code) => DocumentErrorState(
          code: code,
          onRetry: _retry,
        ),
        DocumentReady(:final opened) => _OpenedDocumentView(
          key: ObjectKey(opened),
          opened: opened,
          onRetry: _retry,
        ),
      };

  Instant? _staleSince(DocumentViewState state) => switch (state) {
    DocumentReady(
      opened: OpenedDocument(source: StaleSource(:final cachedAt)),
    ) =>
      cachedAt,
    _ => null,
  };
}

/// An opened document: its title and what protects it, and below them the
/// pages. Remounted for each opening (the key is the opened document itself, so
/// even an opening that follows another without a frame between them is a new
/// one), so a document that is opened again starts from the first page,
/// loading.
///
/// **The PDF view is mounted only while the app is active.** The privacy cover
/// is up from the moment the app goes inactive or to the background, and stays
/// up on the way back until the lock has been judged, so it is the signal:
/// while it is up the PDF view is unmounted, and it is mounted again, from the
/// first page, when the cover is lifted. On Android the native view renders
/// pages again when the app resumes, and when the lock removes the screen at
/// the same moment it renders on a document that is already closed, which
/// kills the app. A locked app removes this screen, so nothing mounts again
/// for it.
class _OpenedDocumentView extends ConsumerWidget {
  const new({required this.opened, required this.onRetry, super.key});

  final OpenedDocument opened;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final covered = ref.watch(privacyCoverUpProvider);
    final OpenedDocument(:document, :screenProtected) = opened;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppSpacing.sm,
            children: [
              Semantics(
                header: true,
                child: Text(
                  document.title,
                  key: const Key(DocumentsTestIds.documentTitle),
                  style: const TextStyle(
                    fontSize: AppFontSizes.subtitle,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Row(
                spacing: AppSpacing.sm,
                children: [
                  AppBadge(
                    label: confidentialityLabel(l10n, document.confidentiality),
                    tone: confidentialityTone(document.confidentiality),
                  ),
                  if (screenProtected)
                    AppBadge(
                      key: const Key(DocumentsTestIds.documentProtectedBadge),
                      label: l10n.documentsDocumentProtectedBadge,
                    ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: covered
              ? const SizedBox.expand()
              : _DocumentPages(opened: opened, onRetry: onRetry),
        ),
      ],
    );
  }
}

/// Where the viewer stands in the file, once it has read it.
enum _PdfStatus { loading, ready, failed }

/// The pages of an opened document: the file in the PDF view, the watermark of
/// the reader over it, and where the reader is in the file. It holds the state
/// of the view, so it starts again, loading, each time the view is mounted.
///
/// **Every document carries the watermark**, protected or not: the screen
/// protection and the badge are decided by the classification of the document
/// (see `OpenDocument`), but the name of the reader on a page deters a
/// photograph of any document.
///
/// **The pages and the watermark are in the secure container of a protected
/// document** (`SecureContent`): on iOS they are left out of screenshots. The
/// title, the badge and the page indicator are not, they are outside it. The
/// loading veil is inside, so it does not matter which of the two a capture
/// catches.
class _DocumentPages extends ConsumerStatefulWidget {
  const new({required this.opened, required this.onRetry});

  final OpenedDocument opened;
  final VoidCallback onRetry;

  @override
  ConsumerState<_DocumentPages> createState() => _DocumentPagesState();
}

class _DocumentPagesState extends ConsumerState<_DocumentPages> {
  static const int _firstPage = 1;

  _PdfStatus _status = _PdfStatus.loading;
  int _page = _firstPage;
  int _pageCount = 0;

  /// The viewer reports from its own callbacks, some of which can run while the
  /// frame is being built: the change is made after it then.
  void _update(VoidCallback change) {
    if (!mounted) {
      return;
    }
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(change);
        }
      });
    } else {
      setState(change);
    }
  }

  void _loaded(int pageCount) => _update(() {
    _status = _PdfStatus.ready;
    _page = _firstPage;
    _pageCount = pageCount;
  });

  void _pageChanged(int page, int pageCount) => _update(() {
    _status = _PdfStatus.ready;
    _page = page;
    _pageCount = pageCount;
  });

  void _failed() => _update(() => _status = _PdfStatus.failed);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatters = Formatters.of(context);
    final OpenedDocument(:location, :watermark, :screenProtected) =
        widget.opened;

    if (_status == _PdfStatus.failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: AppSpacing.lg,
            children: [
              KeyedSubtree(
                key: const Key(DocumentsTestIds.documentPdfError),
                child: LiveText(
                  message: l10n.documentsDocumentRenderFailed,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: AppFontSizes.body,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              AppButton(
                key: const Key(CoreTestIds.retryButton),
                title: l10n.coreStatesRetry,
                onPressed: widget.onRetry,
              ),
            ],
          ),
        ),
      );
    }

    final buildPdf = ref.watch(pdfViewBuilderProvider);
    return Column(
      children: [
        Expanded(
          child: SecureContent(
            key: const Key(DocumentsTestIds.documentSecureContent),
            secure: screenProtected,
            child: Stack(
              fit: StackFit.expand,
              children: [
                KeyedSubtree(
                  key: const Key(DocumentsTestIds.documentPdf),
                  child: buildPdf(
                    PdfViewRequest(
                      location: location,
                      onLoaded: _loaded,
                      onPageChanged: _pageChanged,
                      onFailed: _failed,
                    ),
                  ),
                ),
                if (_status == _PdfStatus.loading)
                  ColoredBox(
                    color: AppColors.documentBackdrop,
                    child: LoadingState(
                      key: const Key(DocumentsTestIds.documentPdfLoading),
                      label: l10n.documentsDocumentRendering,
                    ),
                  ),
                DocumentWatermark(watermark: watermark),
              ],
            ),
          ),
        ),
        if (_status == _PdfStatus.ready)
          Container(
            width: double.infinity,
            color: AppColors.surface,
            padding: EdgeInsets.only(
              top: AppSpacing.sm,
              bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.sm,
            ),
            child: Semantics(
              liveRegion: true,
              child: Text(
                l10n.documentsDocumentPageIndicator(
                  formatters.number(_page),
                  formatters.number(_pageCount),
                ),
                key: const Key(DocumentsTestIds.documentPageIndicator),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: AppFontSizes.caption,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
