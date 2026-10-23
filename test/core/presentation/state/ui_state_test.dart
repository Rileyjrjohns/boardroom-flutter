import 'package:boardroom/core/application/ports/connectivity.dart';
import 'package:boardroom/core/presentation/notices/app_notices.dart';
import 'package:boardroom/core/presentation/providers.dart';
import 'package:boardroom/core/presentation/state/ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Notices implements AppNotices {
  int acknowledged = 0;

  @override
  bool get localDataReset => true;

  @override
  Future<void> acknowledgeLocalDataReset() async => acknowledged++;
}

void main() {
  ProviderContainer container([AppNotices? notices]) {
    final created = ProviderContainer(
      overrides: [
        if (notices != null) appNoticesProvider.overrideWithValue(notices),
      ],
    );
    addTearDown(created.dispose);
    return created;
  }

  test('the connection is online until the device says otherwise', () {
    final providers = container();
    expect(
      providers.read(connectivityStateProvider),
      ConnectivityStatus.online,
    );

    providers
        .read(connectivityStateProvider.notifier)
        .set(ConnectivityStatus.offline);

    expect(
      providers.read(connectivityStateProvider),
      ConnectivityStatus.offline,
    );
  });

  test('the cover goes up and down', () {
    final providers = container();
    expect(providers.read(privacyCoverUpProvider), isFalse);

    providers.read(privacyCoverUpProvider.notifier).set(true);

    expect(providers.read(privacyCoverUpProvider), isTrue);
  });

  test('the reset notice is owed until it is dismissed, and then forgotten '
      'for good', () {
    final notices = _Notices();
    final providers = container(notices);
    expect(providers.read(localDataResetNoticeProvider), isTrue);

    providers.read(localDataResetNoticeProvider.notifier).dismiss();

    expect(providers.read(localDataResetNoticeProvider), isFalse);
    expect(notices.acknowledged, 1);
  });

  test('there is no notice by default', () {
    expect(container().read(localDataResetNoticeProvider), isFalse);
  });

  test('a provider nobody overrode says which one it is', () {
    final providers = container();

    expect(
      () => providers.read(clockProvider),
      throwsA(
        predicate<Object>(
          (error) => error.toString().contains('clockProvider'),
        ),
      ),
    );
  });
}
