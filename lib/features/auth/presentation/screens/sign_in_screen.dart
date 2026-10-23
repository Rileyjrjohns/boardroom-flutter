import 'package:boardroom/core/domain/errors/app_error.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/core/presentation/components/app_button.dart';
import 'package:boardroom/core/presentation/components/app_text_field.dart';
import 'package:boardroom/core/presentation/components/demo_controls_view.dart';
import 'package:boardroom/core/presentation/components/live_text.dart';
import 'package:boardroom/core/presentation/components/status_banner.dart';
import 'package:boardroom/core/presentation/theme/tokens.dart';
import 'package:boardroom/features/auth/domain/value_objects/credentials.dart';
import 'package:boardroom/features/auth/presentation/components/session_notice.dart';
import 'package:boardroom/features/auth/presentation/error_messages.dart';
import 'package:boardroom/features/auth/presentation/state/access.dart';
import 'package:boardroom/features/auth/presentation/state/sign_in_action.dart';
import 'package:boardroom/features/auth/presentation/test_ids.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The sign-in form (docs/spec/screens.md "Sign-in"). The credentials are
/// checked here first, with the rules of the domain (a well-formed email
/// address, a password that is not empty), so that a mistake is told next to
/// its field without waiting for the server; the `SignIn` use case checks them
/// again, and what comes back from it is told the same way. The refusals that
/// are not about a field (wrong credentials, the server out of reach) are told
/// above the button.
///
/// The password is in the controller of this screen only while it is being
/// typed: pressing "sign in" hands it over and empties the field, whatever the
/// answer, so that neither the screen nor any state of the app holds it a
/// moment longer than needed. While the request is under way the button is busy
/// and a second press (or the "go" key of the keyboard) does nothing. A device
/// that is offline says so at the top of the screen, and in the dev
/// configuration the switch of the demo is there too (a sign-in that fails for
/// want of a connection must not leave the demo with no way to bring it back),
/// and the accounts of the simulated server are offered under the form.
///
/// This is the reference screen of the presentation pattern: a
/// `ConsumerStatefulWidget` for the state of the form, a notifier
/// (`SignInAction`) for the action, a map of codes to texts, test ids as keys.
class SignInScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const new({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  ValidationError? _refused;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _focusFieldOf(ValidationError error) {
    final refusesEmail = error.field == ValidationField.email;
    (refusesEmail ? _emailFocus : _passwordFocus).requestFocus();
  }

  Future<void> _submit() async {
    if (ref.read(signInActionProvider).isPending) {
      return;
    }
    final checked = createCredentials(_email.text, _password.text);
    if (checked case Err(:final error)) {
      setState(() => _refused = error);
      // The first field the form refuses is the one to go to: its error is read
      // with it.
      _focusFieldOf(error);
      return;
    }
    FocusScope.of(context).unfocus();
    final email = _email.text;
    final password = _password.text;
    setState(() => _refused = null);
    // The password is emptied whatever the answer will be.
    _password.clear();
    await ref
        .read(signInActionProvider.notifier)
        .run(email: email, password: password);
  }

  void _clearRefusal() {
    if (_refused != null) {
      setState(() => _refused = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final action = ref.watch(signInActionProvider);
    final endedBy = ref.watch(
      accessControllerProvider.select((state) => state.sessionEndedBy),
    );

    // The password was emptied when the form was sent: whoever failed starts
    // typing it again. A refusal of the email address (the use case checked the
    // form again) sends them there instead.
    ref.listen(signInActionProvider.select((state) => state.failure), (
      _,
      failure,
    ) {
      if (failure == null) {
        return;
      }
      if (failure is ValidationError) {
        _focusFieldOf(failure);
      } else {
        _passwordFocus.requestFocus();
      }
    });

    final failure = action.failure;
    final validation =
        _refused ?? (failure is ValidationError ? failure : null);
    final emailError = validation?.field == ValidationField.email
        ? emailRuleMessage(l10n, validation!.rule)
        : null;
    final passwordError = validation?.field == ValidationField.password
        ? passwordRuleMessage(l10n)
        : null;
    final formFailure = _refused == null ? failure : null;
    final formError =
        formFailure != null &&
            (formFailure is! ValidationError ||
                (emailError == null && passwordError == null))
        ? signInErrorMessage(l10n, formFailure.code)
        : null;

    return Column(
      key: const Key(AuthTestIds.signInScreen),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ConnectionBanner(),
        const DemoOfflineSwitch(),
        Expanded(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              children: [
                Align(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppSizes.formMaxWidth,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: AppSpacing.lg,
                        children: [
                          Semantics(
                            header: true,
                            child: Text(
                              l10n.authSignInTitle,
                              style: const TextStyle(
                                fontSize: AppFontSizes.title,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          Text(
                            l10n.authSignInMessage,
                            style: const TextStyle(
                              fontSize: AppFontSizes.body,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          if (endedBy != null) SessionNotice(code: endedBy),
                          AppTextField(
                            key: const Key(AuthTestIds.signInEmail),
                            errorKey: const Key(AuthTestIds.signInEmailError),
                            label: l10n.authSignInEmail,
                            controller: _email,
                            focusNode: _emailFocus,
                            enabled: !action.isPending,
                            error: emailError,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.username],
                            onChanged: (_) => _clearRefusal(),
                            onSubmitted: (_) => _passwordFocus.requestFocus(),
                          ),
                          AppTextField(
                            key: const Key(AuthTestIds.signInPassword),
                            errorKey: const Key(
                              AuthTestIds.signInPasswordError,
                            ),
                            label: l10n.authSignInPassword,
                            controller: _password,
                            focusNode: _passwordFocus,
                            enabled: !action.isPending,
                            error: passwordError,
                            obscureText: true,
                            textInputAction: TextInputAction.go,
                            autofillHints: const [AutofillHints.password],
                            onChanged: (_) => _clearRefusal(),
                            onSubmitted: (_) => _submit(),
                          ),
                          if (formError != null)
                            KeyedSubtree(
                              key: const Key(AuthTestIds.signInError),
                              child: LiveText(
                                message: formError,
                                style: const TextStyle(
                                  fontSize: AppFontSizes.body,
                                  color: AppColors.danger,
                                ),
                              ),
                            ),
                          AppButton(
                            key: const Key(AuthTestIds.signInSubmit),
                            title: action.isPending
                                ? l10n.authSignInSubmitting
                                : l10n.authSignInSubmit,
                            busy: action.isPending,
                            onPressed: _submit,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                DemoAccounts(
                  onPick: (account) {
                    _email.text = account.email;
                    _password.text = account.password;
                    _clearRefusal();
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
