import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bank_sync.dart';
import '../flows.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets.dart';
import 'possible_match_screen.dart';
import 'transaction_parts.dart';

/// Review in the desktop window (ticket 64): the lines waiting for Review in
/// a list, with the selected line's detail beside it. The phone's one-line-
/// at-a-time Review is unchanged.
///
/// The detail panel starts empty and only the person's own taps fill it, so
/// nothing is ever categorized for them (ADR 0003). ⌘↩ marks the selected
/// line Reviewed and selects the next one.
class DesktopReviewScreen extends StatefulWidget {
  const DesktopReviewScreen({super.key, required this.engine});

  final BudgetEngine engine;

  @override
  State<DesktopReviewScreen> createState() => _DesktopReviewScreenState();
}

/// Below this content width the detail wraps under the list.
const _besideWidth = 820.0;
const _listWidth = 360.0;

class _DesktopReviewScreenState extends State<DesktopReviewScreen> {
  var _showAll = false;
  var _fetching = false;

  /// The selected line, as `transactionId/lineId`.
  String? _key;

  /// The line whose values the panel currently holds.
  String? _loadedKey;
  String? _category;
  BusinessStatus? _business;
  final _recipient = TextEditingController();
  String? _recipientError;

  BudgetState get _state => widget.engine.state;

  @override
  void dispose() {
    _recipient.dispose();
    super.dispose();
  }

