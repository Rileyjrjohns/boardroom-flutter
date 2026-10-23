import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/features/meetings/infrastructure/in_memory_meeting_cache.dart';

import '../../../support/contracts/meeting_cache_contract.dart';
import '../../../support/contracts/support.dart';

void main() {
  describeMeetingCacheContract('InMemoryMeetingCache', () {
    final cache = InMemoryMeetingCache();
    return MeetingCacheHarness(
      cache: cache,
      breakWrites: () => cache.failWritesWith(storageWriteFailed()),
      repairWrites: () => cache.failWritesWith(null),
    );
  }, inMemoryStore);
}
