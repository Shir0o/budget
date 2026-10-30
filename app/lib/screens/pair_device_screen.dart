import 'package:budget_core/budget_core.dart';
import 'package:budget_sync/budget_sync.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services.dart';
import '../settings_widgets.dart';
import '../theme.dart';
import '../widgets.dart';

/// Shows the QR code that adds the other device to this budget (ticket 12).
/// The code carries the Budget Key and the Drive budget id, and goes straight
/// from this screen to that camera, so no server or account is involved.
class PairDeviceScreen extends StatefulWidget {
  const PairDeviceScreen({
    super.key,
    required this.engine,
    required this.services,
  });

  final BudgetEngine engine;
  final AppServices services;

  @override
  State<PairDeviceScreen> createState() => _PairDeviceScreenState();
}

class _PairDeviceScreenState extends State<PairDeviceScreen> {
  PairingPayload? _payload;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final budget = widget.engine.state.budget;
    if (budget == null) return;
    final payload = PairingPayload(
      budgetId: budget.id,
      key: await widget.services.keys.keyFor(budget.id),
    );
    if (mounted) setState(() => _payload = payload);
  }

  @override
  Widget build(BuildContext context) {
    final payload = _payload;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BackHeader(title: 'Pair a device'),
            Expanded(
              child: payload == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      children: [
                        CardBox(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            spacing: 14,
                            children: [
                              const Text(
                                'Scan this on your other device',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Center(child: PairingQr(payload: payload)),
                              const Hint(
                                'Open Budget on the other device, choose '
                                'Settings → Join a device’s budget, and paste '
                                'this code if it can’t scan the square.',
                              ),
                              SelectableText(
                                payload.code,
                                key: const ValueKey('pairing-code'),
                                style: const TextStyle(
                                  fontFamily: 'IBMPlexMono',
                                  fontSize: 11,
                                  color: Palette.muted,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        const InfoNote(
                          'The code holds the Budget Key and the Drive id of '
                          'this budget, and nothing else. Don’t show it to '
                          'anyone, photograph it or send it: anyone who has it '
                          'can read the budget. The recovery phrase is the '
                          'other way to bring a device in.',
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

/// The pairing code as a square. It keeps the [payload] it was given and
/// draws its [PairingPayload.code], so there is one thing on screen.
class PairingQr extends StatelessWidget {
  const PairingQr({super.key, required this.payload, this.size = 220});

  final PairingPayload payload;
  final double size;

  @override
  Widget build(BuildContext context) => QrImageView(
    data: payload.code,
    version: QrVersions.auto,
    size: size,
    backgroundColor: Palette.card,
    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Palette.ink),
    dataModuleStyle: const QrDataModuleStyle(
      dataModuleShape: QrDataModuleShape.square,
      color: Palette.ink,
    ),
  );
}
