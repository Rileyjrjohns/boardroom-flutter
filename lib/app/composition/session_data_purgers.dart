import 'package:boardroom/features/auth/application/ports/session_data_purger.dart';
import 'package:boardroom/features/documents/application/document_cache_purger.dart';
import 'package:boardroom/features/documents/application/ports/document_cache.dart';
import 'package:boardroom/features/meetings/application/meeting_cache_purger.dart';
import 'package:boardroom/features/meetings/application/ports/meeting_cache.dart';

/// Everything a session leaves on the device, as one purger for each feature
/// that keeps data for a user: the list that `purgeCaches` of `auth` runs when
/// a session ends. `auth` declares the port and does not know the features, so
/// it is here, where every feature is known, that the list is made. The order
/// is the one the caches have always been emptied in: the meetings, then the
/// documents.
List<SessionDataPurger> sessionDataPurgers({
  required MeetingCache meetingCache,
  required DocumentCache documentCache,
}) => List.unmodifiable([
  MeetingCachePurger(meetingCache),
  DocumentCachePurger(documentCache),
]);