  /// Every line the list shows: the Review queue, then — with All — the
  /// reviewed lines too. A line waiting on a possible bank match is always
  /// shown, so its Compare link is reachable, even though Review waits for
  /// that answer before it counts it (ticket 10).
  List<_ReviewRow> _rows(BudgetState state) {
    final newest = state.transactions.reversed.toList();
    // List.sort isn't stable, so break ties on the position added.
    final position = {for (final (i, t) in newest.indexed) t.id: i};
    newest.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      return byDate != 0 ? byDate : position[a.id]! - position[b.id]!;
    });
    return [
      for (final transaction in newest)
        if (!transaction.isTransfer &&
            (state.account(transaction.accountId)?.type.onBudget ?? true))
          if (transaction.pendingMatch != null)
            _ReviewRow(transaction, transaction.lines.first)
          else
            for (final line in transaction.lines)
              if (_showAll || !line.reviewed) _ReviewRow(transaction, line),
    ];
  }

  _ReviewRow? _selected(List<_ReviewRow> rows) {
    for (final row in rows) {
      if (row.key == _key) return row;
    }
    return rows.firstOrNull;
  }

  /// Starts the panel from a person's own values only. An Unreviewed line
  /// starts blank even when bank sync or an import filled something in.
  void _load(_ReviewRow row) {
    if (row.key == _loadedKey) return;
    _loadedKey = row.key;
    final reviewed = row.line.reviewed;
    _category = reviewed ? row.line.category : null;
    _business = reviewed ? row.line.business : null;
    _recipient.text = reviewed ? (row.line.recipient ?? '') : '';
    _recipientError = null;
  }

  bool _canMark(_ReviewRow row) =>
      !row.line.reviewed &&
      !row.pending &&
      reviewNeed(
            category: _category,
            business: _business,
            recipient: _recipient.text,
            transfer: row.transaction.isTransfer,
          ) ==
          null;

  void _mark(List<_ReviewRow> rows) {
    final row = _selected(rows);
    if (row == null || !_canMark(row)) return;
    final index = rows.indexOf(row);
    final result = widget.engine.execute(
      ReviewLine(
        transactionId: row.transaction.id,
        lineId: row.line.id,
        category: _category,
        business: _business,
        recipient: _recipient.text,
      ),
    );
    if (result is Rejected) {
      setState(() {
        _recipientError = result.reason == Rejection.accountNumberNotAllowed
            ? accountNumberMessage
            : null;
      });
      return;
    }
    _selectAfter(rows, index);
  }

  /// Skip leaves the line alone and moves to the next one.
  void _skip(List<_ReviewRow> rows) {
    final row = _selected(rows);
    if (row == null) return;
    _selectAfter(rows, rows.indexOf(row));
  }

  /// Selects the line after [index], wrapping to the first, and lets [_load]
  /// start its panel from scratch.
  void _selectAfter(List<_ReviewRow> rows, int index) {
    final next = rows.length > 1 ? rows[(index + 1) % rows.length] : null;
    setState(() {
      _key = next?.key;
      _recipientError = null;
    });
  }

  Future<void> _openPossibleMatches() async {
    await openFlow<void>(
      context,
      builder: (_) => PossibleMatchScreen(engine: widget.engine),
    );
    if (mounted) setState(() {});
  }

  Future<void> _fetch() async {
    final services = AppServicesScope.of(context);
    setState(() => _fetching = true);
    final book = await services.prefs.readSimpleFinBook();
    final outcome = await fetchByHand(
      engine: widget.engine,
      client: services.simpleFin,
      book: book,
      today: today(),
      save: services.prefs.writeSimpleFinBook,
    );
    await syncBankSchedule(services.scheduler, outcome.book);
    if (!mounted) return;
    setState(() => _fetching = false);
    final message =
        outcome.message ?? outcome.errors.firstOrNull ?? 'Bank sync is off.';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openSplit(_ReviewRow row) async {
    await openFlow<void>(
      context,
      presentation: FlowPresentation.sheet,
      builder: (_) =>
          _SplitSheet(engine: widget.engine, transactionId: row.transaction.id),
    );
    if (mounted) setState(() {});
  }

  Future<void> _pickCategory(_ReviewRow row) async {
    final picked = await pickCategory(
      context,
      _state,
      payee: row.transaction.payee,
      date: row.transaction.date,
    );
    if (picked != null) setState(() => _category = picked);
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final rows = _rows(state);
    final selected = _selected(rows);
    if (selected != null) {
      // Pin the shown line, so a fetch that adds a newer line above it
      // doesn't swap it out from under half-entered values.
      _key = selected.key;
      _load(selected);
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
            _mark(rows),
        const SingleActivator(LogicalKeyboardKey.numpadEnter, meta: true): () =>
            _mark(rows),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(_showAll ? rows.length : state.reviewQueue.length),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final list = _list(state, rows, selected);
                      final detail = selected == null
                          ? _caughtUp()
                          : _detail(state, rows, selected);
                      if (constraints.maxWidth < _besideWidth) {
                        return SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            spacing: 12,
                            children: [
                              SizedBox(height: 280, child: list),
                              detail,
                            ],
                          ),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 12,
                          children: [
                            SizedBox(width: _listWidth, child: list),
                            Expanded(
                              child: SingleChildScrollView(child: detail),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(int count) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
    child: Row(
      spacing: 12,
      children: [
        const Text(
          'Review',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        ),
        Text(
          _showAll
              ? '$count ${count == 1 ? 'line' : 'lines'}'
              : '$count to review',
          key: const ValueKey('review-count'),
          style: const TextStyle(fontSize: 13, color: Palette.muted),
        ),
        const Spacer(),
        SizedBox(
          width: 210,
          child: Segmented<bool>(
            options: const [(false, 'To review'), (true, 'All')],
            selected: _showAll,
            onChanged: (all) => setState(() {
              _showAll = all;
              _key = null;
            }),
          ),
        ),
        OutlinedButton.icon(
          key: const ValueKey('review-fetch'),
          onPressed: _fetching ? null : _fetch,
          icon: const Icon(Icons.sync, size: 16),
          label: Text(_fetching ? 'Fetching…' : 'Fetch from bank'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            textStyle: const TextStyle(
              fontFamily: sansFamily,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _list(
    BudgetState state,
    List<_ReviewRow> rows,
    _ReviewRow? selected,
  ) => CardBox(
    key: const ValueKey('review-list'),
    padding: EdgeInsets.zero,
    child: rows.isEmpty
        ? const Padding(
            padding: EdgeInsets.all(18),
            child: Text(
              'Nothing to review.',
              style: TextStyle(fontSize: 14, color: Palette.muted),
            ),
          )
        : ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: rows.length,
            itemBuilder: (context, i) => _ListRow(
              row: rows[i],
              state: state,
              selected: identical(rows[i], selected),
              onTap: () => setState(() => _key = rows[i].key),
            ),
          ),
  );

  Widget _caughtUp() => const CardBox(
    padding: EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        Text(
          'All caught up',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        Text(
          'Every line has been reviewed.',
          style: TextStyle(fontSize: 14, color: Palette.muted),
        ),
      ],
    ),
  );

  Widget _detail(BudgetState state, List<_ReviewRow> rows, _ReviewRow row) {
    final transaction = row.transaction;
    final line = row.line;
    final transfer = transaction.isTransfer;
    final reviewed = line.reviewed;
    final pending = row.pending;
    final need = reviewNeed(
      category: _category,
      business: _business,
      recipient: _recipient.text,
      transfer: transfer,
    );
    final payee = transaction.payee.isEmpty ? 'No payee' : transaction.payee;
    return CardBox(
      key: const ValueKey('review-detail'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 14,
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
                      payee,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      [
                        formatDay(transaction.date),
                        state.account(transaction.accountId)?.name ?? '',
                        if (transaction.isSplit)
                          'line ${transaction.lines.indexOf(line) + 1} '
                              'of ${transaction.lines.length}',
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 13,
                        color: Palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                formatSigned(line.amount),
                style: amountStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          // Bank sync put the line back in Review because its amount
          // changed (ticket 10).
          if (line.note case final note?) _bankNote(note),
          if (pending) _possibleMatchWarning(),
          if (reviewed)
            _reviewedValues(state, row)
          else if (!pending) ...[
            LabeledField(
              label: 'Category',
              child: OutlinedButton(
                key: const ValueKey('review-category'),
                onPressed: () => _pickCategory(row),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  side: BorderSide(
                    color: _category == null
                        ? Palette.problemText
                        : Palette.fieldBorder,
                    width: _category == null ? 1.5 : 1,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _category == null
                            ? 'Choose a category'
                            : categoryName(state, _category),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: _category == null
                              ? Palette.muted
                              : Palette.ink,
                        ),
                      ),
                    ),
                    const Icon(Icons.keyboard_arrow_down, size: 18),
                  ],
                ),
              ),
            ),
            if (transfer)
              const Hint(
                'A transfer isn’t spending, so it skips Personal or '
                'Business.',
              )
            else
              BusinessField(
                tags: state.businessTags,
                value: _business,
                onChanged: (status) => setState(() => _business = status),
              ),
            if (_business case Business(tag: giftsTag))
              LabeledField(
                label: 'Recipient',
                child: TextField(
                  key: const ValueKey('review-recipient'),
                  controller: _recipient,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Who received the gift',
                    errorText: _recipientError,
                    helperText:
                        'Deductible gifts are capped at \$25 per '
                        'recipient each tax year.',
                    helperStyle: const TextStyle(
                      fontSize: 12,
                      color: Palette.muted,
                    ),
                  ),
                ),
              ),
          ],
          Row(
            spacing: 8,
            children: [
              if (!reviewed) ...[
                OutlinedButton(
                  key: const ValueKey('review-skip'),
                  onPressed: () => _skip(rows),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                  child: const Text('Skip'),
                ),
                if (!pending)
                  TextButton(
                    key: const ValueKey('review-split'),
                    onPressed: () => _openSplit(row),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      foregroundColor: Palette.teal,
                      textStyle: const TextStyle(
                        fontFamily: sansFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    child: const Text('Split'),
                  ),
                if (!pending)
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('review-mark'),
                      onPressed: _canMark(row) ? () => _mark(rows) : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        disabledBackgroundColor: const Color(0xFFD5D8D2),
                        disabledForegroundColor: const Color(0xFF4A4F54),
                      ),
                      child: const Text('Mark reviewed'),
                    ),
                  ),
              ],
            ],
          ),
          if (!reviewed && !pending && need != null)
            Text(
              switch (need) {
                ReviewNeed.category => 'Pick a category to finish this line',
                ReviewNeed.businessStatus =>
                  'Choose Personal or Business to finish this line',
                ReviewNeed.businessTag =>
                  'Choose a Business Tag to finish this line',
                ReviewNeed.recipient =>
                  'Add who received the gift to finish this line',
              },
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Palette.problemText),
            ),
        ],
      ),
    );
  }

  Widget _bankNote(String note) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: Palette.problemPill,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        const Icon(
          Icons.change_circle_outlined,
          size: 18,
          color: Palette.problemText,
        ),
        Expanded(
          child: Text(
            note,
            key: const ValueKey('review-bank-note'),
            style: const TextStyle(
              fontSize: 13,
              color: Palette.problemText,
              height: 1.35,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _possibleMatchWarning() => Container(
    key: const ValueKey('review-possible-match'),
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: Palette.problemPill,
      border: Border.all(color: Palette.problemBorder),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      spacing: 10,
      children: [
        const Icon(Icons.compare_arrows, size: 20, color: Palette.bankText),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Text(
                'Possible match',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              Text(
                'A bank charge looks like this line.',
                style: TextStyle(fontSize: 13, color: Palette.inkSoft),
              ),
            ],
          ),
        ),
        OutlinedButton(
          key: const ValueKey('review-compare'),
          onPressed: _openPossibleMatches,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          child: const Text('Compare'),
        ),
      ],
    ),
  );

  Widget _reviewedValues(BudgetState state, _ReviewRow row) {
    final line = row.line;
    final business = line.business;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Row(
          spacing: 8,
          children: const [
            Icon(
              Icons.check_circle_outline,
              size: 18,
              color: Palette.positiveText,
            ),
            Text(
              'Reviewed',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Palette.positiveText,
              ),
            ),
          ],
        ),
        _ReadOnlyRow(
          label: 'Category',
          value: categoryName(state, line.category),
        ),
        _ReadOnlyRow(
          label: 'Personal or business',
          value: switch (business) {
            Business(:final tag) => 'Business · $tag',
            Personal() => 'Personal',
            null => 'Not set',
          },
        ),
        if (business case Business(tag: giftsTag))
          _ReadOnlyRow(label: 'Recipient', value: line.recipient ?? 'Not set'),
      ],
    );
  }
}

