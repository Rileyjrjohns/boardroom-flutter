import 'package:boardroom/core/application/offline/loaded.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/presentation/components/demo_controls_view.dart';
import 'package:boardroom/core/presentation/components/error_views.dart';
import 'package:boardroom/core/presentation/components/loading_state.dart';
import 'package:boardroom/core/presentation/components/message.dart';
import 'package:boardroom/core/presentation/components/status_banner.dart';
import 'package:boardroom/core/presentation/format/formatters.dart';
import 'package:boardroom/core/presentation/navigation/navigate.dart';
import 'package:boardroom/core/presentation/providers.dart';
import 'package:boardroom/core/presentation/query/query_failure.dart';
import 'package:boardroom/core/presentation/test_ids.dart';
import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:boardroom/features/meetings/presentation/components/agenda_item_view.dart';
import 'package:boardroom/features/meetings/presentation/components/announce.dart';
import 'package:boardroom/features/meetings/presentation/components/document_row.dart';
import 'package:boardroom/features/meetings/presentation/components/participant_row.dart';
import 'package:boardroom/features/meetings/presentation/components/section.dart';
import 'package:boardroom/features/meetings/presentation/state/meeting_query.dart';
import 'package:boardroom/features/meetings/presentation/test_ids.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The detail of a meeting (docs/spec/screens.md "Meeting detail"). The route
/// parameter is a string from outside, so it is parsed first: one that is no
/// meeting id cannot be a meeting that exists, and is shown as not found
/// without asking the server. [meetingId] is the raw path parameter.
class MeetingDetailScreen extends StatelessWidget {
  /// Creates the screen for the meeting with the raw id [meetingId].
  const new({required this.meetingId, super.key});

  /// The raw `meetingId` path parameter.
  final String meetingId;

  @override
  Widget build(BuildContext context) => switch (parseMeetingId(meetingId)) {
    Ok(:final value) => _MeetingDetail(id: value),
    Err() => const _NotFound(),
  };
}

class _NotFound extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => KeyedSubtree(
    key: const Key(MeetingsTestIds.meetingNotFound),
    child: Message(
      centered: true,
      message: AppLocalizations.of(context).coreErrorsNotFound,
    ),
  );
}

class _MeetingDetail extends ConsumerWidget {
  const new({required this.id});

  final MeetingId id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final catalog = ref.watch(errorCatalogProvider);
    final provider = meetingQueryProvider(id);
    final async = ref.watch(provider);
    final data = async.value;
    final errorCode = async.hasError && !async.isLoading
        ? errorCodeOf(async.error, catalog)
        : null;

    Future<void> refresh() async {
      announceOnIos(context, l10n.coreStatesRefreshing);
      ref.invalidate(provider);
      try {
        await ref.read(provider.future);
        // The failure is the state of the provider, which the screen reads.
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {}
    }

    if (data == null && errorCode == null) {
      return KeyedSubtree(
        key: const Key(MeetingsTestIds.meetingLoading),
        child: LoadingState(label: l10n.meetingsMeetingLoading),
      );
    }
    // A failure that asking again cannot fix, or a refusal of the meeting, is
    // final for the screen: it shows the error and never the meeting it held
    // before. A meeting that does not exist is told as such.
    if (errorCode != null &&
        (data == null ||
            !catalog.isRetryableCode(errorCode) ||
            itemRefusalCodes.contains(errorCode))) {
      return errorCode == RepositoryErrorCode.notFound.value
          ? const _NotFound()
          : KeyedSubtree(
              key: const Key(MeetingsTestIds.meetingError),
              child: ErrorState(
                code: errorCode,
                onRetry: () => ref.invalidate(provider),
              ),
            );
    }
    if (data == null) {
      return const SizedBox.shrink();
    }
    return _MeetingContent(
      loaded: data,
      refreshError: errorCode,
      onRefresh: refresh,
      onRetry: () => ref.invalidate(provider),
    );
  }
}

class _MeetingContent extends StatelessWidget {
  const new({
    required this.loaded,
    required this.refreshError,
    required this.onRefresh,
    required this.onRetry,
  });

  /// The meeting, where it comes from and the instant it was loaded at.
  final Loaded<Meeting> loaded;

  /// Why the last refresh failed, while the content of the last success stays
  /// on the screen.
  final String? refreshError;

  final Future<void> Function() onRefresh;

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatters = Formatters.of(context);
    final meeting = loaded.data;
    final staleSince = switch (loaded.source) {
      StaleSource(:final cachedAt) => cachedAt,
      FreshSource() => null,
    };
    return RefreshIndicator(
      semanticsLabel: l10n.coreStatesRefreshing,
      onRefresh: onRefresh,
      child: SingleChildScrollView(
        key: const Key(MeetingsTestIds.meetingDetail),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StatusBanner(staleSince: staleSince),
            const DemoOfflineSwitch(),
            if (refreshError case final code?)
              KeyedSubtree(
                key: const Key(CoreTestIds.refreshError),
                child: InlineError(code: code, onRetry: onRetry),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: AppSpacing.xs,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      meeting.title,
                      key: const Key(MeetingsTestIds.meetingTitle),
                      style: const TextStyle(
                        fontSize: AppFontSizes.title,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    formatters.fullDateTime(meeting.scheduledAt),
                    style: _detail,
                  ),
                  Text(meeting.location, style: _detail),
                ],
              ),
            ),
            MeetingSection(
              title: l10n.meetingsMeetingAgenda,
              testId: MeetingsTestIds.agendaSection,
              children: [
                if (meeting.agenda.isEmpty)
                  Text(l10n.meetingsMeetingAgendaEmpty, style: _detail)
                else
                  for (final item in meeting.agenda)
                    AgendaItemView(
                      key: ValueKey(item.id),
                      meeting: meeting,
                      item: item,
                      now: loaded.loadedAt,
                    ),
              ],
            ),
            MeetingSection(
              title: l10n.meetingsMeetingDocuments,
              testId: MeetingsTestIds.documentsSection,
              children: [
                if (meeting.documents.isEmpty)
                  Text(l10n.meetingsMeetingDocumentsEmpty, style: _detail)
                else
                  for (final document in meeting.documents)
                    DocumentRow(
                      key: ValueKey(document.id),
                      document: document,
                      onOpen: () => openDocument(context, document.id),
                    ),
              ],
            ),
            MeetingSection(
              title: l10n.meetingsMeetingParticipants,
              testId: MeetingsTestIds.participantsSection,
              children: [
                if (meeting.participants.isEmpty)
                  Text(l10n.meetingsMeetingParticipantsEmpty, style: _detail)
                else
                  for (final participant in meeting.participants)
                    ParticipantRow(
                      key: ValueKey(participant.userId),
                      participant: participant,
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

const TextStyle _detail = TextStyle(
  fontSize: AppFontSizes.body,
  color: AppColors.textSecondary,
);
