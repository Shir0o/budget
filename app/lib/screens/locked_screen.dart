import 'package:flutter/material.dart';

import '../theme.dart';

/// The lock screen (canvas: AppLock).
class LockedScreen extends StatelessWidget {
  const LockedScreen({
    super.key,
    required this.onFingerprint,
    required this.onScreenLock,
  });

  final VoidCallback onFingerprint;
  final VoidCallback onScreenLock;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 16,
              children: [
                const Icon(Icons.lock_outline, size: 44, color: Palette.ink),
                const Text(
                  'Budget is locked',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
                const Text(
                  'Unlock with your fingerprint or the phone’s screen lock.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Palette.muted),
                ),
                const SizedBox(height: 16),
                Semantics(
                  button: true,
                  label: 'Unlock with fingerprint',
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: onFingerprint,
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: Palette.card,
                        shape: BoxShape.circle,
                        border: Border.all(color: Palette.fieldBorder),
                      ),
                      child: const Icon(
                        Icons.fingerprint,
                        size: 40,
                        color: Palette.teal,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            color: Palette.card,
            border: Border(top: BorderSide(color: Palette.cardBorder)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: SafeArea(
            top: false,
            child: OutlinedButton(
              onPressed: onScreenLock,
              child: const Text('Use screen lock'),
            ),
          ),
        ),
      ],
    ),
  );
}
