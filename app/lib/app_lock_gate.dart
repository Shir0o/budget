import 'package:flutter/widgets.dart';

import 'screens/locked_screen.dart';
import 'services.dart';

/// Covers the whole app with the lock screen when the app lock is on: at
/// launch, and each time the app comes back from the background. The app
/// underneath stays mounted, so unlocking returns to where the person was.
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.services, required this.child});

  final AppServices services;
  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  late var _locked = widget.services.appLockEnabled.value;
  var _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_locked) _unlock(biometricOnly: false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final services = widget.services;
    switch (state) {
      case AppLifecycleState.paused:
        if (services.appLockEnabled.value && !services.lockHeld) {
          setState(() => _locked = true);
        }
      case AppLifecycleState.resumed:
        if (_locked) _unlock(biometricOnly: false);
      default:
    }
  }

  Future<void> _unlock({required bool biometricOnly}) async {
    if (_checking) return;
    _checking = true;
    final ok = await widget.services.authenticator.authenticate(
      reason: 'Unlock your budget',
      biometricOnly: biometricOnly,
    );
    _checking = false;
    if (ok && mounted) setState(() => _locked = false);
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Visibility(visible: !_locked, maintainState: true, child: widget.child),
      if (_locked)
        LockedScreen(
          onFingerprint: () => _unlock(biometricOnly: true),
          onScreenLock: () => _unlock(biometricOnly: false),
        ),
    ],
  );
}
