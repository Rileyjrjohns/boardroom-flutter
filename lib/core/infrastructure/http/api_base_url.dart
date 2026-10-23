import 'package:boardroom/core/domain/shared/constants.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/domain/shared/validation.dart';
import 'package:meta/meta.dart';

/// Why an address cannot be the base URL of the API.
enum ApiBaseUrlError implements StableValue {
  /// There is no address.
  missing('missing'),

  /// Not an `http` or `https` URL with a host, or one that carries
  /// credentials, a query or a fragment.
  malformed('malformed'),

  /// An `http` URL, in a build that is not a development one, for a host that
  /// is not on this machine.
  insecure('insecure');

  new(this.value);

  @override
  final String value;
}

/// The hosts that mean "this machine" for the app: the loopback names, and the
/// address the Android emulator gives to the computer it runs on. Traffic to
/// them never leaves the machine, so it needs no TLS, in a build of any kind.
const List<String> localHosts = ['localhost', '127.0.0.1', '[::1]', '10.0.2.2'];

const String _https = 'https';
const String _schemeGroup = 'scheme';
const String _hostGroup = 'host';
const String _portGroup = 'port';
const String _pathGroup = 'path';

// scheme, host (a name, an IPv4 address or an IPv6 address in brackets), an
// optional port, an optional path. No user information (a password in a URL
// ends up in logs and screenshots), no query and no fragment.
const String _hostLabel = '[a-z0-9](?:[a-z0-9-]*[a-z0-9])?';
final RegExp _baseUrl = RegExp(
  '^(?<$_schemeGroup>https?)://'
  '(?<$_hostGroup>\\[[0-9a-f:.]+\\]|$_hostLabel(?:\\.$_hostLabel)*)'
  '(?<$_portGroup>:\\d{1,5})?'
  r'(?<path>/[^\s?#@]*)?$',
  caseSensitive: false,
);

const int _minPort = 1;
const int _maxPort = 65535;
final RegExp _trailingSlashes = RegExp(r'/+$');
const String _portPrefix = ':';

/// What the base URL depends on: the kind of build.
@immutable
final class BaseUrlEnvironment {
  /// Creates the environment of a build.
  const new({required this.development});

  /// Whether this is a development build.
  final bool development;
}

/// The base URL of the API from the raw value of the setting: trimmed, with the
/// scheme and the host in lower case and no trailing slash, so that a path is
/// always appended to it with a slash of its own. `https` is required, except
/// in a development build (where the API runs on a computer of the network) and
/// for the hosts of [localHosts].
Result<String, ApiBaseUrlError> parseApiBaseUrl(
  String? raw,
  BaseUrlEnvironment environment,
) {
  final text = trimText(raw ?? '');
  if (text.isEmpty) {
    return err(ApiBaseUrlError.missing);
  }

  final match = _baseUrl.firstMatch(text);
  final scheme = match?.namedGroup(_schemeGroup);
  final host = match?.namedGroup(_hostGroup);
  if (match == null || scheme == null || host == null) {
    return err(ApiBaseUrlError.malformed);
  }
  final port = match.namedGroup(_portGroup);
  final path = match.namedGroup(_pathGroup);

  final portNumber = port == null
      ? _minPort
      : int.parse(port.substring(_portPrefix.length));
  if (portNumber < _minPort || portNumber > _maxPort) {
    return err(ApiBaseUrlError.malformed);
  }

  final hostName = host.toLowerCase();
  final secure = scheme.toLowerCase() == _https;
  if (!secure && !environment.development && !localHosts.contains(hostName)) {
    return err(ApiBaseUrlError.insecure);
  }
  final cleanPath = (path ?? '').replaceFirst(_trailingSlashes, '');
  return ok('${scheme.toLowerCase()}://$hostName${port ?? ''}$cleanPath');
}
