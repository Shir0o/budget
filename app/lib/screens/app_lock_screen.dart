import 'package:flutter/material.dart';

import '../services.dart';
import '../settings_widgets.dart';
import '../theme.dart';
import '../widgets.dart';

/// Turns the app lock on or off. It is off by default; the canvas has no
/// separate screen for this, so it follows the Settings card style.
class AppLockScreen extends StatefulWidget {
  const AppLockScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  String? _problem;

  /// Changing the lock needs the phone's check to pass first, so a lock can
  /// neither be switched on by someone else nor left on with no way in.
  Future<void> _set(bool enabled) async {
    final services = widget.services;
    if (!await services.authenticator.isSupported()) {
      setState(
        () => _problem = 'Set up a fingerprint or screen lock in your phone’s settings first.',
      );
      return;
    }
    final ok = await services.keepUnlocked(
      () => services.authenticator.authenticate(
        reason: enabled ? 'Turn on app lock' : 'Turn off app lock',
        biometricOnly: false,
      ),
    );
    if (!ok) return;
    await services.setAppLockEnabled(enabled);
    if (mounted) setState(() => _problem = null);
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BackHeader(title: 'App lock'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                children: [
                  CardBox(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: ValueListenableBuilder(
                      valueListenable: widget.services.appLockEnabled,
                      builder: (context, enabled, _) => Row(
                        spacing: 12,
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Lock the app',
                                  style: TextStyle(fontSize: 15),
                                ),
                                Hint('Fingerprint or the phone’s screen lock'),
                              ],
                            ),
                          ),
                          Semantics(
                            label: 'Lock the app',
                            child: Switch(
                              key: const ValueKey('app-lock-switch'),
                              value: enabled,
                              onChanged: _set,
                              activeThumbColor: Palette.card,
                              activeTrackColor: Palette.teal,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.padded,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (problem != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      problem,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Palette.problemText,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const InfoNote(
                    'The budget locks each time you leave the app. Your data '
                    'is encrypted on this phone whether the lock is on or not.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
