import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

// The two messages the simulated API reads and writes. They know no network
// library: the API is a function from an [ApiRequest] to an [ApiResponse], and
// whoever carries them (the dio adapter, a test) turns its own request into the
// first and the second into its own response.

/// The value of the header [name] in [headers], or `null`. Header names are not
/// case sensitive.
String? _headerIn(Map<String, String> headers, String name) {
  final wanted = name.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == wanted) {
      return entry.value;
    }
  }
  return null;
}

/// A request as the server receives it.
@immutable
final class ApiRequest {
  /// Creates a request. [target] is what comes after the host on the request
  /// line, as sent: the path and the query, percent-encoded
  /// (`/meetings?period=past&limit=5`). The server decodes it, so that a
  /// malformed escape sequence reaches it as it would reach a real server.
  const new({
    required this.method,
    required this.target,
    this.headers = const {},
    this.body,
  });

  /// The HTTP method, as sent.
  final String method;

  /// The path and the query, percent-encoded.
  final String target;

  /// The headers, by name. Look one up with [header].
  final Map<String, String> headers;

  /// The body, or `null` for a request that has none.
  final Uint8List? body;

  /// The value of the header [name], whatever its case, or `null`.
  String? header(String name) => _headerIn(headers, name);

  /// The path, percent-encoded, without the query.
  String get path {
    final end = target.indexOf('?');
    return end == -1 ? target : target.substring(0, end);
  }

  /// The query, percent-encoded, without the `?`, or an empty text.
  String get query {
    final start = target.indexOf('?');
    return start == -1 ? '' : target.substring(start + 1);
  }

  // The token of the caller is in the headers: it is never printed.
  @override
  String toString() => 'ApiRequest($method $path)';
}

/// An answer of the server.
@immutable
final class ApiResponse {
  /// Creates an answer.
  const new({
    required this.status,
    required this.body,
    this.headers = const {},
  });

  /// An answer whose body is the UTF-8 form of [text].
  new text({
    required this.status,
    required String text,
    this.headers = const {},
  }) : body = Uint8List.fromList(utf8.encode(text));

  /// The status code.
  final int status;

  /// The headers, by name. Look one up with [header].
  final Map<String, String> headers;

  /// The body, empty for an answer that has none.
  final Uint8List body;

  /// The value of the header [name], whatever its case, or `null`.
  String? header(String name) => _headerIn(headers, name);

  /// The body read as UTF-8 text.
  String get text => utf8.decode(body, allowMalformed: true);

  @override
  String toString() => 'ApiResponse($status, ${body.length} bytes)';
}
