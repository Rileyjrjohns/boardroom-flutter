import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/shared/validation.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/features/meetings/domain/entities/agenda_item.dart';
import 'package:boardroom/features/meetings/domain/entities/document.dart';
import 'package:boardroom/features/meetings/domain/entities/meeting_summary.dart';
import 'package:boardroom/features/meetings/domain/entities/participant.dart';
import 'package:boardroom/features/meetings/domain/entities/resolution.dart';
import 'package:boardroom/features/votes/domain/entities/vote.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'meeting.freezed.dart';

/// A meeting with everything its detail screen shows. It has all the fields of
/// a [MeetingSummary] and can be used where one is expected.
@freezed
abstract class Meeting with _$Meeting implements MeetingSummary {
  /// Creates a meeting from validated parts. Use [createMeeting], which checks
  /// the collections and sorts the agenda.
  const factory({
    required MeetingId id,
    required String title,
    required Instant scheduledAt,
    required String location,

    /// Sorted by position.
    required List<AgendaItem> agenda,
    required List<Document> documents,
    required List<Participant> participants,
  }) = _Meeting;
}

/// What [createMeeting] needs to build a meeting.
final class MeetingInput {
  /// Creates the input of [createMeeting].
  const new({
    required this.summary,
    required this.agenda,
    required this.documents,
    required this.participants,
  });

  /// What a list of meetings shows about the meeting.
  final MeetingSummary summary;

  /// The agenda, in any order.
  final List<AgendaItem> agenda;

  /// The documents attached to the meeting.
  final List<Document> documents;

  /// The people invited to the meeting.
  final List<Participant> participants;
}

/// Builds a meeting. Within a meeting, agenda items must have distinct ids and
/// positions, resolutions distinct ids, documents distinct ids, participants
/// distinct user ids. The agenda is sorted by position. The collections are
/// copied.
Result<Meeting, ValidationError> createMeeting(MeetingInput input) {
  final MeetingInput(:summary, :agenda, :documents, :participants) = input;
  final resolutionIds = [
    for (final item in agenda)
      if (item.resolution case final resolution?) resolution.id,
  ];

  if (hasDuplicates(agenda.map((item) => item.id)) ||
      hasDuplicates(agenda.map((item) => item.position)) ||
      hasDuplicates(resolutionIds)) {
    return err(
      validationError(ValidationField.agenda, ValidationRule.duplicate),
    );
  }
  if (hasDuplicates(documents.map((document) => document.id))) {
    return err(
      validationError(ValidationField.documents, ValidationRule.duplicate),
    );
  }
  if (hasDuplicates(participants.map((participant) => participant.userId))) {
    return err(
      validationError(ValidationField.participants, ValidationRule.duplicate),
    );
  }

  return ok(
    Meeting(
      id: summary.id,
      title: summary.title,
      scheduledAt: summary.scheduledAt,
      location: summary.location,
      // Positions are distinct (checked above), so the order does not depend on
      // the stability of the sort.
      agenda: List.unmodifiable(
        List<AgendaItem>.of(agenda)
          ..sort((first, second) => first.position.compareTo(second.position)),
      ),
      documents: List.unmodifiable(documents),
      participants: List.unmodifiable(participants),
    ),
  );
}

/// The resolution with this id, wherever it sits in the agenda.
Resolution? findResolution(Meeting meeting, ResolutionId resolutionId) {
  for (final item in meeting.agenda) {
    final resolution = item.resolution;
    if (resolution != null && resolution.id == resolutionId) {
      return resolution;
    }
  }
  return null;
}

/// The participant with this user id, or null.
Participant? findParticipant(Meeting meeting, UserId userId) {
  for (final participant in meeting.participants) {
    if (participant.userId == userId) {
      return participant;
    }
  }
  return null;
}

/// A copy of the meeting in which the vote is recorded on its resolution, as
/// the server records it once the vote is accepted. Used to keep a cached copy
/// truthful, so that the voter cannot vote again from it. The meeting is
/// returned unchanged when the vote belongs to another meeting or to a
/// resolution it does not have.
Meeting withVoteRecorded(Meeting meeting, Vote vote) {
  if (vote.meetingId != meeting.id) {
    return meeting;
  }
  return meeting.copyWith(
    agenda: [
      for (final item in meeting.agenda)
        if (item.resolution case final resolution?
            when resolution.id == vote.resolutionId)
          item.copyWith(
            resolution: resolution.copyWith(recordedVote: vote.choice),
          )
        else
          item,
    ],
  );
}
