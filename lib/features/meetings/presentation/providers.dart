import 'package:boardroom/features/meetings/application/use_cases/get_meeting.dart';
import 'package:boardroom/features/meetings/application/use_cases/list_meetings.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'providers.g.dart';

// What the screens of the meetings need from the outside. They throw until
// `lib/app/providers` overrides them in the root `ProviderScope` (a widget test
// overrides them with use cases over fakes).

/// The list of the meetings of a period, page by page.
@Riverpod(keepAlive: true)
ListMeetings listMeetingsUseCase(Ref ref) =>
    throw UnimplementedError('listMeetingsUseCaseProvider');

/// One meeting, with its agenda, resolutions, participants and documents.
@Riverpod(keepAlive: true)
GetMeeting getMeetingUseCase(Ref ref) =>
    throw UnimplementedError('getMeetingUseCaseProvider');

/// How many meetings a page of the list holds (`meetingsPageSize` of the
/// settings).
@Riverpod(keepAlive: true)
int meetingsPageSize(Ref ref) =>
    throw UnimplementedError('meetingsPageSizeProvider');
