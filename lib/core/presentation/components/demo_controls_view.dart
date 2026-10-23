import 'package:boardroom/core/presentation/components/app_button.dart';
import 'package:boardroom/core/presentation/components/badge.dart';
import 'package:boardroom/core/presentation/demo/demo_controls.dart';
import 'package:boardroom/core/presentation/navigation/routes.dart';
import 'package:boardroom/core/presentation/providers.dart';
import 'package:boardroom/core/presentation/test_ids.dart';
import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The switch of the simulated server, in a small area marked as the demo: it
/// drives the whole offline scenario (go offline, open a meeting already seen,
/// vote, see it queued, go online, see it sent) in the running app. It renders
/// nothing when there are no demo controls, which is every configuration but
/// the
/// dev one: a real device has no switch to cut its own network.
class DemoOfflineSwitch extends ConsumerWidget {
  /// Creates the switch bar.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controls = ref.watch(demoControlsProvider);
    return controls == null
        ? const SizedBox.shrink()
        : _OfflineSwitch(network: controls.network);
  }
}

class _OfflineSwitch extends StatefulWidget {
  const new({required this.network});

  final DemoNetwork network;

  @override
  State<_OfflineSwitch> createState() => _OfflineSwitchState();
}

class _OfflineSwitchState extends State<_OfflineSwitch> {
  late bool _online = widget.network.online;
  void Function()? _stop;

  @override
  void initState() {
    super.initState();
    _stop = widget.network.subscribe(({required online}) {
      if (mounted) {
        setState(() => _online = online);
      }
    });
  }

  @override
  void dispose() {
    _stop?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final offline = !_online;
    return Container(
      key: const Key(CoreTestIds.demoPanel),
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        spacing: AppSpacing.md,
        children: [
          AppBadge(label: l10n.coreDemoBadge),
          Expanded(
            child: Semantics(
              toggled: offline,
              hint: l10n.coreDemoOfflineHint,
              label: l10n.coreDemoOffline,
              excludeSemantics: true,
              onTap: () => widget.network.setOnline(online: offline),
              child: InkWell(
                key: const Key(CoreTestIds.demoOfflineSwitch),
                onTap: () => widget.network.setOnline(online: offline),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: AppSizes.touchTargetMin,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          l10n.coreDemoOffline,
                          style: const TextStyle(
                            fontSize: AppFontSizes.body,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IgnorePointer(
                        child: Switch(value: offline, onChanged: (_) {}),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The accounts of the simulated server, as a discreet helper under the sign-in
/// form: touching one fills in its email address and password. They exist in
/// the
/// dev configuration only, and this renders nothing in any other. It also
/// offers the way to the demo screen of the screen protection.
class DemoAccounts extends ConsumerWidget {
  /// Creates the panel; [onPick] is called with the account the user touched.
  const new({required this.onPick, super.key});

  /// Called with the account the user touched, to fill in the form.
  final void Function(DemoAccountHint account) onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controls = ref.watch(demoControlsProvider);
    if (controls == null) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    return Container(
      key: const Key(CoreTestIds.demoAccounts),
      margin: const EdgeInsets.all(AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.sm,
        children: [
          Row(
            spacing: AppSpacing.sm,
            children: [
              AppBadge(label: l10n.coreDemoBadge),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    l10n.coreDemoAccounts,
                    style: const TextStyle(
                      fontSize: AppFontSizes.body,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Text(
            l10n.coreDemoAccountsHint,
            style: const TextStyle(
              fontSize: AppFontSizes.caption,
              color: AppColors.textSecondary,
            ),
          ),
          for (final account in controls.accounts)
            AppButton(
              key: Key(demoAccountTestId(account.email)),
              title: l10n.coreDemoUseAccount(account.fullName),
              variant: AppButtonVariant.secondary,
              onPressed: () => onPick(account),
            ),
          AppButton(
            title: l10n.coreDemoOpenScreenProtection,
            variant: AppButtonVariant.secondary,
            onPressed: () =>
                context.pushNamed(AppRoutes.screenProtectionDemo.name),
          ),
        ],
      ),
    );
  }
}
