import 'package:boardroom/core/application/ports/connectivity.dart';
import 'package:boardroom/core/domain/value_objects/instant.dart';
import 'package:boardroom/core/presentation/components/app_button.dart';
import 'package:boardroom/core/presentation/components/live_text.dart';
import 'package:boardroom/core/presentation/format/formatters.dart';
import 'package:boardroom/core/presentation/state/ui_state.dart';
import 'package:boardroom/core/presentation/test_ids.dart';
import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

/// What a feature adds to the banner: lines about the state of its own data, in
/// the block of the banner and on its background. The core declares the slot,
/// the feature implements it, and `lib/app` plugs it in
/// (`bannerNoticesProvider`): the votes tell what the last synchronisation did,
/// and the shared banner does not know the votes.
final class BannerNotices {
  /// Creates the notices of a feature.
  const new({required this.hasNotices, required this.builder});

  /// Whether there is something to tell, watched by the banner: it shows
  /// nothing at all when nobody has anything to say.
  final ProviderListenable<bool> hasNotices;

  /// The lines, built when [hasNotices] says so.
  final WidgetBuilder builder;

  /// The banner when nothing is plugged into it: it tells what the core knows,
  /// and no more.
  static final BannerNotices none = BannerNotices(
    hasNotices: Provider<bool>((ref) => false),
    builder: (context) => const SizedBox.shrink(),
  );
}

/// The notices plugged into the banner. Nothing until `lib/app` overrides it.
final bannerNoticesProvider = Provider<BannerNotices>(
  (ref) => BannerNotices.none,
);

/// The one banner area of a screen, at its top, for what the user should know
/// about the state of the data: that the device is offline, that what is shown
/// is a saved copy and since when, what a feature adds to it (the votes tell
/// what the last synchronisation did), and that local data was reset. It is a
/// single block on a single background, with a line per fact, and nothing at
/// all when there is nothing to say.
///
/// The two facts about the connection are told apart on purpose, and can be
/// true together or apart: the device being offline says what the platform
/// thinks, a saved copy says what the server really answered.
class StatusBanner extends ConsumerWidget {
  /// Creates the banner; [staleSince] is when the data on the screen was saved,
  /// if what is shown is a saved copy (a screen with no data of its own to date
  /// passes nothing).
  const new({this.staleSince, super.key});

  /// When the data on the screen was saved, if it is a saved copy.
  final Instant? staleSince;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final offline =
        ref.watch(connectivityStateProvider) == ConnectivityStatus.offline;
    final reset = ref.watch(localDataResetNoticeProvider);
    final notices = ref.watch(bannerNoticesProvider);
    final hasNotices = ref.watch(notices.hasNotices);

    if (!offline && staleSince == null && !hasNotices && !reset) {
      return const SizedBox.shrink();
    }
    return _BannerBlock(
      key: const Key(CoreTestIds.statusBanner),
      children: [
        if (offline) _OfflineLine(l10n),
        if (staleSince case final since?)
          KeyedSubtree(
            key: const Key(CoreTestIds.staleBanner),
            child: LiveText(
              message: l10n.coreStatesStaleData(
                Formatters.of(context).dateTime(since),
              ),
              style: _bannerText,
            ),
          ),
        if (reset)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppSpacing.sm,
            children: [
              KeyedSubtree(
                key: const Key(CoreTestIds.localDataResetNotice),
                child: LiveText(
                  message: l10n.coreBannerLocalDataReset,
                  style: _bannerText,
                ),
              ),
              AppButton(
                key: const Key(CoreTestIds.localDataResetDismiss),
                title: l10n.coreBannerDismiss,
                variant: AppButtonVariant.secondary,
                onPressed: () =>
                    ref.read(localDataResetNoticeProvider.notifier).dismiss(),
              ),
            ],
          ),
        if (hasNotices) notices.builder(context),
      ],
    );
  }
}

/// The banner of the screens that are shown before the app is open, the sign-in
/// and the lock screens: the one fact it can tell there is that the device is
/// offline (a sign-in cannot succeed, and the switch of the demo is what brings
/// the connection back). Nothing at all when the device is online.
class ConnectionBanner extends ConsumerWidget {
  /// Creates the banner.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline =
        ref.watch(connectivityStateProvider) == ConnectivityStatus.offline;
    if (!offline) {
      return const SizedBox.shrink();
    }
    return _BannerBlock(
      key: const Key(CoreTestIds.statusBanner),
      children: [_OfflineLine(AppLocalizations.of(context))],
    );
  }
}

const TextStyle _bannerText = TextStyle(
  fontSize: AppFontSizes.caption,
  color: AppColors.warningText,
);

class _OfflineLine extends StatelessWidget {
  const new(this.l10n);

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => KeyedSubtree(
    key: const Key(CoreTestIds.offlineBanner),
    child: LiveText(message: l10n.coreBannerOffline, style: _bannerText),
  );
}

class _BannerBlock extends StatelessWidget {
  const new({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: AppColors.warningBackground,
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.md,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: AppSpacing.xs,
      children: children,
    ),
  );
}
