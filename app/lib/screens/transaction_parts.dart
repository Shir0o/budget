import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';
import 'category_picker.dart';

// Pieces shared by the New transaction and Transaction screens.

/// One line being edited. [amount] is how much of the transaction it takes,
/// in the transaction's direction, so it is positive for an outflow too.
class LineDraft {
  LineDraft({
    this.id,
    required this.amount,
    this.category,
    this.business,
    this.memo = '',
    this.recipient,
  });

  /// Starts from a saved line of a transaction going [outflow].
  LineDraft.of(TransactionLine line, {required bool outflow})
    : id = line.id,
      amount = outflow ? -line.amount : line.amount,
      category = line.category,
      business = line.business,
      memo = line.memo,
      recipient = line.recipient;

  final String? id;
  Money amount;
  String? category;
  BusinessStatus? business;
  String memo;

  /// A gift line's recipient, kept through edits.
  String? recipient;

  /// Whether saving it by hand marks it Reviewed.
  bool get complete =>
      reviewNeed(
        category: category,
        business: business,
        recipient: recipient,
      ) ==
      null;

  LineInput toInput({required bool outflow}) => LineInput(
    id: id,
    amount: outflow ? -amount : amount,
    category: category,
    business: business,
    memo: memo,
    recipient: recipient,
  );
}

/// A business status with a tag, if Business. [Business] with a blank tag
/// means Business was tapped but no tag chosen yet.
bool isSet(BusinessStatus? status) => switch (status) {
  null => false,
  Personal() => true,
  Business(:final tag) => tag.isNotEmpty,
};

String categoryName(BudgetState state, String? id) => switch (id) {
  null => 'Uncategorized',
  readyToAssignCategory => 'Ready to Assign',
  final id => state.category(id)?.name ?? 'Unknown',
};

/// Opens the Category picker for a transaction to [payee] dated [date].
Future<String?> pickCategory(
  BuildContext context,
  BudgetState state, {
  required String payee,
  required CivilDate date,
}) => showCategoryPicker(
  context,
  state: state,
  month: CalendarMonth.of(date),
  title: payee.trim().isEmpty ? 'Category' : 'Category for ${payee.trim()}',
  readyToAssignLabel: 'Ready to Assign (income)',
  recent: state.recentCategories(),
);

/// Personal or Business, then a Business Tag when Business.
class BusinessField extends StatelessWidget {
  const BusinessField({
    super.key,
    required this.tags,
    required this.value,
    required this.onChanged,
  });

  /// The presets and any custom tags.
  final List<BusinessTag> tags;
  final BusinessStatus? value;
  final ValueChanged<BusinessStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        Segmented<bool>(
          options: const [(false, 'Personal'), (true, 'Business')],
          selected: value == null ? null : value is Business,
          onChanged: (business) {
            if (business && value is! Business) {
              onChanged(const Business(''));
            } else if (!business) {
              onChanged(const Personal());
            }
          },
        ),
        if (value is Business)
          Wrap(
            spacing: 6,
            children: [
              for (final tag in tags)
                SelectChip(
                  label: tag.name,
                  selected: value.tag == tag.name,
                  onTap: () => onChanged(Business(tag.name)),
                ),
            ],
          ),
      ],
    );
  }
}

/// The Split lines card: Left to split, each line, and Add line.
class SplitLinesCard extends StatelessWidget {
  const SplitLinesCard({
    super.key,
    required this.state,
    required this.lines,
    required this.left,
    required this.outflow,
    required this.onEdit,
    required this.onAdd,
  });

  final BudgetState state;
  final List<LineDraft> lines;
  final Money left;
  final bool outflow;
  final ValueChanged<int> onEdit;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => CardBox(
    padding: EdgeInsets.zero,
    child: Material(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    lines.length > 1 ? 'Split lines' : 'Line',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text.rich(
                  TextSpan(
                    text: 'Left to split ',
                    children: [
                      TextSpan(
                        text: left.format(),
                        style: amountStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    color: left == Money.zero
                        ? Palette.positiveText
                        : Palette.problemText,
                  ),
                ),
              ],
            ),
          ),
          for (final (i, line) in lines.indexed)
            _LineRow(
              state: state,
              line: line,
              outflow: outflow,
              onTap: () => onEdit(i),
            ),
          InkWell(
            onTap: onAdd,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Palette.divider)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 6,
                children: [
                  Icon(Icons.add, size: 16, color: Palette.teal),
                  Text(
                    'Add line',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Palette.teal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.state,
    required this.line,
    required this.outflow,
    required this.onTap,
  });

  final BudgetState state;
  final LineDraft line;
  final bool outflow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final business = line.business;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Palette.divider)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    categoryName(state, line.category),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: line.category == null
                          ? Palette.problemText
                          : Palette.ink,
                    ),
                  ),
                ),
                Text(
                  (outflow ? -line.amount : line.amount).format(),
                  style: amountStyle(),
                ),
              ],
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                switch (business) {
                  Business(:final tag) when tag.isNotEmpty => _Tag(
                    'Business · $tag',
                    background: Palette.ink,
                    foreground: Palette.background,
                  ),
                  Personal() => const _Tag(
                    'Personal',
                    background: Palette.zeroPill,
                    foreground: Palette.inkSoft,
                  ),
                  _ => const _Tag(
                    'No business status',
                    background: Palette.problemPill,
                    foreground: Palette.problemText,
                  ),
                },
                line.complete
                    ? const _Tag(
                        'Reviewed',
                        background: Palette.positivePill,
                        foreground: Palette.positiveText,
                      )
                    : const _Tag(
                        'Unreviewed',
                        background: Palette.problemPill,
                        foreground: Palette.problemText,
                      ),
              ],
            ),
            if (line.memo.isNotEmpty)
              Text(
                'Memo: ${line.memo}',
                style: const TextStyle(fontSize: 12, color: Palette.muted),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {required this.background, required this.foreground});

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
    height: 26,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Center(
      widthFactor: 1,
      child: Text(text, style: TextStyle(fontSize: 12, color: foreground)),
    ),
  );
}

