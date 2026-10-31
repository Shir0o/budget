import 'package:flutter/material.dart';

import '../budget_library.dart';
import '../services.dart';
import '../settings_widgets.dart';
import '../shell.dart';
import '../sync.dart';
import '../theme.dart';
import '../widgets.dart';

/// Joins a budget another device already has, from its pairing code
/// (ticket 12). The budget is read straight from this Google account's Drive
/// folder, so joining needs no account and no server of ours.
class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _code = TextEditingController();
  String? _problem;
  var _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final library = BudgetLibraryScope.of(context);
    // The window, not the content area: the joined budget is the app now.
    final navigator = Navigator.of(context, rootNavigator: true);
    setState(() {
      _busy = true;
      _problem = null;
    });
    final result = await joinBudget(
      library: library,
      services: widget.services,
      code: _code.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    final engine = result.engine;
    if (engine == null) {
      setState(() => _problem = result.error);
      return;
    }
    navigator.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const DesktopShell()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BackHeader(title: 'Join a budget'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                children: [
                  CardBox(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 12,
                      children: [
                        const Text(
                          'Paste the pairing code',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Text(
                          'On the device that already has the budget, open '
                          'Settings → Pair a device. Its code starts with '
                          'budget://pair.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Palette.inkSoft,
                            height: 1.45,
                          ),
                        ),
                        TextField(
                          key: const ValueKey('pairing-code'),
                          controller: _code,
                          minLines: 2,
                          maxLines: 4,
                          autocorrect: false,
                          enableSuggestions: false,
                          style: const TextStyle(
                            fontFamily: 'IBMPlexMono',
                            fontSize: 13,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'budget://pair?…',
                          ),
                        ),
                        if (problem != null)
                          Text(
                            problem,
                            key: const ValueKey('join-problem'),
                            style: const TextStyle(
                              fontSize: 13,
                              color: Palette.problemText,
                            ),
                          ),
                        FilledButton(
                          key: const ValueKey('join-budget'),
                          onPressed: _busy ? null : _join,
                          child: Text(_busy ? 'Joining…' : 'Join this budget'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const InfoNote(
                    'Joining keeps the Budget Key on this device only. The '
                    'budget is read from your own Google Drive app folder, '
                    'sealed the whole way; there is no server of ours.',
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
