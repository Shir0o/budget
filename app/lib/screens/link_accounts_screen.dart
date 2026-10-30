import 'package:budget_core/budget_core.dart';
import 'package:budget_simplefin/budget_simplefin.dart';
import 'package:flutter/material.dart';

import '../services.dart';
import '../settings_widgets.dart';
import '../theme.dart';
import '../widgets.dart';

/// Link accounts (canvas: Settings → Bank sync → Link accounts). Each bank
/// account feeds one app account or is ignored, and its linked-from date is
/// the first bank date to import (ticket 10).
class LinkAccountsScreen extends StatefulWidget {
  const LinkAccountsScreen({
    super.key,
    required this.engine,
    required this.services,
    required this.book,
    required this.accounts,
    required this.today,
  });

  final BudgetEngine engine;
  final AppServices services;

  /// The book as it was when the accounts were fetched.
  final SimpleFinBook book;

  /// The accounts the last fetch returned.
  final List<ClaimedAccount> accounts;

  final CivilDate today;

  @override
  State<LinkAccountsScreen> createState() => _LinkAccountsScreenState();
}

class _LinkAccountsScreenState extends State<LinkAccountsScreen> {
  late final Map<String, _Draft> _drafts = {
    for (final account in widget.accounts)
      account.id: _Draft.of(widget.book.linkFor(account.id), widget.today),
  };
  var _saving = false;

  BudgetState get _state => widget.engine.state;

  void _choose(_Draft draft, String? accountId) => setState(() {
    draft
      ..decided = true
      ..accountId = accountId;
    if (accountId != null) {
      draft.linkedFrom = defaultLinkedFrom(_state, accountId, widget.today);
    }
  });

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    var book = widget.book;
    for (final account in widget.accounts) {
      final draft = _drafts[account.id]!;
      if (!draft.decided) continue;
      book = book.link(
        LinkedAccount(
          simpleFinId: account.id,
          institution: account.institution,
          name: account.displayName,
          linkedFrom: draft.linkedFrom,
          accountId: draft.accountId,
        ),
      );
    }
    await widget.services.prefs.writeSimpleFinBook(book);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BackHeader(title: 'Link accounts'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Hint(
                    'Each bank account feeds one app account. Linked from is '
                    'the first bank date to import, so history already in '
                    'the budget isn’t pulled in again. Ignore an account to '
                    'leave it out.',
                  ),
                ),
                for (final (i, account) in widget.accounts.indexed) ...[
                  if (i > 0) const SizedBox(height: 12),
                  _accountCard(account),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  key: const ValueKey('save-links'),
                  onPressed: _saving ? null : _save,
                  child: const Text('Save links'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _accountCard(ClaimedAccount account) {
    final draft = _drafts[account.id]!;
    final label = !draft.decided
        ? 'Not linked'
        : draft.accountId == null
        ? 'Ignored'
        : _state.account(draft.accountId!)?.name ?? 'Missing account';
    return CardBox(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 4,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      account.displayName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      [
                        if (account.institution.isNotEmpty) account.institution,
                        account.balance.formatDollars(),
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 13,
                        color: Palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (account.transactions.isNotEmpty)
                Text(
                  '${account.transactions.length} new',
                  style: amountStyle(fontSize: 12, color: Palette.muted),
                ),
            ],
          ),
          const SizedBox(height: 4),
          _Row(
            label: 'App account',
            child: Align(
              alignment: Alignment.centerRight,
              child: PopupMenuButton<String>(
                tooltip: 'Choose app account',
                onSelected: (choice) =>
                    _choose(draft, choice == _ignore ? null : choice),
                itemBuilder: (_) => [
                  for (final account in _state.accounts)
                    PopupMenuItem(value: account.id, child: Text(account.name)),
                  const PopupMenuDivider(),
                  const PopupMenuItem(value: _ignore, child: Text('Ignore')),
                ],
                child: _Choice(label),
              ),
            ),
          ),
          if (draft.decided && draft.accountId != null)
            _Row(
              label: 'Linked from',
              child: DateField(
                value: draft.linkedFrom,
                onChanged: (date) => setState(() => draft.linkedFrom = date),
              ),
            ),
        ],
      ),
    );
  }
}

/// The popup's "Ignore" choice, which is not an account id.
const _ignore = '';

final class _Draft {
  _Draft({
    required this.accountId,
    required this.linkedFrom,
    required this.decided,
  });

  factory _Draft.of(LinkedAccount? link, CivilDate today) => link == null
      ? _Draft(accountId: null, linkedFrom: today, decided: false)
      : _Draft(
          accountId: link.accountId,
          linkedFrom: link.linkedFrom,
          decided: true,
        );

  String? accountId;
  CivilDate linkedFrom;

  /// False until the person picks an account or Ignore, so saving leaves an
  /// undecided account exactly as it was.
  bool decided;
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 44),
    child: Row(
      spacing: 12,
      children: [
        Text(label, style: const TextStyle(fontSize: 15)),
        const Spacer(),
        Flexible(child: child),
      ],
    ),
  );
}

class _Choice extends StatelessWidget {
  const _Choice(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 44),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15),
          ),
        ),
        const Icon(Icons.keyboard_arrow_down, size: 18, color: Palette.ink),
      ],
    ),
  );
}
