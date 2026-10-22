import 'package:boardroom/application/use_cases/auth/get_current_user.dart';
import 'package:boardroom/domain/errors/app_error.dart';
import 'package:boardroom/domain/shared/result.dart';
import 'package:test/test.dart';

import '../../../domain/support/builders.dart';
import '../../support/create_fakes.dart';

void main() {
  group('GetCurrentUser', () {
    test('answers with the signed-in user', () async {
      final fakes = createFakes();
      final user = aUser(
        id: aUserId('user-9'),
        fullName: 'Nadia Benali',
        email: anEmail('n@x.fr'),
      );
      fakes.auth.session = aSession(user: user);

      expect(await GetCurrentUser(fakes).execute(), equals(ok(user)));
    });

    test('requires a valid session', () async {
      final fakes = createFakes();
      fakes.auth.session = null;
      expect(
        await GetCurrentUser(fakes).execute(),
        equals(err(notAuthenticated())),
      );

      fakes.auth.session = aSession(expiresAt: now);
      expect(
        await GetCurrentUser(fakes).execute(),
        equals(err(sessionExpired())),
      );
    });

    test('discloses nobody while the app is locked', () async {
      final fakes = createFakes();
      fakes.appLock.lock();

      expect(await GetCurrentUser(fakes).execute(), equals(err(appLocked())));
    });

    test('returns the storage error when the session cannot be read', () async {
      final fakes = createFakes();
      fakes.auth.readFailure = storageReadFailed();

      expect(
        await GetCurrentUser(fakes).execute(),
        equals(err(storageReadFailed())),
      );
    });
  });
}
