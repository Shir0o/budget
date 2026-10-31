import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../flows.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets.dart';
import 'add_account_screen.dart';
import 'join_screen.dart';

/// First run (canvas: FirstRun). Nothing is written until the first account
/// is saved.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.engine});

  final BudgetEngine engine;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _name = TextEditingController(text: 'Home');
  String? _nameError;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 48, 16, 12),
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(8, 0, 8, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 10,
                      children: [
                        Text(
                          'Give every dollar a job',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                        Text(
                          'A zero-based budget that lives on this phone.',
                          style: TextStyle(
                            fontSize: 15,
                            color: Palette.inkSoft,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const CardBox(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        _Promise(
                          Icons.person_off_outlined,
                          'No account and no sign-up',
                          first: true,
                        ),
                        _Promise(
                          Icons.lock_outline,
                          'Encrypted on this device',
                        ),
                        _Promise(
                          Icons.download_outlined,
                          'Works offline, no telemetry',
                        ),
                        _Promise(Icons.check, 'Nothing is categorized for you'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  LabeledField(
                    label: 'Budget name',
                    child: TextField(
                      key: const ValueKey('budget-name'),
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      style: const TextStyle(fontSize: 15),
                      decoration: InputDecoration(errorText: _nameError),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Hint(
                    'Bank connection and sync between devices are off until '
                    'you turn them on.',
                  ),
                ],
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                color: Palette.card,
                border: Border(top: BorderSide(color: Palette.cardBorder)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 4,
                children: [
                  FilledButton(
                    onPressed: _addFirstAccount,
                    child: const Text('Add your first account'),
                  ),
                  TextButton(
                    key: const ValueKey('join-from-welcome'),
                    onPressed: _join,
                    child: const Text('Join a budget from another device'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addFirstAccount() {
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = 'Name your budget');
      return;
    }
    setState(() => _nameError = null);
    openFlow<void>(
      context,
      builder: (_) =>
          AddAccountScreen(engine: widget.engine, newBudgetName: _name.text),
    );
  }

  /// A device with no budget yet can bring one in from a pairing code
  /// instead of starting a new one (ticket 12).
  void _join() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => JoinScreen(services: AppServicesScope.of(context)),
      ),
    );
  }
}

class _Promise extends StatelessWidget {
  const _Promise(this.icon, this.text, {this.first = false});

  final IconData icon;
  final String text;
  final bool first;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 52),
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      border: first
          ? null
          : const Border(top: BorderSide(color: Palette.divider)),
    ),
    child: Row(
      spacing: 12,
      children: [
        Icon(icon, size: 20, color: Palette.teal),
        Text(text, style: const TextStyle(fontSize: 15)),
      ],
    ),
  );
}
