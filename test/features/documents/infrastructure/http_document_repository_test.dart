import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:boardroom/app/dev/in_memory/in_memory_backend.dart';
import 'package:boardroom/app/dev/pdf/create_document_pdf.dart';
import 'package:boardroom/core/application/ports/monitoring.dart';
import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/value_objects/ids.dart';
import 'package:boardroom/core/infrastructure/files/file_store.dart';
import 'package:boardroom/core/infrastructure/http/protocol.dart';
import 'package:boardroom/features/documents/domain/value_objects/document_location.dart';
import 'package:boardroom/features/documents/infrastructure/dto/document_dto.dart';
import 'package:boardroom/features/documents/infrastructure/http_document_repository.dart';
import 'package:boardroom/features/documents/infrastructure/store_document_content.dart';
import 'package:boardroom/features/meetings/domain/entities/document.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import '../../../support/builders/builders.dart';
import '../../../support/infrastructure/document_device.dart';
import '../../../support/infrastructure/faulty_file_volume.dart';
import '../../../support/infrastructure/http_adapters_world.dart';
import '../../../support/infrastructure/http_world.dart';
import '../../../support/infrastructure/test_files.dart';
import '../../../support/infrastructure/test_server.dart';

// The download of a document, end to end: the real repository, the real client,
// the dio adapter that stands in for the network, and the real files of a
// directory of the machine. The server is the API of the simulated server
// (`MockApi`) except where a test makes it send what a broken or hostile server
// would. The contract suite of the repository is run by
// http_repositories_test.dart.

final Document _document = aDocument();
final Uint8List _pdf = createDocumentPdf(
  DocumentPdfSpec(title: _document.title, pageCount: _document.pageCount),
);
final Map<String, String> _pdfHeaders = {
  HttpHeader.contentType.value: mediaTypePdf,
  HttpHeader.eTag.value: '"v1"',
};
final UserId _user = aUserId();

/// A stream of [size] bytes in chunks, with no length declared: a body that
/// does not say how long it is.
Stream<Uint8List> _streamOf(int size) {
  const chunkSize = 500;
  Uint8List chunk(int length) => Uint8List(length)
    ..fillRange(0, length, 0x41)
    ..setAll(0, const [0x25, 0x50, 0x44, 0x46, 0x2d]);
  return Stream.fromIterable([
    for (var sent = 0; sent < size; sent += chunkSize)
      chunk(min(chunkSize, size - sent)),
  ]);
}

