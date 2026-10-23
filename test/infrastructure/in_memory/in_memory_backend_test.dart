import 'package:boardroom/domain/entities/document.dart';
import 'package:boardroom/domain/entities/meeting.dart';
import 'package:boardroom/domain/entities/meeting_summary.dart';
import 'package:boardroom/domain/entities/participant.dart';
import 'package:boardroom/domain/entities/resolution.dart';
import 'package:boardroom/domain/entities/user.dart';
import 'package:boardroom/domain/entities/vote.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/domain/value_objects/ids.dart';
import 'package:boardroom/domain/value_objects/meeting_period.dart';
import 'package:boardroom/domain/value_objects/page.dart';
import 'package:boardroom/domain/value_objects/page_cursor.dart';
import 'package:boardroom/domain/value_objects/page_request.dart';
import 'package:boardroom/domain/value_objects/vote_choice.dart';
import 'package:boardroom/infrastructure/documents/store_document_content.dart';
import 'package:boardroom/infrastructure/files/file_store.dart';
import 'package:boardroom/infrastructure/in_memory/in_memory_backend.dart';
import 'package:boardroom/infrastructure/in_memory/simulated_network.dart';
import 'package:boardroom/infrastructure/pdf/pdf_signature.dart';
import 'package:test/test.dart';

import '../../application/support/fake_auth_session.dart';
import '../../application/support/fake_clock.dart';
import '../../domain/support/builders.dart';
import '../support/sleep.dart';
import '../support/test_server.dart';

final User _bruno = aUser(id: aUserId('user-2'));
final UserId _outsider = aUserId('user-9');

PageRequest _request(int limit, [String? cursor]) =>
    unwrap<PageRequest, ValidationError>(
      createPageRequest(
        limit: limit,
        cursor: cursor == null ? null : unwrap(parsePageCursor(cursor)),
      ),
    );

/// A meeting with one resolution, of the given id.
Meeting _meetingAtWithResolution(String id, String resolutionId) => aMeeting(
  summary: aMeetingSummary(
    id: aMeetingId(id),
    title: 'Meeting $id',
    scheduledAt: at(millisPerDay),
  ),
  agenda: [
    anAgendaItem(
      id: anAgendaItemId('agenda-$id'),
      resolution: aResolution(id: aResolutionId(resolutionId)),
    ),
  ],
);

Meeting _meetingAt(
  String id,
  int millisFromNow, [
  List<Participant>? participants,
]) => aMeeting(
  summary: aMeetingSummary(
    id: aMeetingId(id),
    title: 'Meeting $id',
    scheduledAt: at(millisFromNow),
  ),
  // Resolution ids are unique across meetings, and these meetings need no
  // agenda.
  agenda: [],
  participants: participants ?? [aParticipant()],
);

ServerContent _content(
  List<Meeting> meetings, [
  List<Vote> recordedVotes = const [],
]) => ServerContent(meetings: meetings, recordedVotes: recordedVotes);

List<String> _ids(Result<Page<MeetingSummary>, GatewayError> page) =>
    unwrap(page).items.map((summary) => summary.id).toList();

Resolution? _resolutionOf(Result<Meeting, RepositoryError> meeting) =>
    findResolution(unwrap(meeting), aResolutionId());

