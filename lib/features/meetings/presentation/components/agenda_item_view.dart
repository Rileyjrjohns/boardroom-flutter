import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:boardroom/features/meetings/domain/entities/agenda_item.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting.dart';
import 'package:boardroom/features/meetings/presentation/components/resolution_view.dart';
import 'package:boardroom/features/meetings/presentation/slots/resolution_actions.dart';
import 'package:boardroom/features/meetings/presentation/test_ids.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One point of the agenda, numbered by its position, with its resolution when
/// it has one.
class AgendaItemView extends ConsumerWidget {
  /// Creates the block of [item], a point of [meeting], judged at [now].
  const new({
    required this.meeting,
    required this.item,
    required this.now,
    super.key,
  });

  /// The meeting the item belongs to, handed to the slot of the actions.
  final Meeting meeting;

  /// The point of the agenda.
  final AgendaItem item;

  /// The instant the data was produced at, for the state of the vote (see
  /// `ResolutionView`).
  final Instant now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final resolution = item.resolution;
    final description = item.description;
    // What a feature adds under the resolution (see
    // `resolutionActionsProvider`); without one the resolution is display only.
    final actions = ref.watch(resolutionActionsProvider);
    return Column(
      key: Key(agendaItemTestId(item.id)),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.sm,
      children: [
        Text(
          l10n.meetingsMeetingAgendaItem('${item.position}', item.title),
          style: const TextStyle(
            fontSize: AppFontSizes.body,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        if (description != null)
          Text(
            description,
            style: const TextStyle(
              fontSize: AppFontSizes.body,
              color: AppColors.textSecondary,
            ),
          ),
        if (resolution != null)
          ResolutionView(
            resolution: resolution,
            now: now,
            actions: actions == null
                ? null
                : actions(context, meeting: meeting, resolution: resolution),
          ),
      ],
    );
  }
}
