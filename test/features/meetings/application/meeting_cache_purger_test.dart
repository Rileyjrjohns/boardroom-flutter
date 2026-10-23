import 'package:boardroom/core/application/offline/cache_resource.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/meetings/application/meeting_cache_purger.dart';
import 'package:test/test.dart';

import '../../../support/builders/builders.dart';
import '../../../support/fakes/fake_meeting_cache.dart';

// The purger is how the meetings feature takes part in the end of a session
// without auth importing its cache (see docs/architecture.md).

void main() {
  group('MeetingCachePurger', () {
    test('names the meetings as what it empties, for the monitoring', () {
      expect(
        MeetingCachePurger(FakeMeetingCache()).resource,
        equals(CacheResource.meeting),
      );
    });

    test('empties the cache of the meetings, for every owner', () async {
      final cache = FakeMeetingCache();
      await cache.saveMeeting(aUserId(), aMeeting(), now);
      await cache.saveMeeting(aUserId('user-2'), aMeeting(), now);

      final purged = await MeetingCachePurger(cache).purge();

      expect(purged, equals(ok<void>(null)));
      expect(cache.isEmpty(), isTrue);
    });

    test('gives the failure of a cache that cannot be emptied', () async {
      final cache = FakeMeetingCache()
        ..purgeFailure = storageWriteFailed('locked');

      final purged = await MeetingCachePurger(cache).purge();

      expect(purged, equals(err(storageWriteFailed('locked'))));
    });
  });
}
