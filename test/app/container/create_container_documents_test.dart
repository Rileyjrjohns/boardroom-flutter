import 'dart:typed_data';

import 'package:boardroom/app/container/app_container.dart';
import 'package:boardroom/app/container/create_container.dart';
import 'package:boardroom/core/application/offline/loaded.dart';
import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/infrastructure/files/file_store.dart';
import 'package:boardroom/features/documents/domain/errors/screen_protection_error.dart';
import 'package:boardroom/features/documents/infrastructure/in_memory_screen_protection.dart';
import 'package:boardroom/features/meetings/domain/entities/document.dart';
import 'package:boardroom/features/meetings/domain/value_objects/meeting_period.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes/fake_monitoring.dart';
import '../../support/infrastructure/faulty_file_volume.dart';
import '../../support/infrastructure/memory_file_volume.dart';
import '../../support/infrastructure/test_files.dart';
import 'container_support.dart';
import 'http_support.dart';

// The scenarios of `createContainer.documents.test.ts`: what the documents
// leave on the device, in the development configuration and in the real one.

/// A confidential document and one that is not, among the documents of the
/// upcoming meetings.
Future<({Document confidential, Document other})> _documentsOf(
  AppContainer container,
) async {
  final listed = valueOf(
    await container.useCases.listMeetings.execute(
      period: MeetingPeriod.upcoming,
      request: firstPage(),
    ),
  );
  final documents = <Document>[];
  for (final summary in listed.data.items) {
    final meeting = valueOf(
      await container.useCases.getMeeting.execute(meetingId: summary.id),
    ).data;
    documents.addAll(meeting.documents);
  }
  return (
    confidential: documents.firstWhere(
      (document) =>
          document.confidentiality == ConfidentialityLevel.confidential,
    ),
    other: documents.firstWhere(
      (document) =>
          document.confidentiality != ConfidentialityLevel.confidential,
    ),
  );
}

Future<List<String>> _names(FileStore files) => files.list().then(valueOf);

Matcher _failsWithCode(String code) =>
    isA<Err<Object?, AppError>>().having((err) => err.error.code, 'code', code);

