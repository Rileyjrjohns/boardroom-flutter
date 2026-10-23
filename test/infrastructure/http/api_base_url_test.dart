import 'package:boardroom/domain/shared/result.dart';
import 'package:boardroom/infrastructure/http/api_base_url.dart';
import 'package:test/test.dart';

import '../../domain/support/names.dart';

const BaseUrlEnvironment _development = BaseUrlEnvironment(development: true);
const BaseUrlEnvironment _release = BaseUrlEnvironment(development: false);

void main() {
  group('parseApiBaseUrl', () {
    for (final (raw, expected) in [
      ('https://api.boardroom.example', 'https://api.boardroom.example'),
      ('https://api.boardroom.example/', 'https://api.boardroom.example'),
      ('https://api.boardroom.example///', 'https://api.boardroom.example'),
      (
        '  https://api.boardroom.example/v1/  ',
        'https://api.boardroom.example/v1',
      ),
      ('HTTPS://API.Boardroom.EXAMPLE/V1', 'https://api.boardroom.example/V1'),
      (
        'https://api.boardroom.example:8443/api/v2',
        'https://api.boardroom.example:8443/api/v2',
      ),
      ('https://203.0.113.7', 'https://203.0.113.7'),
      ('https://[2001:db8::1]:8443', 'https://[2001:db8::1]:8443'),
      ('https://a', 'https://a'),
      ('https://api.boardroom.example:1', 'https://api.boardroom.example:1'),
      (
        'https://api.boardroom.example:65535',
        'https://api.boardroom.example:65535',
      ),
    ]) {
      test('reads ${formatJson(raw)} as $expected', () {
        expect(parseApiBaseUrl(raw, _release), equals(ok(expected)));
      });
    }

    for (final raw in <String?>[null, '', '   ', '\n']) {
      test('says it is missing when it is ${formatJson(raw)}', () {
        expect(
          parseApiBaseUrl(raw, _development),
          equals(err(ApiBaseUrlError.missing)),
        );
      });
    }

    for (final raw in [
      'api.boardroom.example',
      '//api.boardroom.example',
      'ftp://api.boardroom.example',
      'https://',
      'https:///path',
      'https://api.boardroom.example?token=1',
      'https://api.boardroom.example/path?x=1',
      'https://api.boardroom.example#top',
      'https://user:password@api.boardroom.example',
      'https://user@api.boardroom.example',
      'https://api.boardroom.example:0',
      'https://api.boardroom.example:65536',
      'https://api.boardroom.example:port',
      'https://api boardroom.example',
      'https://api.boardroom.example/a b',
      'https://-bad.example',
      'https://bad-.example',
      'javascript:alert(1)',
    ]) {
      test('refuses ${formatJson(raw)} as malformed', () {
        expect(
          parseApiBaseUrl(raw, _development),
          equals(err(ApiBaseUrlError.malformed)),
        );
      });
    }

    group('the scheme', () {
      test('refuses http for a host that is not this machine outside of a '
          'development build', () {
        expect(
          parseApiBaseUrl('http://api.boardroom.example', _release),
          equals(err(ApiBaseUrlError.insecure)),
        );
        expect(
          parseApiBaseUrl('HTTP://192.168.1.20:4000', _release),
          equals(err(ApiBaseUrlError.insecure)),
        );
      });

      for (final host in localHosts) {
        test('accepts http for $host in any build: the traffic stays on the '
            'machine', () {
          expect(
            parseApiBaseUrl('http://$host:4000', _release),
            equals(ok('http://$host:4000')),
          );
        });
      }

      test('does not take a host that merely starts with a local name for a '
          'local one', () {
        expect(
          parseApiBaseUrl('http://localhost.evil.example', _release),
          equals(err(ApiBaseUrlError.insecure)),
        );
        expect(
          parseApiBaseUrl('http://127.0.0.1.evil.example', _release),
          equals(err(ApiBaseUrlError.insecure)),
        );
      });

      test('accepts http for any host in a development build', () {
        expect(
          parseApiBaseUrl('http://192.168.1.20:4000', _development),
          equals(ok('http://192.168.1.20:4000')),
        );
      });

      test('always accepts https', () {
        expect(
          parseApiBaseUrl('https://localhost:4000', _release),
          isA<Ok<String, ApiBaseUrlError>>(),
        );
        expect(
          parseApiBaseUrl('https://api.boardroom.example', _development),
          isA<Ok<String, ApiBaseUrlError>>(),
        );
      });
    });
  });
}
