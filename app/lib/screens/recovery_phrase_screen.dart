import 'package:budget_core/budget_core.dart';
import 'package:budget_sync/budget_sync.dart';
import 'package:flutter/material.dart';

import '../services.dart';
import '../settings_widgets.dart';
import '../theme.dart';
import '../widgets.dart';

/// The 24 words that spell this budget's Budget Key (ticket 12). They are
/// shown once when sync is turned on, and from then on only after the phone
/// confirms it is you, because anyone who reads them can read the budget.
class RecoveryPhraseScreen extends StatefulWidget {
  const RecoveryPhraseScreen({
    super.key,
    required this.services,
    required this.budgetKey,
    this.requiresConfirmation = true,
  });

  final AppServices services;

  /// The key to spell. It is never written to the Event log.
  final BudgetKey budgetKey;

  /// False for the first showing, right after sync is turned on or the key is
  /// rotated, when the person has just acted and no check is needed.
  final bool requiresConfirmation;

  @override
  State<RecoveryPhraseScreen> createState() => _RecoveryPhraseScreenState();
}

class _RecoveryPhraseScreenState extends State<RecoveryPhraseScreen> {
  List<String>? _words;
  String? _problem;
  var _checking = false;

  @override
  void initState() {
    super.initState();
    if (widget.requiresConfirmation) {
      _confirm();
    } else {
      _spell();
    }
  }

  /// The phrase is shown only after the fingerprint or screen lock says it is
  /// you, so a phone left unlocked doesn't hand out the budget's key.
  Future<void> _confirm() async {
    final services = widget.services;
    setState(() {
      _problem = null;
      _checking = true;
    });
    final supported = await services.authenticator.isSupported();
    final ok =
        supported &&
        await services.keepUnlocked(
          () => services.authenticator.authenticate(
            reason: 'Show the recovery phrase',
            biometricOnly: true,
          ),
        );
    if (!mounted) return;
    setState(() => _checking = false);
    if (ok) {
      await _spell();
    } else if (mounted) {
      setState(
        () => _problem = supported
            ? 'The phrase is only shown after your fingerprint confirms it '
                  'is you.'
            : 'Set up a fingerprint or screen lock in your phone’s settings '
                  'first.',
      );
    }
  }

  Future<void> _spell() async {
    final phrase = await RecoveryPhrase.of(widget.budgetKey);
    if (!mounted) return;
    setState(() {
      _words = phrase.words;
      _problem = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final words = _words;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BackHeader(title: 'Recovery phrase'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                children: [
                  if (_checking)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (words == null) ...[
                    InfoNote(_problem ?? ''),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      key: const ValueKey('show-recovery-phrase'),
                      onPressed: _confirm,
                      child: const Text('Try again'),
                    ),
                  ] else ...[
                    CardBox(
                      padding: const EdgeInsets.all(16),
                      child: _Words(words: words),
                    ),
                    const SizedBox(height: 12),
                    const InfoNote(
                      'These 24 words are the Budget Key. Write them down, in '
                      'this order, and keep them where you keep your passport. '
                      'Anyone who reads them can read this budget, and nobody '
                      'can recover them for you.',
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Words extends StatelessWidget {
  const _Words({required this.words});

  final List<String> words;

  @override
  Widget build(BuildContext context) => GridView.builder(
    key: const ValueKey('recovery-words'),
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      mainAxisExtent: 28,
      crossAxisSpacing: 16,
    ),
    itemCount: words.length,
    itemBuilder: (context, index) => Row(
      spacing: 8,
      children: [
        SizedBox(
          width: 18,
          child: Text(
            '${index + 1}',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12, color: Palette.muted),
          ),
        ),
        Text(
          words[index],
          style: const TextStyle(
            fontFamily: 'IBMPlexMono',
            fontSize: 14,
            color: Palette.ink,
          ),
        ),
      ],
    ),
  );
}
