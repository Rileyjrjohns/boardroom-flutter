import 'package:boardroom/core/application/offline/cache_resource.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/meetings/application/meeting_cache_purger.dart';
import 'package:test/test.dart';

import '../../../support/builders/builders.dart';
import '../../../support/fakes/fake_meeting_cache.dart';

// Dart only: the purger is how the meetings feature takes part in the end of a
// session without auth importing its cache (see docs/architecture.md).

void main() {
  group('MeetingCachePurger', () {
    test('is named after the meeting cache in the logs', () {
      expect(
        MeetingCachePurger(FakeMeetingCache()).resource,
        equals(CacheResource.meeting),
      );
    });

    test('empties the meeting cache of every owner', () async {
      final cache = FakeMeetingCache();
      await cache.saveMeeting(aUserId(), aMeeting(), now);
      await cache.saveMeeting(aUserId('user-2'), aMeeting(), now);

      final purged = await MeetingCachePurger(cache).purge();

      expect(purged, equals(ok<void>(null)));
      expect(cache.isEmpty(), isTrue);
    });

    test('returns the failure of the cache', () async {
      final cache = FakeMeetingCache()..purgeFailure = storageWriteFailed('x');

      final purged = await MeetingCachePurger(cache).purge();

      expect(purged, equals(err(storageWriteFailed('x'))));
    });
  });
}
