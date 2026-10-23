import 'dart:async';

import 'package:boardroom/core/application/ports/types/unsubscribe.dart';
import 'package:boardroom/core/domain/shared/result.dart';
import 'package:boardroom/features/documents/application/ports/screen_protection.dart';
import 'package:boardroom/features/documents/domain/errors/screen_protection_error.dart';
import 'package:boardroom/features/documents/presentation/secure_content.dart';
import 'package:boardroom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// A screen to try the screen protection on a device: a switch that turns the
/// protection on and off, a confidential text in a [SecureContent], and the
/// list of the captures the system reported. It drives the [ScreenProtection]
/// port directly, as a demo: the documents go through the coordinator, which
/// counts the screens that need the protection.
class ScreenProtectionDemoScreen extends StatefulWidget {
  /// Creates the screen over [screenProtection].
  const new({required this.screenProtection, super.key});

  /// The port the screen turns on and off, and listens to.
  final ScreenProtection screenProtection;

  @override
  State<ScreenProtectionDemoScreen> createState() =>
      _ScreenProtectionDemoScreenState();
}

class _ScreenProtectionDemoScreenState
    extends State<ScreenProtectionDemoScreen> {
  final List<ScreenCaptureKind> _captures = [];
  late final Unsubscribe _unsubscribe;
  bool _enabled = false;
  bool _busy = false;
  ScreenProtectionError? _error;

  @override
  void initState() {
    super.initState();
    _unsubscribe = widget.screenProtection.subscribe((event) {
      if (mounted) {
        setState(() => _captures.add(event.kind));
      }
    });
  }

  @override
  void dispose() {
    _unsubscribe();
    // Leaving the screen must not leave the protection on.
    if (_enabled) {
      unawaited(widget.screenProtection.disable());
    }
    super.dispose();
  }

  Future<void> _toggle({required bool enabled}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = enabled
        ? await widget.screenProtection.enable()
        : await widget.screenProtection.disable();
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      switch (result) {
        case Ok():
          _enabled = enabled;
        case Err(:final error):
          _error = error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.documentsScreenProtectionDemoTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: Text(l10n.documentsScreenProtectionDemoSwitch),
            subtitle: Text(l10n.documentsScreenProtectionDemoSwitchHelp),
            value: _enabled,
            onChanged: _busy
                ? null
                : (value) => unawaited(_toggle(enabled: value)),
          ),
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _errorText(l10n, error),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 16),
          SecureContent(
            secure: _enabled,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l10n.documentsScreenProtectionDemoConfidential),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            l10n.documentsScreenProtectionDemoEventsTitle,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (_captures.isEmpty)
            Text(l10n.documentsScreenProtectionDemoEventsEmpty)
          else
            for (final kind in _captures)
              ListTile(
                dense: true,
                leading: const Icon(Icons.screenshot_monitor),
                title: Text(_captureText(l10n, kind)),
              ),
        ],
      ),
    );
  }
}

String _errorText(AppLocalizations l10n, ScreenProtectionError error) =>
    switch (error) {
      ScreenProtectionUnsupportedError() =>
        l10n.documentsScreenProtectionDemoErrorUnsupported,
      ScreenProtectionFailedError() =>
        l10n.documentsScreenProtectionDemoErrorFailed,
    };

String _captureText(AppLocalizations l10n, ScreenCaptureKind kind) =>
    switch (kind) {
      ScreenCaptureKind.screenshotTaken =>
        l10n.documentsScreenProtectionDemoScreenshot,
      ScreenCaptureKind.recordingStarted =>
        l10n.documentsScreenProtectionDemoRecordingStarted,
      ScreenCaptureKind.recordingStopped =>
        l10n.documentsScreenProtectionDemoRecordingStopped,
    };
