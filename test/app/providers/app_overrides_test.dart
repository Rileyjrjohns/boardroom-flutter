import 'dart:io';

import 'package:boardroom/core/presentation/providers.dart';
import 'package:boardroom/features/auth/presentation/providers.dart';
import 'package:boardroom/features/documents/presentation/providers.dart';
import 'package:boardroom/features/meetings/presentation/providers.dart';
import 'package:boardroom/features/votes/presentation/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';

import '../../support/presentation/test_app.dart';

// The composition root overrides every provider that a feature declares and
// throws on. A provider added without its override fails here, not on a device.

void main() {
  final throwing = <String, ProviderListenable<Object?>>{
    'clockProvider': clockProvider,
    'observeConnectivityUseCaseProvider': observeConnectivityUseCaseProvider,
    'errorCatalogProvider': errorCatalogProvider,
    'sessionEndHandlerProvider': sessionEndHandlerProvider,
    'sessionEpochProvider': sessionEpochProvider,
    'restoreSessionUseCaseProvider': restoreSessionUseCaseProvider,
    'signInUseCaseProvider': signInUseCaseProvider,
    'signOutUseCaseProvider': signOutUseCaseProvider,
    'evaluateAppLockUseCaseProvider': evaluateAppLockUseCaseProvider,
    'unlockAppUseCaseProvider': unlockAppUseCaseProvider,
    'getCurrentUserUseCaseProvider': getCurrentUserUseCaseProvider,
    'listMeetingsUseCaseProvider': listMeetingsUseCaseProvider,
    'getMeetingUseCaseProvider': getMeetingUseCaseProvider,
    'meetingsPageSizeProvider': meetingsPageSizeProvider,
    'openDocumentUseCaseProvider': openDocumentUseCaseProvider,
    'closeDocumentUseCaseProvider': closeDocumentUseCaseProvider,
    'observeScreenCaptureUseCaseProvider': observeScreenCaptureUseCaseProvider,
    'screenProtectionProvider': screenProtectionProvider,
    'castVoteUseCaseProvider': castVoteUseCaseProvider,
    'syncPendingVotesUseCaseProvider': syncPendingVotesUseCaseProvider,
    'listPendingVotesUseCaseProvider': listPendingVotesUseCaseProvider,
    'acknowledgeRejectedVoteUseCaseProvider':
        acknowledgeRejectedVoteUseCaseProvider,
    'discardUnreadableVotesUseCaseProvider':
        discardUnreadableVotesUseCaseProvider,
  };

  test('overrides every provider that throws until it is overridden', () {
    final providers = TestApp().providers();

    for (final MapEntry(:key, :value) in throwing.entries) {
      expect(() => providers.read(value), returnsNormally, reason: key);
    }
  });

  test('a container with no override throws on each of them', () {
    final providers = ProviderContainer();
    addTearDown(providers.dispose);

    for (final MapEntry(:key, :value) in throwing.entries) {
      expect(() => providers.read(value), throwsA(anything), reason: key);
    }
  });

  test('the list names every provider of the presentation that throws', () {
    final declared = <String>[];
    final files = [
      File('lib/core/presentation/providers.dart'),
      for (final feature in ['auth', 'meetings', 'documents', 'votes'])
        File('lib/features/$feature/presentation/providers.dart'),
    ];
    for (final file in files) {
      final source = file.readAsStringSync();
      for (final match in RegExp(
        r'^\w[\w<>?]* (\w+)\(Ref ref\)\s*(=>\s*)?throw',
        multiLine: true,
      ).allMatches(source)) {
        declared.add('${match.group(1)}Provider');
      }
    }

    expect(declared.toSet(), throwing.keys.toSet());
  });

  test('the epoch is the one of the access, and the handler ends the session '
      'for the epoch it was told', () {
    final providers = TestApp().providers();

    expect(providers.read(sessionEpochProvider), 0);
    providers.read(sessionEndHandlerProvider)('sessionExpired', null);

    expect(providers.read(sessionEpochProvider), 1);
  });

  test('the handler ignores a code that does not end the session', () {
    final providers = TestApp().providers();

    providers.read(sessionEndHandlerProvider)('forbidden', null);

    expect(providers.read(sessionEpochProvider), 0);
  });
}
