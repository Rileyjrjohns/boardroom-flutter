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
import 'package:boardroom/features/meetings/domain/value_objects/meeting_period.dart';
import 'package:boardroom/features/meetings/presentation/components/announce.dart';
import 'package:boardroom/features/meetings/presentation/components/meeting_row.dart';
import 'package:boardroom/features/meetings/presentation/components/period_control.dart';
import 'package:boardroom/features/meetings/presentation/messages.dart';
import 'package:boardroom/features/meetings/presentation/state/meetings_list.dart';
import 'package:boardroom/features/meetings/presentation/state/selected_meetings_period.dart';
import 'package:boardroom/features/meetings/presentation/test_ids.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How far from the end of the list, in lengths of the visible part, the next
/// page is asked for.
const double _endReachedThreshold = 0.5;

/// The meetings list, the home of the open app (docs/spec/screens.md "Meetings
/// list"). The meetings of the user, upcoming or past: the period is chosen
/// with a segmented control and kept in `selectedMeetingsPeriodProvider`; each
/// period has its own list (see `_PeriodList`), so nothing of one shows on the
/// other. A tap on a row opens the meeting.
class MeetingsListScreen extends ConsumerWidget {
  /// Creates the screen.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(selectedMeetingsPeriodProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DemoOfflineSwitch(),
        PeriodControl(
          selected: period,
          onChanged: ref.read(selectedMeetingsPeriodProvider.notifier).select,
        ),
        // Keyed by period: a period is a list of its own, with its own pull to
        // refresh in progress and its own scroll position, not the same list
        // given other data.
        Expanded(
          child: _PeriodList(key: ValueKey(period), period: period),
        ),
      ],
    );
  }
}

/// The meetings of one period, a page at a time. The next page is loaded when
/// the end of the list is near, a pull starts again from the first page, and
/// the states of a list are all handled: loading, error with a way to retry,
/// empty, and the end of the list. When the server cannot be reached and a
/// saved copy is shown, a banner says since when.
///
/// Only an error that can pass is shown next to the list, with its retry. Every
/// other error a list can meet says the session is over, and ends the session
/// for the whole app: the router moves the user to the sign-in or the lock
/// screen, and the cache is emptied, so no row of the list outlives it.
class _PeriodList extends ConsumerStatefulWidget {
  const new({required this.period, super.key});

  final MeetingPeriod period;

  @override
  ConsumerState<_PeriodList> createState() => _PeriodListState();
}

class _PeriodListState extends ConsumerState<_PeriodList> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  MeetingsListProvider get _provider => meetingsListProvider(widget.period);

  MeetingsList get _list => ref.read(_provider.notifier);

  // The next page is asked for when the end is near. A list shorter than the
  // screen has its end in view from the start, so it is checked after each
  // layout too. The notifier ignores the call while a page is being fetched,
  // after a failed page, and when there is no page left.
  void _loadMoreWhenNear(ScrollMetrics metrics) {
    if (metrics.extentAfter <
        metrics.viewportDimension * _endReachedThreshold) {
      _list.loadMore().ignore();
    }
  }

  void _checkEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller.hasClients) {
        _loadMoreWhenNear(_controller.position);
      }
    });
  }

  Future<void> _refresh() {
    announceOnIos(context, AppLocalizations.of(context).coreStatesRefreshing);
    return _list.restart();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final catalog = ref.watch(errorCatalogProvider);
    final async = ref.watch(_provider);
    final state = async.value;
    final meetings = state?.meetings ?? const [];
    final errorCode = async.hasError && !async.isLoading
        ? errorCodeOf(async.error, catalog)
        : null;
    final refreshFailed = errorCode != null && meetings.isNotEmpty;
    final formatters = Formatters.of(context);
    if (state != null) {
      _checkEnd();
    }

    final Widget empty;
    if (state == null && errorCode == null) {
      empty = KeyedSubtree(
        key: const Key(MeetingsTestIds.meetingsLoading),
        child: LoadingState(label: l10n.meetingsLoading),
      );
    } else if (errorCode != null && meetings.isEmpty) {
      empty = KeyedSubtree(
        key: const Key(MeetingsTestIds.meetingsError),
        child: ErrorState(
          code: errorCode,
          onRetry: () => _list.restart().ignore(),
        ),
      );
    } else {
      empty = KeyedSubtree(
        key: const Key(MeetingsTestIds.meetingsEmpty),
        child: Message(
          centered: true,
          message: emptyListLabel(l10n, widget.period),
        ),
      );
    }

    final Widget? footer;
    if (state != null && state.loadingMore) {
      footer = Semantics(
        key: const Key(MeetingsTestIds.meetingsLoadingMore),
        label: l10n.meetingsLoadingMore,
        liveRegion: true,
        child: const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ),
      );
    } else if (state?.nextPageFailure case final failure?) {
      footer = KeyedSubtree(
        key: const Key(MeetingsTestIds.meetingsLoadMoreError),
        child: InlineError(
          code: failure,
          onRetry: () => _list.retryNextPage().ignore(),
        ),
      );
    } else if (state != null && meetings.isNotEmpty && !state.hasNextPage) {
      footer = KeyedSubtree(
        key: const Key(MeetingsTestIds.meetingsEnd),
        child: Message(message: l10n.meetingsEndOfList),
      );
    } else {
      footer = null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatusBanner(staleSince: state?.staleSince),
        if (refreshFailed)
          KeyedSubtree(
            key: const Key(CoreTestIds.refreshError),
            child: InlineError(
              code: errorCode,
              onRetry: () => _list.restart().ignore(),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            semanticsLabel: l10n.coreStatesRefreshing,
            onRefresh: _refresh,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                _loadMoreWhenNear(notification.metrics);
                return false;
              },
              child: CustomScrollView(
                key: const Key(MeetingsTestIds.meetingsList),
                controller: _controller,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (meetings.isEmpty)
                    SliverFillRemaining(hasScrollBody: false, child: empty)
                  else
                    SliverList.builder(
                      itemCount: meetings.length,
                      itemBuilder: (context, index) {
                        final meeting = meetings[index];
                        return MeetingRow(
                          key: ValueKey(meeting.id),
                          id: meeting.id,
                          title: meeting.title,
                          when: formatters.dateTime(meeting.scheduledAt),
                          location: meeting.location,
                          onOpen: () => openMeeting(context, meeting.id),
                        );
                      },
                    ),
                  if (footer != null) SliverToBoxAdapter(child: footer),
                  const SliverPadding(
                    padding: EdgeInsets.only(bottom: AppSpacing.lg),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