void main() {
  final parent = temporaryDirectory();

  group('createContainer, development configuration, documents', () {
    Future<AppContainer> start({
      FileStore? files,
      InMemoryScreenProtection? protection,
      FakeMonitoring? monitoring,
    }) async {
      final world = silentRuntime(
        fileStore: files,
        screenProtection: protection ?? InMemoryScreenProtection(),
        monitoring: monitoring,
      );
      final container = built(await createContainer(dev(), world.runtime));
      addTearDown(container.dispose);
      return container;
    }

    test('opens a document: its content is a file of the device, in the '
        'store', () async {
      final files = createFileStore(MemoryFileVolume());
      final container = await start(files: files);
      final (:confidential, :other) = await _documentsOf(container);

      final opened = valueOf(
        await container.useCases.openDocument.execute(
          documentId: confidential.id,
        ),
      );

      expect(opened.location, startsWith(memoryRootUri));
      expect(opened.screenProtected, isTrue);
      expect(opened.document.id, equals(confidential.id));
      expect(await _names(files), hasLength(1));
      expect(other.id, isNot(equals(confidential.id)));
    });

    test('opens it again without the network from the saved copy, on the same '
        'file, protected', () async {
      final container = await start();
      final (:confidential, :other) = await _documentsOf(container);
      final first = valueOf(
        await container.useCases.openDocument.execute(
          documentId: confidential.id,
        ),
      );
      container.demoControls!.network.setOnline(online: false);

      final again = valueOf(
        await container.useCases.openDocument.execute(
          documentId: confidential.id,
        ),
      );

      expect(again.source, isA<StaleSource>());
      expect(again.location, equals(first.location));
      expect(again.screenProtected, isTrue);
      expect(other, isNotNull);
    });

    test('refuses a document never opened when the network is down', () async {
      final container = await start();
      final (:confidential, :other) = await _documentsOf(container);
      await container.useCases.openDocument.execute(documentId: other.id);
      container.demoControls!.network.setOnline(online: false);

      final refused = await container.useCases.openDocument.execute(
        documentId: confidential.id,
      );

      expect(refused, _failsWithCode('networkUnavailable'));
    });

    test('turns the screen protection on for a confidential document and off '
        'when it is closed', () async {
      final protection = InMemoryScreenProtection();
      final container = await start(protection: protection);
      final (:confidential, :other) = await _documentsOf(container);

      await container.useCases.openDocument.execute(documentId: other.id);
      expect(protection.isEnabled(), isFalse);
      await container.useCases.openDocument.execute(
        documentId: confidential.id,
      );
      expect(protection.isEnabled(), isTrue);
      await container.useCases.closeDocument.execute(
        documentId: confidential.id,
      );

      expect(protection.isEnabled(), isFalse);
    });

    test('does not show a confidential document when the screen cannot be '
        'protected', () async {
      final protection = InMemoryScreenProtection()
        ..failEnableWith(screenProtectionFailed());
      final container = await start(protection: protection);
      final (:confidential, other: _) = await _documentsOf(container);

      final refused = await container.useCases.openDocument.execute(
        documentId: confidential.id,
      );

      expect(refused, _failsWithCode('screenProtectionFailed'));
    });

    test('leaves nothing of any document on the device once the user signs '
        'out', () async {
      final files = createFileStore(MemoryFileVolume());
      final container = await start(files: files);
      final (:confidential, :other) = await _documentsOf(container);
      await container.useCases.openDocument.execute(
        documentId: confidential.id,
      );
      await container.useCases.openDocument.execute(documentId: other.id);
      expect(await _names(files), hasLength(2));

      valueOf(await container.useCases.signOut.execute());

      expect(await _names(files), isEmpty);
      valueOf(
        await container.useCases.signIn.execute(
          email: aliceEmail,
          password: demoAccountPassword,
        ),
      );
      container.demoControls!.network.setOnline(online: false);
      final afterwards = await container.useCases.openDocument.execute(
        documentId: other.id,
      );
      expect(afterwards, _failsWithCode('networkUnavailable'));
    });

    test('deletes what the last run left when it starts, before anything is '
        'downloaded', () async {
      final files = createFileStore(MemoryFileVolume());
      valueOf(
        await files.write(
          'left-by-the-last-run.pdf',
          Uint8List.fromList([1, 2, 3]),
        ),
      );

      await start(files: files);

      expect(await _names(files), isEmpty);
    });

    test('starts, and tells the monitoring, when the files of the last run '
        'cannot be deleted', () async {
      final volume = FaultyFileVolume(MemoryFileVolume());
      final files = createFileStore(volume);
      valueOf(await files.write('left.pdf', Uint8List.fromList([1])));
      volume.fail(VolumeCall.remove, true);
      final monitoring = FakeMonitoring();

      await start(files: files, monitoring: monitoring);

      expect(monitoring.errors, hasLength(1));
      final reported = monitoring.errors.single;
      expect(reported.event, equals(MonitoringEvent.orphanFileNotDeleted));
      expect(reported.error.code, equals('storageWriteFailed'));
      expect(reported.attributes, equals({LogAttribute.resource: 'document'}));
    });
  });

  group('createContainer, http configuration, documents', () {
    Future<(TestWorld, AppContainer)> signedIn() async {
      final world = await aTestWorld(parent);
      final container = await world.start();
      valueOf(
        await container.useCases.signIn.execute(
          email: aliceEmail,
          password: demoAccountPassword,
        ),
      );
      return (world, container);
    }

    test('downloads the document to a file of the device, and remembers it in '
        'the database', () async {
      final (world, container) = await signedIn();
      final (:confidential, other: _) = await _documentsOf(container);

      final opened = valueOf(
        await container.useCases.openDocument.execute(
          documentId: confidential.id,
        ),
      );

      expect(opened.source, isA<FreshSource>());
      expect(opened.location, startsWith(memoryRootUri));
      expect(await _names(world.files), hasLength(1));
    });

    test('opens the document again after a restart, without the network, from '
        'the database and the file', () async {
      final (world, container) = await signedIn();
      final (:confidential, other: _) = await _documentsOf(container);
      final first = valueOf(
        await container.useCases.openDocument.execute(
          documentId: confidential.id,
        ),
      );
      await container.dispose();

      final restarted = await world.start();
      valueOf(await restarted.useCases.restoreSession.execute());
      valueOf(await restarted.useCases.unlockApp.execute());
      world.server.backend.network.setOnline(online: false);
      final again = valueOf(
        await restarted.useCases.openDocument.execute(
          documentId: confidential.id,
        ),
      );

      expect(again.source, isA<StaleSource>());
      expect(again.location, equals(first.location));
    });

    test('refuses a document never opened while offline', () async {
      final (world, container) = await signedIn();
      final (:confidential, other: _) = await _documentsOf(container);
      world.server.backend.network.setOnline(online: false);

      final refused = await container.useCases.openDocument.execute(
        documentId: confidential.id,
      );

      expect(refused, _failsWithCode('networkUnavailable'));
    });

    test('leaves nothing of any document on the device once the user signs '
        'out', () async {
      final (world, container) = await signedIn();
      final (:confidential, :other) = await _documentsOf(container);
      await container.useCases.openDocument.execute(
        documentId: confidential.id,
      );
      await container.useCases.openDocument.execute(documentId: other.id);
      expect(await _names(world.files), hasLength(2));

      valueOf(await container.useCases.signOut.execute());

      expect(await _names(world.files), isEmpty);
    });

    test('deletes the files of a session the server refuses, and the saved '
        'copies with them', () async {
      final (world, container) = await signedIn();
      final (:confidential, other: _) = await _documentsOf(container);
      await container.useCases.openDocument.execute(
        documentId: confidential.id,
      );
      world.server.api.revokeSessions();

      final refused = await container.useCases.listMeetings.execute(
        period: MeetingPeriod.past,
        request: firstPage(),
      );

      expect(refused, _failsWithCode('unauthorized'));
      expect(await _names(world.files), isEmpty);
    });

    test('deletes the files no entry points at when it starts, and keeps the '
        'ones an entry does', () async {
      final (world, container) = await signedIn();
      final (:confidential, other: _) = await _documentsOf(container);
      await container.useCases.openDocument.execute(
        documentId: confidential.id,
      );
      await container.dispose();
      valueOf(
        await world.files.write('orphan.pdf', Uint8List.fromList([1, 2, 3])),
      );
      expect(await _names(world.files), hasLength(2));

      await world.start();

      final remaining = await _names(world.files);
      expect(remaining, hasLength(1));
      expect(remaining, isNot(contains('orphan.pdf')));
    });

    test('starts, and tells the monitoring once, when a file no entry points '
        'at cannot be deleted', () async {
      final world = await aTestWorld(parent);
      final volume = FaultyFileVolume(MemoryFileVolume());
      final files = createFileStore(volume);
      valueOf(await files.write('orphan.pdf', Uint8List.fromList([1])));
      volume.fail(VolumeCall.remove, true);

      await world.start(runtime: world.runtime(fileStore: files));

      final reported = world.monitoring.errors
          .where(
            (record) => record.event == MonitoringEvent.orphanFileNotDeleted,
          )
          .toList();
      expect(reported, hasLength(1));
      expect(reported.single.attributes, {LogAttribute.resource: 'document'});
    });
  });
}