/// One line in the desktop Review list.
final class _ReviewRow {
  const _ReviewRow(this.transaction, this.line);

  final Transaction transaction;
  final TransactionLine line;

  String get key => '${transaction.id}/${line.id}';

  /// Waiting on a possible bank match, so it is not part of the queue but
  /// still needs a person's answer.
  bool get pending => transaction.pendingMatch != null;
}

class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.row,
    required this.state,
    required this.selected,
    required this.onTap,
  });

  final _ReviewRow row;
  final BudgetState state;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final transaction = row.transaction;
    return InkWell(
      key: ValueKey('review-row-${row.key}'),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 62),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Palette.zeroPill : null,
          border: const Border(top: BorderSide(color: Palette.divider)),
        ),
        child: Row(
          spacing: 10,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    transaction.payee.isEmpty ? 'No payee' : transaction.payee,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '${formatDay(transaction.date)} · '
                    '${state.account(transaction.accountId)?.name ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Palette.muted),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: 2,
              children: [
                Text(
                  formatSigned(row.line.amount),
                  style: amountStyle(fontSize: 13),
                ),
                if (row.pending)
                  const Text(
                    'Possible match',
                    style: TextStyle(fontSize: 11, color: Palette.bankText),
                  )
                else if (row.line.reviewed)
                  const Text(
                    'Reviewed',
                    style: TextStyle(fontSize: 11, color: Palette.positiveText),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A label and its value in the reviewed line's read-only summary.
class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 12,
    children: [
      SizedBox(
        width: 150,
        child: Text(
          label,
          style: const TextStyle(fontSize: 13, color: Palette.muted),
        ),
      ),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
    ],
  );
}

/// The Split sheet (ticket 64): one purchase divided across Categories. The
/// lines always add up to the transaction's amount before Save is allowed.
class _SplitSheet extends StatefulWidget {
  const _SplitSheet({required this.engine, required this.transactionId});

  final BudgetEngine engine;
  final String transactionId;

  @override
  State<_SplitSheet> createState() => _SplitSheetState();
}

class _SplitSheetState extends State<_SplitSheet> {
  late final Transaction _saved = widget.engine.state.transaction(
    widget.transactionId,
  )!;
  late final bool _outflow = _saved.amount.isNegative;
  late final Money _magnitude = _outflow ? -_saved.amount : _saved.amount;

  /// An Unreviewed line starts blank, like the detail panel, so the sheet
  /// never shows values an import or an app filled in (ADR 0003).
  late final List<LineDraft> _lines = [
    for (final line in _saved.lines)
      line.reviewed
          ? LineDraft.of(line, outflow: _outflow)
          : LineDraft(
              id: line.id,
              amount: _outflow ? -line.amount : line.amount,
              memo: line.memo,
            ),
  ];
  String? _error;

  Money get _left =>
      _lines.fold<Money>(_magnitude, (left, line) => left - line.amount);

  Future<void> _editLine(int index) async {
    final edit = await showLineEditor(
      context,
      state: widget.engine.state,
      line: _lines[index],
      payee: _saved.payee,
      date: _saved.date,
      canRemove: _lines.length > 1,
    );
    if (edit == null || !mounted) return;
    setState(() {
      if (edit.line case final line?) {
        _lines[index] = line;
      } else {
        _lines.removeAt(index);
      }
    });
  }

  Future<void> _addLine() async {
    final left = _left;
    final edit = await showLineEditor(
      context,
      state: widget.engine.state,
      line: LineDraft(amount: left.isPositive ? left : Money.zero),
      payee: _saved.payee,
      date: _saved.date,
      canRemove: false,
    );
    if (edit?.line case final line?) setState(() => _lines.add(line));
  }

  /// [draft] as saved. An Unreviewed line the person left blank keeps the
  /// values it had, and the engine leaves it Unreviewed.
  LineInput _input(LineDraft draft) {
    final saved = _saved.lines.where((line) => line.id == draft.id).firstOrNull;
    if (saved == null ||
        saved.reviewed ||
        draft.category != null ||
        draft.business != null) {
      return draft.toInput(outflow: _outflow);
    }
    return LineInput(
      id: saved.id,
      amount: _outflow ? -draft.amount : draft.amount,
      category: saved.category,
      business: saved.business,
      memo: draft.memo,
      recipient: saved.recipient,
    );
  }

  void _save() {
    final result = widget.engine.execute(
      EditTransaction(
        transactionId: _saved.id,
        amount: _saved.amount,
        lines: [for (final line in _lines) _input(line)],
      ),
    );
    if (result case Rejected(:final reason) when reason != Rejection.noChange) {
      setState(
        () => _error = switch (reason) {
          Rejection.reconciledNeedsConfirmation =>
            'This transaction is reconciled with your bank. Change it from '
                'its account.',
          _ => 'That split could not be saved.',
        },
      );
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 14,
        children: [
          const Text(
            'Split',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          Hint(
            '${_magnitude.formatDollars()} in '
            '${_lines.length == 1 ? 'one line' : '${_lines.length} lines'}. '
            'The lines must add up to the total.',
          ),
          SplitLinesCard(
            state: widget.engine.state,
            lines: _lines,
            left: _left,
            outflow: _outflow,
            onEdit: _editLine,
            onAdd: _addLine,
          ),
          if (_error case final error?)
            Text(
              error,
              key: const ValueKey('split-error'),
              style: const TextStyle(fontSize: 13, color: Palette.problemText),
            ),
          Row(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                ),
                child: const Text('Cancel'),
              ),
              Expanded(
                child: FilledButton(
                  onPressed: _left == Money.zero ? _save : null,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
