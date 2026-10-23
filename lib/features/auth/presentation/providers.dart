import 'package:boardroom/features/auth/application/use_cases/evaluate_app_lock.dart';
import 'package:boardroom/features/auth/application/use_cases/get_current_user.dart';
import 'package:boardroom/features/auth/application/use_cases/restore_session.dart';
import 'package:boardroom/features/auth/application/use_cases/sign_in.dart';
import 'package:boardroom/features/auth/application/use_cases/sign_out.dart';
import 'package:boardroom/features/auth/application/use_cases/unlock_app.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'providers.g.dart';

// The use cases the screens and the notifiers of the session need. The
// presentation of the feature declares what it depends on and throws until
// `lib/app/providers` overrides it in the root `ProviderScope` (a widget test
// overrides it with a use case over fakes): the feature never imports the
// composition.

/// Who was signed in when the app was last used.
@Riverpod(keepAlive: true)
RestoreSession restoreSessionUseCase(Ref ref) =>
    throw UnimplementedError('restoreSessionUseCaseProvider');

/// Signs in with the credentials the user typed.
@Riverpod(keepAlive: true)
SignIn signInUseCase(Ref ref) =>
    throw UnimplementedError('signInUseCaseProvider');

/// Signs the user out.
@Riverpod(keepAlive: true)
SignOut signOutUseCase(Ref ref) =>
    throw UnimplementedError('signOutUseCaseProvider');

/// Judges whether the app must be unlocked after a time in the background.
@Riverpod(keepAlive: true)
EvaluateAppLock evaluateAppLockUseCase(Ref ref) =>
    throw UnimplementedError('evaluateAppLockUseCaseProvider');

/// Unlocks the app with the biometrics.
@Riverpod(keepAlive: true)
UnlockApp unlockAppUseCase(Ref ref) =>
    throw UnimplementedError('unlockAppUseCaseProvider');

/// Reads the signed-in user, which is also the check of the session.
@Riverpod(keepAlive: true)
GetCurrentUser getCurrentUserUseCase(Ref ref) =>
    throw UnimplementedError('getCurrentUserUseCaseProvider');
