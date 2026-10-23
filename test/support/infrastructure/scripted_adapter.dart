import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

// Test support, not production code: a dio adapter that answers what the test
// scripted, one answer per request, and remembers the requests and how their
// answers were read. It is the counterpart of the scripted `fetch` of the React
// Native tests of the HTTP client: the client itself is tested against it, the
// adapters against the fixture server.

/// How many turns of the event loop a paced chunk waits: more than the few
/// dio takes between the headers and the moment the client has the answer.
const int _pacedTurns = 10;

/// What the adapter does with a request.
enum _Kind { response, fails, never, brokenBody }

/// One scripted answer.
final class ScriptedAnswer {
  /// An answer with a status, headers and a body, as text or as chunks.
  const new({
    this.status = 200,
    this.headers = const {},
    this.text,
    this.chunks,
    this.paced = false,
  }) : _kind = _Kind.response,
       _failure = null;

  /// A request that does not go through: the adapter throws [failure].
  const new fails(Object failure)
    : _kind = _Kind.fails,
      _failure = failure,
      status = 0,
      headers = const {},
      text = null,
      chunks = null,
      paced = false;

  /// A server that never answers. It ignores the cancellation, as a platform
  /// that does not honour it would.
  const new never()
    : _kind = _Kind.never,
      _failure = null,
      status = 0,
      headers = const {},
      text = null,
      chunks = null,
      paced = false;

  /// An answer whose body breaks while it is being read.
  const new brokenBody()
    : _kind = _Kind.brokenBody,
      _failure = null,
      status = 200,
      headers = const {},
      text = null,
      chunks = null,
      paced = false;

  final _Kind _kind;
  final Object? _failure;

  /// The status of the answer.
  final int status;

  /// The headers of the answer.
  final Map<String, String> headers;

  /// The body as text, in one chunk.
  final String? text;

  /// The body as chunks. Wins over [text].
  final List<Uint8List>? chunks;

  /// Whether each chunk comes some turns of the event loop after the one before
  /// (and after the headers). dio starts reading a body as soon as it has the
  /// headers, so only a body that is paced lets a test tell what the client
  /// read from what the client left alone: a decision the client takes in the
  /// turn it gets the answer comes before the first chunk.
  final bool paced;
}

/// A request the adapter received.
final class SentRequest {
  /// Creates the record of a request.
  new(this.options, this.body);

  /// The options dio gave the adapter.
  final RequestOptions options;

  /// The body, as the server would read it, or `null` when there was none.
  final String? body;

  /// Whether the client cancelled the request.
  bool cancelled = false;

  /// The address as the server would read it.
  String get url => options.uri.toString();

  /// The method of the request.
  String get method => options.method;

  /// The headers, with their names in lower case.
  Map<String, String> get headers => {
    for (final entry in options.headers.entries)
      entry.key.toLowerCase(): '${entry.value}',
  };

  /// A header, whatever the case of its name.
  String? header(String name) => headers[name.toLowerCase()];
}

/// How the bodies of the answers were read.
final class Reading {
  /// How many streams were opened (dio opens the body of every answer).
  int streamsOpened = 0;

  /// How many chunks were read.
  int chunksRead = 0;

  /// Whether a stream was abandoned before its end.
  bool cancelled = false;
}

/// The adapter.
final class ScriptedAdapter implements HttpClientAdapter {
  /// Creates an adapter that gives [answers] in turn, and repeats the last one.
  /// Without any, it answers an empty 200.
  new([List<ScriptedAnswer> answers = const []]) : _answers = answers;

  final List<ScriptedAnswer> _answers;

  /// The requests received, in order.
  final List<SentRequest> sent = [];

  /// How the bodies were read.
  final Reading reading = Reading();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = await _readBody(requestStream);
    final request = SentRequest(options, body);
    sent.add(request);
    unawaited(cancelFuture?.then((_) => request.cancelled = true));

    final answer = _answers.isEmpty
        ? const ScriptedAnswer()
        : _answers[(sent.length < _answers.length
                  ? sent.length
                  : _answers.length) -
              1];
    switch (answer._kind) {
      case _Kind.fails:
        Error.throwWithStackTrace(answer._failure!, StackTrace.current);
      case _Kind.never:
        return await Completer<ResponseBody>().future;
      case _Kind.brokenBody:
        return ResponseBody(
          Stream<Uint8List>.error(StateError('connection reset')),
          200,
        );
      case _Kind.response:
        final chunks =
            answer.chunks ??
            [
              if (answer.text != null && answer.text!.isNotEmpty)
                Uint8List.fromList(utf8.encode(answer.text!)),
            ];
        return ResponseBody(
          _stream(chunks, paced: answer.paced),
          answer.status,
          headers: {
            for (final entry in answer.headers.entries)
              entry.key: [entry.value],
          },
        );
    }
  }

  Stream<Uint8List> _stream(List<Uint8List> chunks, {required bool paced}) {
    var finished = false;
    var abandoned = false;
    late StreamController<Uint8List> controller;
    Future<void> deliver() async {
      reading.streamsOpened += 1;
      for (final chunk in chunks) {
        if (paced) {
          for (var turn = 0; turn < _pacedTurns; turn++) {
            await Future<void>.delayed(Duration.zero);
          }
        }
        if (abandoned) {
          return;
        }
        reading.chunksRead += 1;
        controller.add(chunk);
      }
      finished = true;
      await controller.close();
    }

    controller = StreamController<Uint8List>(
      onListen: deliver,
      onCancel: () {
        if (!finished) {
          abandoned = true;
          reading.cancelled = true;
        }
      },
    );
    return controller.stream;
  }

  /// Whether the client let go of the adapter.
  bool closed = false;

  @override
  void close({bool force = false}) {
    closed = true;
  }
}

Future<String?> _readBody(Stream<Uint8List>? stream) async {
  if (stream == null) {
    return null;
  }
  final bytes = BytesBuilder();
  await stream.forEach(bytes.add);
  return utf8.decode(bytes.takeBytes());
}