/// What the line editor returns: the edited line, or null to remove it.
typedef LineEdit = ({LineDraft? line});

/// Edits one split line: amount, Category, business status and memo.
/// Returns null when dismissed.
Future<LineEdit?> showLineEditor(
  BuildContext context, {
  required BudgetState state,
  required LineDraft line,
  required String payee,
  required CivilDate date,
  required bool canRemove,
}) => showModalBottomSheet<LineEdit>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Palette.card,
  builder: (_) => _LineEditor(
    state: state,
    line: line,
    payee: payee,
    date: date,
    canRemove: canRemove,
  ),
);

class _LineEditor extends StatefulWidget {
  const _LineEditor({
    required this.state,
    required this.line,
    required this.payee,
    required this.date,
    required this.canRemove,
  });

  final BudgetState state;
  final LineDraft line;
  final String payee;
  final CivilDate date;
  final bool canRemove;

  @override
  State<_LineEditor> createState() => _LineEditorState();
}

class _LineEditorState extends State<_LineEditor> {
  late final _amount = TextEditingController(
    text: widget.line.amount == Money.zero ? '' : widget.line.amount.format(),
  );
  late final _memo = TextEditingController(text: widget.line.memo);
  late String? _category = widget.line.category;
  late BusinessStatus? _business = widget.line.business;
  String? _amountError;
  String? _memoError;
  String? _businessError;

  @override
  void dispose() {
    _amount.dispose();
    _memo.dispose();
    super.dispose();
  }

  void _done() {
    final amount = _amount.text.trim().isEmpty
        ? Money.zero
        : Money.tryParse(_amount.text);
    setState(() {
      _amountError = amount == null || amount.isNegative
          ? 'Enter an amount like 1,234.56'
          : null;
      _memoError = containsSensitiveNumber(_memo.text)
          ? accountNumberMessage
          : null;
      _businessError = _business is Business && !isSet(_business)
          ? 'Choose a Business Tag'
          : null;
    });
    if (_amountError != null || _memoError != null || _businessError != null) {
      return;
    }
    Navigator.of(context).pop((
      line: LineDraft(
        id: widget.line.id,
        amount: amount!,
        category: _category,
        business: _business,
        memo: _memo.text.trim(),
        recipient: widget.line.recipient,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.9,
    ),
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        18,
        18,
        18,
        22 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Split line',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          LabeledField(
            label: 'Amount',
            child: TextField(
              key: const ValueKey('line-amount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: amountStyle(fontSize: 18, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: '0.00',
                errorText: _amountError,
              ),
            ),
          ),
          const SizedBox(height: 12),
          LabeledField(
            label: 'Category',
            child: OutlinedButton(
              key: const ValueKey('line-category'),
              onPressed: () async {
                final picked = await pickCategory(
                  context,
                  widget.state,
                  payee: widget.payee,
                  date: widget.date,
                );
                if (picked != null) setState(() => _category = picked);
              },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.centerLeft,
              ),
              child: Text(
                _category == null
                    ? 'Choose a Category'
                    : categoryName(widget.state, _category),
              ),
            ),
          ),
          const SizedBox(height: 12),
          BusinessField(
            tags: widget.state.businessTags,
            value: _business,
            onChanged: (status) => setState(() => _business = status),
          ),
          if (_businessError case final error?)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                error,
                style: const TextStyle(
                  fontSize: 12,
                  color: Palette.problemText,
                ),
              ),
            ),
          const SizedBox(height: 12),
          LabeledField(
            label: 'Memo',
            child: TextField(
              key: const ValueKey('line-memo'),
              controller: _memo,
              style: const TextStyle(fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Optional',
                errorText: _memoError,
                helperText: _memoError == null ? accountNumberMessage : null,
                helperStyle: const TextStyle(
                  fontSize: 12,
                  color: Palette.muted,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _done, child: const Text('Done')),
          if (widget.canRemove)
            TextButton(
              onPressed: () => Navigator.of(context).pop((line: null)),
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                foregroundColor: Palette.problemText,
              ),
              child: const Text('Remove line'),
            ),
        ],
      ),
    ),
  );
}
