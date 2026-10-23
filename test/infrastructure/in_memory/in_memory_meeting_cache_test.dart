import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/infrastructure/in_memory/in_memory_meeting_cache.dart';

import '../../application/support/contracts/meeting_cache_contract.dart';
import '../../application/support/contracts/support.dart';

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