void main() {
  final installed = installFixtureServer();
  final filesParent = temporaryDirectory();

  HttpWorld aWorld([HttpWorldOptions options = const .new()]) {
    return createHttpWorld(installed, options)..load(
      ServerContent(
        meetings: [
          aMeeting(documents: [_document]),
        ],
        recordedVotes: const [],
      ),
    );
  }

  Future<HttpWorld> aSignedInWorld([
    HttpWorldOptions options = const .new(),
  ]) async {
    final world = aWorld(options);
    await world.signInAs(_user);
    return world;
  }

  /// The names of the files of the device, or a marker when they cannot be
  /// listed.
  Future<List<String>> filesOf(HttpWorld world) async {
    final listed = await world.files.list();
    return switch (listed) {
      Ok(:final value) => value,
      Err() => const ['the files could not be listed'],
    };
  }

  /// Makes the server answer with [body], whatever the request.
  void serverSends(
    Object body, {
    int status = 200,
    Map<String, String>? headers,
  }) {
    final sent = {
      for (final entry in (headers ?? _pdfHeaders).entries)
        entry.key: [entry.value],
    };
    installed.answerWith = (_) => switch (body) {
      final Stream<Uint8List> stream => ResponseBody(
        stream,
        status,
        headers: sent,
      ),
      final Uint8List bytes => ResponseBody.fromBytes(
        bytes,
        status,
        headers: sent,
      ),
      final String text => ResponseBody.fromString(text, status, headers: sent),
      _ => throw ArgumentError.value(body),
    };
  }

  /// The world, with the files of the device in a directory of the machine.
  Future<HttpWorld> aWorldOnDisk([
    HttpDocumentRepositoryOptions documents =
        const HttpDocumentRepositoryOptions(),
  ]) => aSignedInWorld(
    HttpWorldOptions(
      server: TestServerOptions(files: testFileStore(filesParent)),
      documents: documents,
    ),
  );

  group('HttpDocumentRepository, reading the metadata', () {
    test('answers the document that was asked for', () async {
      final world = await aSignedInWorld();

      expect(await world.documents.get(_document.id), equals(ok(_document)));
    });

    test('refuses the metadata of another document than the one asked for, '
        'and tells nothing of either', () async {
      final world = await aSignedInWorld();
      final other = aDocument(
        id: aDocumentId('document-other'),
        title: 'Board minutes',
      );
      serverSends(
        jsonEncode(toDocumentWire(other).toJson()),
        headers: {HttpHeader.contentType.value: mediaTypeJson},
      );

      final refused = await world.documents.get(_document.id);

      expect(refused, equals(err(unexpected('invalid response'))));
      expect(
        world.monitoring.capturedEvents(),
        equals([MonitoringEvent.responseInvalid]),
      );
      expect(
        world.monitoring.errors.first.attributes,
        equals({
          LogAttribute.resource: 'document',
          LogAttribute.reason: 'otherItem',
        }),
      );
      final everything =
          '$refused ${world.monitoring.errors} ${world.monitoring.logs}';
      expect(everything, isNot(contains(_document.id)));
      expect(everything, isNot(contains(other.id)));
      expect(everything, isNot(contains(other.title)));
    });
  });

  group('HttpDocumentRepository, downloading the content', () {
    group('a PDF', () {
      test('is written whole to a file of the device, and the repository '
          'says where it is', () async {
        final world = await aWorldOnDisk();

        final location = await world.documents.fetchContent(_document.id);

        expect(location, isA<Ok<DocumentLocation, RepositoryError>>());
        final where = (location as Ok<DocumentLocation, RepositoryError>).value;
        expect(File.fromUri(Uri.parse(where)).readAsBytesSync(), equals(_pdf));
        expect(
          await world.files.stat(world.files.nameOf(where) ?? ''),
          equals(ok(StoredFile(size: _pdf.length))),
        );
      });

      test('is named for the user the token belongs to, the document and the '
          'version, and for nothing else', () async {
        final world = await aSignedInWorld();
        serverSends(_pdf);

        final location = await world.documents.fetchContent(_document.id);

        final name = documentFileName(_user, _document.id, '"v1"');
        expect(location, equals(ok(world.files.uriOf(name))));
        expect(name, matches(RegExp(r'^[0-9a-f]{64}\.pdf$')));
        expect(name, isNot(contains(_document.id)));
      });

      test('asks for a PDF, with the token of the user read when the request '
          'was created, and keeps nothing', () async {
        final world = await aSignedInWorld();

        await world.documents.fetchContent(_document.id);

        final last = installed.received.length - 1;
        expect(
          installed.received.last,
          equals('GET $testApiUrl/documents/${_document.id}/content'),
        );
        expect(
          installed.receivedHeader(last, HttpHeader.accept.value),
          equals(mediaTypePdf),
        );
        expect(
          installed.receivedHeader(last, HttpHeader.cacheControl.value),
          equals(cacheControlNoStore),
        );
        expect(
          installed.receivedHeader(last, HttpHeader.authorization.value),
          matches(RegExp(r'^Bearer token-\d+$')),
        );
      });

      test('accepts the media type with parameters and in any case', () async {
        final world = await aSignedInWorld();
        serverSends(
          _pdf,
          headers: {
            ..._pdfHeaders,
            HttpHeader.contentType.value: 'Application/PDF; charset=binary',
          },
        );

        expect(
          await world.documents.fetchContent(_document.id),
          isA<Ok<DocumentLocation, RepositoryError>>(),
        );
      });

      test('replaces the file when the same version is downloaded again, at '
          'the same place', () async {
        final world = await aSignedInWorld();

        final first = await world.documents.fetchContent(_document.id);
        final second = await world.documents.fetchContent(_document.id);

        expect(second, equals(first));
        expect(await filesOf(world), hasLength(1));
      });

      test('is another file for another version, and for another '
          'user', () async {
        final world = await aSignedInWorld();
        final first = await world.documents.fetchContent(_document.id);

        world.load(
          ServerContent(
            meetings: [
              aMeeting(documents: [_document]),
            ],
            recordedVotes: const [],
          ),
        );
        final newer = await world.documents.fetchContent(_document.id);
        await world.signInAs(aUserId('user-2'));
        final other = await world.documents.fetchContent(_document.id);

        final locations = [
          for (final result in [first, newer, other])
            if (result case Ok(:final value)) value,
        ];
        expect(locations, hasLength(3));
        expect(locations.toSet(), hasLength(3));
      });
    });

    group('what is not a PDF', () {
      for (final (name, type) in [
        ('an HTML page', 'text/html; charset=utf-8'),
        ('JSON', 'application/json'),
        ('a stream of bytes', 'application/octet-stream'),
        ('nothing said', ''),
      ]) {
        test('is refused when the server sends $name, before it is read, and '
            'nothing is stored', () async {
          final world = await aSignedInWorld();
          serverSends(
            _pdf,
            headers: {
              HttpHeader.eTag.value: '"v1"',
              if (type.isNotEmpty) HttpHeader.contentType.value: type,
            },
          );

          final refused = await world.documents.fetchContent(_document.id);

          expect(refused, equals(err(unexpected('unexpected media type'))));
          expect(await filesOf(world), isEmpty);
        });
      }

      test('is refused when the bytes do not start with the signature of a '
          'PDF, though the server says they do', () async {
        final world = await aSignedInWorld();
        serverSends('<html><body>Please sign in</body></html>');

        final refused = await world.documents.fetchContent(_document.id);

        expect(refused, equals(err(unexpected('invalid response'))));
        expect(
          world.monitoring.capturedEvents(),
          equals([MonitoringEvent.responseInvalid]),
        );
        expect(
          world.monitoring.errors.first.attributes,
          equals({
            LogAttribute.resource: 'documentContent',
            LogAttribute.reason: 'wrongSignature',
          }),
        );
        expect(await filesOf(world), isEmpty);
      });

      test('is refused when the body is empty', () async {
        final world = await aSignedInWorld();
        serverSends(Uint8List(0));

        final refused = await world.documents.fetchContent(_document.id);

        expect(
          refused,
          isA<Err<DocumentLocation, RepositoryError>>().having(
            (result) => result.error.code,
            'code',
            equals(RepositoryErrorCode.unexpected.value),
          ),
        );
        expect(await filesOf(world), isEmpty);
      });

      for (final (name, etag) in <(String, String?)>[
        ('no version', null),
        ('an empty version', ''),
        ('a version with a space', 'has a space'),
        ('a version that is too long', 'v' * 257),
      ]) {
        test('is refused with $name, and nothing is stored', () async {
          final world = await aSignedInWorld();
          serverSends(
            _pdf,
            headers: {
              HttpHeader.contentType.value: mediaTypePdf,
              HttpHeader.eTag.value: ?etag,
            },
          );

          final refused = await world.documents.fetchContent(_document.id);

          expect(refused, equals(err(unexpected('invalid response'))));
          expect(
            world.monitoring.errors.last.attributes?[LogAttribute.reason],
            equals('noVersion'),
          );
          expect(await filesOf(world), isEmpty);
        });
      }
    });

    group('a file that is too big', () {
      const small = HttpDocumentRepositoryOptions(maxContentBytes: 2000);

      test('is refused, unread, when the server declares more than the '
          'maximum', () async {
        final world = await aSignedInWorld(
          const HttpWorldOptions(documents: small),
        );
        serverSends(
          _pdf,
          headers: {..._pdfHeaders, HttpHeader.contentLength.value: '2001'},
        );

        final refused = await world.documents.fetchContent(_document.id);

        expect(refused, equals(err(unexpected('response too large'))));
        expect(await filesOf(world), isEmpty);
      });

      test('is refused when a body that says nothing about its length grows '
          'past the maximum', () async {
        final world = await aSignedInWorld(
          const HttpWorldOptions(documents: small),
        );
        serverSends(_streamOf(5000));

        final refused = await world.documents.fetchContent(_document.id);

        expect(refused, equals(err(unexpected('response too large'))));
        expect(await filesOf(world), isEmpty);
      });

      test('is accepted when it is exactly the maximum', () async {
        final world = await aSignedInWorld(
          const HttpWorldOptions(documents: small),
        );
        serverSends(_streamOf(2000));

        expect(
          await world.documents.fetchContent(_document.id),
          isA<Ok<DocumentLocation, RepositoryError>>(),
        );
      });

      test('has a maximum of its own that is above the one of the JSON '
          'answers', () {
        expect(maxDocumentBytes, greaterThan(2 * 1024 * 1024));
      });
    });

    group('time', () {
      test('is bounded: a server that takes too long is a network that '
          'failed, and nothing is stored', () async {
        final world = await aSignedInWorld(
          HttpWorldOptions(
            documents: HttpDocumentRepositoryOptions(
              downloadTimeout: aDuration(50),
            ),
          ),
        );
        installed.conditions.delayMillis = 400;

        final refused = await world.documents.fetchContent(_document.id);

        expect(refused, equals(err(networkUnavailable())));
        expect(await filesOf(world), isEmpty);
      });

      test('is bounded when the body never ends, too', () async {
        final world = await aSignedInWorld(
          HttpWorldOptions(
            documents: HttpDocumentRepositoryOptions(
              downloadTimeout: aDuration(80),
            ),
          ),
        );
        final neverEnding = StreamController<Uint8List>();
        addTearDown(neverEnding.close);
        serverSends(neverEnding.stream);

        final refused = await world.documents.fetchContent(_document.id);

        expect(refused, equals(err(networkUnavailable())));
      });

      test('gets more time than a request of JSON when the download has a '
          'timeout of its own', () async {
        final world = await aSignedInWorld(
          HttpWorldOptions(
            clientTimeout: aDuration(50),
            documents: HttpDocumentRepositoryOptions(
              downloadTimeout: aDuration(2000),
            ),
          ),
        );
        installed.conditions.delayMillis = 200;

        expect(
          await world.documents.fetchContent(_document.id),
          isA<Ok<DocumentLocation, RepositoryError>>(),
        );
      });
    });

    group('a server that refuses', () {
      for (final (status, error) in <(int, RepositoryError)>[
        (HttpStatusCode.unauthorized.code, unauthorized()),
        (HttpStatusCode.forbidden.code, forbidden()),
        (HttpStatusCode.notFound.code, notFound()),
        (HttpStatusCode.serviceUnavailable.code, networkUnavailable()),
        (HttpStatusCode.tooManyRequests.code, networkUnavailable()),
        (HttpStatusCode.internalServerError.code, unexpected('status 500')),
        (HttpStatusCode.unprocessableContent.code, unexpected('status 422')),
      ]) {
        test('answers the error of the status $status, and stores '
            'nothing', () async {
          final world = await aSignedInWorld();
          serverSends(
            '{"error":{"code":"nope"}}',
            status: status,
            headers: {HttpHeader.contentType.value: mediaTypeJson},
          );

          final refused = await world.documents.fetchContent(_document.id);

          expect(refused, equals(err(error)));
          expect(await filesOf(world), isEmpty);
        });
      }

      test('answers unauthorized when the API does not know the token, '
          'forbidden for a document the user may not have, and notFound for '
          'one that is not there', () async {
        final world = await aSignedInWorld();

        world.load(const ServerContent(meetings: [], recordedVotes: []));
        expect(
          await world.documents.fetchContent(_document.id),
          equals(err(notFound())),
        );

        world.load(
          ServerContent(
            meetings: [
              aMeeting(documents: [_document], participants: []),
            ],
            recordedVotes: const [],
          ),
        );
        expect(
          await world.documents.fetchContent(_document.id),
          equals(err(forbidden())),
        );

        world.api.revokeSessions();
        expect(
          await world.documents.fetchContent(_document.id),
          equals(err(unauthorized())),
        );
      });

      test('does not send the request, and answers unauthorized, when nobody '
          'is signed in', () async {
        final world = await aSignedInWorld();
        await world.auth.signOut();
        installed.received.clear();

        final refused = await world.documents.fetchContent(_document.id);

        expect(refused, equals(err(unauthorized())));
        expect(installed.received, isEmpty);
      });
    });

    group('a device that cannot keep the file', () {
      test('answers unexpected with a cause that says nothing of the file, '
          'and tells the monitoring with the code only', () async {
        final device = aDocumentDevice(filesParent);
        final world = await aSignedInWorld(
          HttpWorldOptions(server: TestServerOptions(files: device.store)),
        );
        device.volume.fail(VolumeCall.write, true);

        final refused = await world.documents.fetchContent(_document.id);

        expect(refused, equals(err(unexpected('content not stored'))));
        expect(
          world.monitoring.capturedEvents(),
          equals([MonitoringEvent.documentContentNotStored]),
        );
        expect(
          world.monitoring.errors.first.error,
          equals(storageWriteFailed('os error 5')),
        );
        expect(
          world.monitoring.errors.first.attributes,
          equals({
            LogAttribute.resource: 'documentContent',
            LogAttribute.documentId: _document.id,
          }),
        );
        expect(await filesOf(world), isEmpty);
      });

      test('leaves the previous file as it was when the new one cannot be '
          'put in its place', () async {
        final device = aDocumentDevice(filesParent, realLocations: true);
        final world = await aSignedInWorld(
          HttpWorldOptions(server: TestServerOptions(files: device.store)),
        );
        final first = await world.documents.fetchContent(_document.id);
        device.volume.fail(VolumeCall.move, true);

        final refused = await world.documents.fetchContent(_document.id);

        expect(refused, isA<Err<DocumentLocation, RepositoryError>>());
        expect(await filesOf(world), hasLength(1));
        expect(
          File.fromUri(Uri.parse((first as Ok).value as String))
              .readAsBytesSync(),
          equals(_pdf),
        );
      });
    });

    group('what the errors and the logs hold', () {
      test('is never an address, a path, a name, the token or the '
          'title', () async {
        final world = await aSignedInWorld(
          const HttpWorldOptions(
            documents: HttpDocumentRepositoryOptions(maxContentBytes: 100),
          ),
        );
        final tooBig = await world.documents.fetchContent(_document.id);
        serverSends('<html>');
        final notAPdf = await world.documents.fetchContent(_document.id);

        final everything =
            '$tooBig $notAPdf ${world.monitoring.errors} '
            '${world.monitoring.logs}';

        expect(everything, isNot(contains(testApiUrl)));
        expect(everything, isNot(contains('api.boardroom')));
        expect(everything, isNot(contains(_document.title)));
        expect(
          everything,
          isNot(matches(RegExp(r'token-\d|Bearer|file://|\.pdf'))),
        );
      });
    });
  });

  group('HttpDocumentRepository, over dio', () {
    test('writes a download that the server sends in pieces', () async {
      final world = await aWorldOnDisk();
      serverSends(
        Stream.fromIterable([
          _pdf.sublist(0, 10),
          _pdf.sublist(10, 40),
          _pdf.sublist(40),
        ]),
      );

      final location = await world.documents.fetchContent(_document.id);

      final where = (location as Ok<DocumentLocation, RepositoryError>).value;
      expect(File.fromUri(Uri.parse(where)).readAsBytesSync(), equals(_pdf));
    });

    test('refuses the metadata of a document that the server cannot send as '
        'JSON', () async {
      final world = await aSignedInWorld();
      serverSends(
        'not json',
        headers: {HttpHeader.contentType.value: mediaTypeJson},
      );

      expect(
        await world.documents.get(_document.id),
        equals(err(unexpected('invalid response'))),
      );
      expect(
        world.monitoring.errors.single.attributes?[LogAttribute.issuePaths],
        equals(r'$'),
      );
    });
  });
}