void main() {
  group('InMemoryBackend', () {
    group('who sees what', () {
      test('lists to a user the meetings they take part in only', () async {
        final server = createTestServer(
          TestServerOptions(
            content: _content([
              _meetingAt('mine', millisPerDay),
              _meetingAt('theirs', 2 * millisPerDay, [
                aParticipant(
                  userId: aUserId('user-2'),
                  fullName: 'Bruno Durand',
                ),
              ]),
            ]),
          ),
        );

        final mine = await server.backend.listMeetings(
          MeetingPeriod.upcoming,
          _request(10),
        );
        server.auth.openSessionFor(_bruno);
        final theirs = await server.backend.listMeetings(
          MeetingPeriod.upcoming,
          _request(10),
        );

        expect(_ids(mine), equals(['mine']));
        expect(_ids(theirs), equals(['theirs']));
      });

      test('refuses a meeting the user is not invited to with forbidden, '
          'and one that does not exist with notFound', () async {
        final server = createTestServer(
          TestServerOptions(
            content: _content([_meetingAt('mine', millisPerDay)]),
          ),
        );
        server.auth.openSessionFor(aUser(id: _outsider));

        expect(
          await server.backend.getMeeting(aMeetingId('mine')),
          equals(err(forbidden())),
        );
        expect(
          await server.backend.getMeeting(aMeetingId('unknown')),
          equals(err(notFound())),
        );
      });

      test('refuses a document of a meeting the user is not part of '
          'with forbidden, one that no meeting lists with notFound', () async {
        final hidden = aConfidentialDocument(id: aDocumentId('hidden'));
        final server = createTestServer()
          ..load(
            _content([
              aMeeting(
                summary: aMeetingSummary(id: aMeetingId('theirs')),
                agenda: [],
                documents: [hidden],
                participants: [aParticipant(userId: aUserId('user-2'))],
              ),
              aMeeting(documents: [aDocument()]),
            ]),
          );

        expect(
          await server.backend.getDocument(hidden.id),
          equals(err(forbidden())),
        );
        expect(
          await server.backend.fetchDocumentContent(hidden.id),
          equals(err(forbidden())),
        );
        expect(
          await server.backend.getDocument(aDocumentId('unknown')),
          equals(err(notFound())),
        );
        expect(
          await server.backend.getDocument(aDocument().id),
          isA<Ok<Document, RepositoryError>>(),
        );
      });

      test('lets a document that two meetings list be had by a user '
          'who is in one of them', () async {
        final shared = aDocument(id: aDocumentId('shared'));
        final server = createTestServer()
          ..load(
            _content([
              aMeeting(
                summary: aMeetingSummary(id: aMeetingId('theirs')),
                agenda: [],
                documents: [shared],
                participants: [aParticipant(userId: aUserId('user-2'))],
              ),
              aMeeting(documents: [shared]),
            ]),
          );

        expect(
          await server.backend.getDocument(shared.id),
          isA<Ok<Document, RepositoryError>>(),
        );
      });

      test('treats a session whose expiry has passed as no session: '
          'unauthorized', () async {
        final server = createTestServer();

        server.clock.advance(millisPerHour);

        expect(
          await server.backend.getMeeting(aMeetingId()),
          equals(err(unauthorized())),
        );
        expect(
          await server.backend.listMeetings(
            MeetingPeriod.upcoming,
            _request(5),
          ),
          equals(err(unauthorized())),
        );
        expect(
          await server.backend.submitVote(aVote()),
          equals(err(unauthorized())),
        );
      });

      test('serves whoever signs in next with their own view', () async {
        final server = createTestServer(
          const TestServerOptions(signedIn: false),
        );
        final [alice, bruno] = server.accounts;
        server.auth.openSessionFor(alice.user);
        expect(
          await server.backend.submitVote(aVote()),
          equals(ok<void>(null)),
        );

        server.auth.openSessionFor(bruno.user);

        expect(
          await server.backend.submitVote(aVote()),
          equals(err(unauthorized())),
        );
      });
    });

    group('the content it accepts', () {
      Meeting twinOf(String id) =>
          _meetingAtWithResolution(id, 'resolution-shared');

      test('refuses, on creation, two meetings that share a resolution id: '
          'resolution ids are globally unique', () {
        final server = createTestServer();

        final created = InMemoryBackend.create(
          InMemoryBackendOptions(
            clock: server.clock,
            auth: AuthSessionCaller(server.auth),
            network: server.network,
            content: _content([twinOf('first'), twinOf('second')]),
          ),
        );

        expect(
          created,
          equals(
            err(
              ServerContentError(
                code: ServerContentErrorCode.duplicateResolutionId,
                resolutionId: aResolutionId('resolution-shared'),
              ),
            ),
          ),
        );
      });

      test(
        'refuses the same on a replacement, and keeps what it held',
        () async {
          final server = createTestServer();
          await server.backend.submitVote(aVote());

          final replaced = server.backend.replaceContent(
            _content([twinOf('first'), twinOf('second')]),
          );

          expect(replaced, isA<Err<void, ServerContentError>>());
          expect(
            (replaced as Err<void, ServerContentError>).error.code,
            equals(ServerContentErrorCode.duplicateResolutionId),
          );
          expect(
            await server.backend.getMeeting(aMeetingId()),
            isA<Ok<Meeting, RepositoryError>>(),
          );
          expect(server.backend.recordedVotes(), hasLength(1));
        },
      );

      test('accepts meetings with distinct resolution ids, '
          'and a meeting without resolutions', () {
        final server = createTestServer();

        expect(
          server.backend.replaceContent(
            _content([
              twinOf('first'),
              _meetingAtWithResolution('second', 'resolution-other'),
              _meetingAt('third', 0),
            ]),
          ),
          isA<Ok<void, ServerContentError>>(),
        );
      });

      test('does not take a vote held for another meeting under the same key '
          'for the vote it is sent', () async {
        // Cannot happen with unique resolution ids; the safeguard is that it is
        // not acknowledged.
        final server = createTestServer(
          TestServerOptions(
            content: _content(
              [aMeetingWithAgenda()],
              [aVote(meetingId: aMeetingId('another-meeting'))],
            ),
          ),
        );

        final result = await server.backend.submitVote(aVote());

        expect(result, isA<Err<void, AppError>>());
        expect(server.backend.recordedVotes(), hasLength(1));
      });
    });

    group('the requests it validates', () {
      // The page limit of Dart is an `int`: the React Native cases 1.5 and NaN
      // cannot be written.
      for (final limit in [0, -1, 51]) {
        test('refuses a page limit of $limit, '
            'which the domain does not accept', () async {
          final server = createTestServer();

          final result = await server.backend.listMeetings(
            MeetingPeriod.upcoming,
            PageRequest(limit: limit),
          );

          expect(
            (result as Err<Page<MeetingSummary>, GatewayError>).error.code,
            equals(RepositoryErrorCode.unexpected.value),
          );
        });
      }

      for (final (name, cursor) in <(String, String)>[
        ('an exponent', '1e3:a'),
        ('a hexadecimal instant', '0x10:a'),
        ('a space after the instant', '5 :a'),
        ('a negative instant', '-5:a'),
        ('a leading zero', '05:a'),
        ('a fractional instant', '5.5:a'),
        ('an extra segment', '5:a:b'),
        ('an empty id', '5:'),
        ('no separator', '5'),
        ('no instant', ':a'),
        ('an instant too large to be exact', '99999999999999999999:a'),
        ('a malformed escape sequence', '5:%E0%A4%A'),
      ]) {
        test('refuses a cursor with $name', () async {
          final server = createTestServer();

          final result = await server.backend.listMeetings(
            MeetingPeriod.upcoming,
            _request(5, cursor),
          );

          expect(
            (result as Err<Page<MeetingSummary>, GatewayError>).error.code,
            equals(RepositoryErrorCode.unexpected.value),
          );
        });
      }

      test('reads the cursors it writes back, for ids that contain '
          'the separator and other special characters', () async {
        final ids = ['a:b', 'c/d', 'e%20f', 'g h'];
        final server = createTestServer(
          TestServerOptions(
            content: _content([
              for (final (index, id) in ids.indexed)
                _meetingAt(id, (index + 1) * millisPerDay),
            ]),
          ),
        );

        final seen = <String>[];
        String? cursor;
        do {
          final page = unwrap(
            await server.backend.listMeetings(
              MeetingPeriod.upcoming,
              _request(1, cursor),
            ),
          );
          seen.addAll(page.items.map((summary) => summary.id));
          cursor = page.nextCursor;
        } while (cursor != null);

        expect(seen, equals(ids));
      });
    });

    group('the identity of a request', () {
      test('is the one read when the request was created: '
          'a vote is recorded for the user who cast it', () async {
        late final TestServer server;
        server = createTestServer(
          TestServerOptions(
            sleep: (millis) {
              server.auth.openSessionFor(_bruno);
              return Future.value();
            },
          ),
        );
        server.network.setLatency(aDuration(1));

        final result = await server.backend.submitVote(aVote());

        expect(result, equals(ok<void>(null)));
        expect(
          server.backend.recordedVotes().map((vote) => vote.voterId),
          equals([aUserId()]),
        );
      });

      test('never answers with the view of a user who signed in '
          'while it was on its way', () async {
        late final TestServer server;
        server = createTestServer(
          TestServerOptions(
            content: _content(
              [
                aMeetingWithAgenda(
                  participants: [
                    aParticipant(),
                    aParticipant(
                      userId: aUserId('user-2'),
                      fullName: 'Bruno Durand',
                    ),
                  ],
                ),
              ],
              [aVote(choice: VoteChoice.against)],
            ),
            sleep: (millis) {
              server.auth.openSessionFor(_bruno);
              return Future.value();
            },
          ),
        );
        server.network.setLatency(aDuration(1));

        final meeting = await server.backend.getMeeting(aMeetingId());

        expect(
          _resolutionOf(meeting)?.recordedVote,
          equals(VoteChoice.against),
        );
      });

      test('refuses a request created when nobody was signed in, '
          'though somebody signs in meanwhile', () async {
        late final TestServer server;
        server = createTestServer(
          TestServerOptions(
            signedIn: false,
            sleep: (millis) {
              server.auth.openSessionFor(aUser());
              return Future.value();
            },
          ),
        );
        server.network.setLatency(aDuration(1));

        expect(
          await server.backend.submitVote(aVote()),
          equals(err(unauthorized())),
        );
        expect(server.backend.recordedVotes(), isEmpty);
      });

      test('answers unauthorized to nobody signed in even without a '
          'connection: the client has no token to send', () async {
        final server = createTestServer(
          const TestServerOptions(signedIn: false),
        );
        server.network.setOnline(online: false);

        expect(
          await server.backend.getMeeting(aMeetingId()),
          equals(err(unauthorized())),
        );
      });
    });

    group('the downloads', () {
      test('are located per user: two users never share a location', () async {
        final server = createTestServer(
          TestServerOptions(
            content: _content([
              aMeeting(documents: [aDocument()]),
            ]),
          ),
        );
        final first = unwrap(
          await server.backend.fetchDocumentContent(aDocument().id),
        );
        server.auth.openSessionFor(_bruno);
        final second = unwrap(
          await server.backend.fetchDocumentContent(aDocument().id),
        );

        expect(
          documentFileName(first.userId, aDocument().id, first.version),
          isNot(
            equals(
              documentFileName(second.userId, aDocument().id, second.version),
            ),
          ),
        );
      });

      test('are located per version of the content: '
          'serving the content again changes the location', () async {
        final content = _content([
          aMeeting(documents: [aDocument()]),
        ]);
        final server = createTestServer(TestServerOptions(content: content));
        final first = unwrap(
          await server.backend.fetchDocumentContent(aDocument().id),
        );
        server.load(content);
        final second = unwrap(
          await server.backend.fetchDocumentContent(aDocument().id),
        );

        expect(
          documentFileName(first.userId, aDocument().id, first.version),
          isNot(
            equals(
              documentFileName(second.userId, aDocument().id, second.version),
            ),
          ),
        );
      });

      test('are located by encoded parts, so that ids that contain '
          'a separator cannot share a location', () async {
        final first = aDocument(id: aDocumentId('a/b'));
        final second = aDocument(id: aDocumentId('a%2Fb'));
        final server = createTestServer(
          TestServerOptions(
            content: _content([
              aMeeting(documents: [first, second]),
            ]),
          ),
        );

        final served = [
          unwrap(await server.backend.fetchDocumentContent(first.id)),
          unwrap(await server.backend.fetchDocumentContent(second.id)),
        ];
        final locations = {
          documentFileName(served[0].userId, first.id, served[0].version),
          documentFileName(served[1].userId, second.id, served[1].version),
        };

        expect(locations, hasLength(2));
      });
    });

    group('the lists', () {
      test('puts a meeting scheduled at the very instant of the clock '
          'among the past ones', () async {
        final server = createTestServer(
          TestServerOptions(
            content: _content([_meetingAt('now', 0), _meetingAt('later', 1)]),
          ),
        );

        final upcoming = await server.backend.listMeetings(
          MeetingPeriod.upcoming,
          _request(5),
        );
        final past = await server.backend.listMeetings(
          MeetingPeriod.past,
          _request(5),
        );

        expect(_ids(upcoming), equals(['later']));
        expect(_ids(past), equals(['now']));
      });

      test('moves a meeting to the past list when the clock passes it, '
          'and keeps a cursor valid meanwhile', () async {
        final server = createTestServer(
          TestServerOptions(
            content: _content([
              _meetingAt('u1', millisPerDay),
              _meetingAt('u2', 2 * millisPerDay),
              _meetingAt('u3', 3 * millisPerDay),
            ]),
          ),
        );
        final first = await server.backend.listMeetings(
          MeetingPeriod.upcoming,
          _request(1),
        );
        final cursor = unwrap(first).nextCursor;

        // The first meeting begins while the user is reading the first page.
        server.clock.advance(millisPerDay + 1);
        server.auth.openSessionFor(aUser());
        final second = await server.backend.listMeetings(
          MeetingPeriod.upcoming,
          PageRequest(limit: 1, cursor: cursor),
        );

        expect(_ids(second), equals(['u2']));
      });

      test('answers unexpected, with a cause free of any query value, '
          'to a cursor it did not build', () async {
        final server = createTestServer();

        final result = await server.backend.listMeetings(
          MeetingPeriod.upcoming,
          _request(5, 'garbage'),
        );

        expect(result, isA<Err<Page<MeetingSummary>, GatewayError>>());
        final error = (result as Err<Page<MeetingSummary>, GatewayError>).error;
        expect(error.code, equals(RepositoryErrorCode.unexpected.value));
        expect('$error ${error.payload}', isNot(contains('garbage')));
      });

      test(
        'answers an empty page for a cursor past the end of the list',
        () async {
          final server = createTestServer(
            TestServerOptions(
              content: _content([_meetingAt('u1', millisPerDay)]),
            ),
          );

          final result = await server.backend.listMeetings(
            MeetingPeriod.upcoming,
            _request(5, '${at(10 * millisPerDay)}:zzz'),
          );

          expect(result, equals(ok(createPage<MeetingSummary>(const []))));
        },
      );

      test('breaks a tie between two meetings at the same instant by id, '
          'so a page boundary between them is stable', () async {
        final server = createTestServer(
          TestServerOptions(
            content: _content([
              _meetingAt('b', millisPerDay),
              _meetingAt('a', millisPerDay),
            ]),
          ),
        );

        final first = await server.backend.listMeetings(
          MeetingPeriod.upcoming,
          _request(1),
        );
        final cursor = unwrap(first).nextCursor;
        final second = await server.backend.listMeetings(
          MeetingPeriod.upcoming,
          PageRequest(limit: 1, cursor: cursor),
        );

        expect(_ids(first), equals(['a']));
        expect(_ids(second), equals(['b']));
      });
    });

    group('votes', () {
      test('shows the user the vote they recorded on the resolution, '
          'and nobody else', () async {
        final server = createTestServer(
          TestServerOptions(
            content: _content([
              aMeetingWithAgenda(
                participants: [
                  aParticipant(),
                  aParticipant(
                    userId: aUserId('user-2'),
                    fullName: 'Bruno Durand',
                  ),
                ],
              ),
            ]),
          ),
        );
        await server.backend.submitVote(aVote(choice: VoteChoice.against));

        final mine = await server.backend.getMeeting(aMeetingId());
        server.auth.openSessionFor(_bruno);
        final theirs = await server.backend.getMeeting(aMeetingId());

        expect(_resolutionOf(mine)?.recordedVote, equals(VoteChoice.against));
        expect(_resolutionOf(theirs)?.recordedVote, isNull);
      });

      test('shows the votes it was seeded with to their voter', () async {
        final seeded = aVote(choice: VoteChoice.abstain);
        final server = createTestServer(
          TestServerOptions(
            content: _content([aMeetingWithAgenda()], [seeded]),
          ),
        );

        final meeting = await server.backend.getMeeting(aMeetingId());

        expect(
          _resolutionOf(meeting)?.recordedVote,
          equals(VoteChoice.abstain),
        );
        expect(
          await server.backend.submitVote(aVote()),
          equals(
            err(const AlreadyVotedError(source: AlreadyVotedSource.recorded)),
          ),
        );
      });

      test(
        'stamps the vote with its own time, never the castAt of the device',
        () async {
          final server = createTestServer();
          server.clock.advance(1234);

          await server.backend.submitVote(aVote(castAt: at(-5 * millisPerDay)));

          expect(
            server.backend.recordedVotes().map((vote) => vote.castAt),
            equals([at(1234)]),
          );
        },
      );

      test('records the vote under the key it derives, '
          'not the one the device sent', () async {
        final server = createTestServer();
        final forged = aVote().copyWith(
          idempotencyKey: aVote(resolutionId: aResolutionId('forged'))
              .idempotencyKey,
        );

        await server.backend.submitVote(forged);
        final again = await server.backend.submitVote(forged);

        expect(again, equals(ok<void>(null)));
        expect(
          server.backend.recordedVotes().map((vote) => vote.idempotencyKey),
          equals([idempotencyKeyOf(aResolutionId(), aUserId())]),
        );
      });

      test('is shared by the repositories: replacing the content '
          'forgets the votes', () async {
        final server = createTestServer();
        await server.backend.submitVote(aVote());

        server.load(_content([aMeetingWithAgenda()]));

        expect(server.backend.recordedVotes(), isEmpty);
        expect(
          await server.backend.submitVote(aVote(choice: VoteChoice.against)),
          equals(ok<void>(null)),
        );
      });
    });

    group('content', () {
      test('writes the content of a downloaded document to the files of the '
          'device, as a PDF', () async {
        final server = createTestServer(
          TestServerOptions(
            content: _content([
              aMeeting(documents: [aDocument()]),
            ]),
          ),
        );

        final location = await server.documents.fetchContent(aDocument().id);

        final name = switch (location) {
          Ok(:final value) => server.files.nameOf(value),
          Err() => null,
        };
        expect(name, isNotNull);
        expect(
          await server.files.stat(name!),
          isA<Ok<StoredFile?, FileStoreFailure>>().having(
            (stat) => stat.value?.size,
            'size',
            isA<int>(),
          ),
        );
      });

      test('does not store anything when the download fails', () async {
        final server = createTestServer(
          TestServerOptions(
            content: _content([
              aMeeting(documents: [aDocument()]),
            ]),
          ),
        );
        server.network.setOnline(online: false);

        final location = await server.documents.fetchContent(aDocument().id);

        expect(isErr(location), isTrue);
        expect(await server.files.list(), equals(ok(<String>[])));
      });

      test('serves a PDF with the pages of the document, '
          'made for the user and the version', () async {
        final server = createTestServer(
          TestServerOptions(
            content: _content([
              aMeeting(
                documents: [aDocument(title: 'Annual report', pageCount: 7)],
              ),
            ]),
          ),
        );

        final served = unwrap(
          await server.backend.fetchDocumentContent(aDocument().id),
        );

        expect(hasPdfSignature(served.bytes), isTrue);
        expect(served.userId, equals(aUserId()));
        expect(String.fromCharCodes(served.bytes), contains('/Count 7'));
      });

      test('serves another version when the content is replaced, '
          'and the same one while it is not', () async {
        final server = createTestServer(
          TestServerOptions(
            content: _content([
              aMeeting(documents: [aDocument()]),
            ]),
          ),
        );
        final first = unwrap(
          await server.backend.fetchDocumentContent(aDocument().id),
        );
        final again = unwrap(
          await server.backend.fetchDocumentContent(aDocument().id),
        );

        server.load(
          _content([
            aMeeting(documents: [aDocument()]),
          ]),
        );
        final replaced = unwrap(
          await server.backend.fetchDocumentContent(aDocument().id),
        );

        expect(again.version, equals(first.version));
        expect(replaced.version, isNot(equals(first.version)));
      });

      test('serves no content for a document that is not there', () async {
        final server = createTestServer(
          TestServerOptions(
            content: _content([
              aMeeting(documents: [aDocument()]),
            ]),
          ),
        );

        expect(
          await server.backend.fetchDocumentContent(aDocumentId('nowhere')),
          equals(err(notFound())),
        );
      });

      test('hands out copies: changing an answer '
          'does not change the server', () async {
        // The entities of Dart are immutable: the lists of an answer cannot be
        // changed, and trying to leaves the server as it was.
        final server = createTestServer(
          TestServerOptions(
            content: _content([
              aMeeting(documents: [aDocument()]),
            ]),
          ),
        );
        final meeting = unwrap(await server.backend.getMeeting(aMeetingId()));
        final page = unwrap(
          await server.backend.listMeetings(
            MeetingPeriod.upcoming,
            _request(5),
          ),
        );

        expect(meeting.participants.clear, throwsUnsupportedError);
        expect(page.items.clear, throwsUnsupportedError);

        final again = unwrap(await server.backend.getMeeting(aMeetingId()));
        expect(again.title, equals(aMeeting().title));
        expect(again.participants, hasLength(aMeeting().participants.length));
        final documentAgain = unwrap(
          await server.backend.getDocument(aDocument().id),
        );
        expect(documentAgain.title, equals(aDocument().title));
        expect(
          documentAgain.confidentiality,
          equals(ConfidentialityLevel.internal),
        );
      });

      test('copies the content it is given: changing it afterwards '
          'does not change the server', () async {
        final meetings = [aMeeting()];
        final server = createTestServer(
          TestServerOptions(content: _content(meetings)),
        );

        meetings.clear();

        final held = unwrap(await server.backend.getMeeting(aMeetingId()));
        expect(held.title, equals(aMeeting().title));
      });
    });

    group('the network', () {
      test('waits for the latency once per request, '
          'through the sleep it was given', () async {
        final (:sleep, :requested) = recordingSleep();
        final server = createTestServer(TestServerOptions(sleep: sleep));
        server.network.setLatency(aDuration(300));

        await server.backend.listMeetings(MeetingPeriod.upcoming, _request(5));
        await server.backend.getMeeting(aMeetingId());
        await server.backend.submitVote(aVote());

        expect(requested, equals([300, 300, 300]));
      });

      test('is the network every client of the server goes through: '
          'going offline cuts them all', () async {
        final server = createTestServer();
        server.backend.network.setOnline(online: false);

        final results = [
          await server.backend.getMeeting(aMeetingId()),
          await server.backend.submitVote(aVote()),
        ];

        expect(
          results.map(
            (result) => (result as Err<Object?, AppError>).error.code,
          ),
          equals(['networkUnavailable', 'networkUnavailable']),
        );
      });
    });
  });

  group('InMemoryBackend, in Dart', () {
    InMemoryBackend backendOf(Caller auth, FakeClock clock) {
      final network = SimulatedNetwork(
        sleep: immediateSleep,
        latency: aDuration(0),
      );
      return unwrap(
        InMemoryBackend.create(
          InMemoryBackendOptions(
            clock: clock,
            auth: auth,
            network: network,
            content: _content([aMeetingWithAgenda()]),
          ),
        ),
      );
    }

    test('knows the caller from the session stored on the device', () async {
      final auth = FakeAuthSession();
      final backend = backendOf(AuthSessionCaller(auth), FakeClock());

      expect(
        await backend.getMeeting(aMeetingId()),
        isA<Ok<Meeting, RepositoryError>>(),
      );
      auth.session = null;
      expect(
        await backend.getMeeting(aMeetingId()),
        equals(err(unauthorized())),
      );
    });

    test(
      'takes a session that cannot be read for nobody: unauthorized',
      () async {
        final auth = FakeAuthSession()
          ..readFailure = const StorageReadFailedError();
        final backend = backendOf(AuthSessionCaller(auth), FakeClock());

        expect(
          await backend.getMeeting(aMeetingId()),
          equals(err(unauthorized())),
        );
      },
    );

    test(
      'compares and prints the content it holds without its bytes',
      () async {
        final server = createTestServer(
          TestServerOptions(
            content: _content([
              aMeeting(documents: [aDocument()]),
            ]),
          ),
        );
        final first = unwrap(
          await server.backend.fetchDocumentContent(aDocument().id),
        );
        final second = unwrap(
          await server.backend.fetchDocumentContent(aDocument().id),
        );

        expect(first, equals(second));
        expect(first.hashCode, equals(second.hashCode));
        expect(first.toString(), contains('version: ${first.version}'));
        expect(_content([aMeeting()]), equals(_content([aMeeting()])));
        expect(_content([aMeeting()]).toString(), contains('1 meetings'));
      },
    );
  });
}
