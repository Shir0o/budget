import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';
import 'transaction_parts.dart';

/// The Business Tags shown before "All tags" (canvas: Review).
const _featuredTags = [
  'Meals',
  giftsTag,
  'Supplies',
  'Conferences & education',
  'Software & subscriptions',
];

/// Review (canvas: Review): one Unreviewed line at a time. A person sets its
/// Category and business status and taps Mark reviewed. The hint chip only
/// fills the fields, and there is no approve-all (ADR 0003).
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.engine});

  final BudgetEngine engine;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  /// The line the fields below belong to, as `transactionId/lineId`.
  String? _key;
  String? _category;
  BusinessStatus? _business;
  final _recipient = TextEditingController();
  var _allTags = false;
  String? _recipientError;

  @override
  void dispose() {
    _recipient.dispose();
    super.dispose();
  }

  /// Starts the fields from [item]'s values, which bank sync or an import
  /// may have filled in. They are not Reviewed until the person taps.
  void _load(ReviewItem item) {
    final key = '${item.transaction.id}/${item.line.id}';
    if (key == _key) return;
    _key = key;
    _category = item.line.category;
    _business = item.transaction.isTransfer ? null : item.line.business;
    _recipient.text = item.line.recipient ?? '';
    _allTags = false;
    _recipientError = null;
  }

  void _markReviewed(ReviewItem item) {
    final result = widget.engine.execute(
      ReviewLine(
        transactionId: item.transaction.id,
        lineId: item.line.id,
        category: _category,
        business: _business,
        recipient: _recipient.text,
      ),
    );
    setState(() {
      _recipientError =
          result is Rejected &&
              result.reason == Rejection.accountNumberNotAllowed
          ? accountNumberMessage
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.engine.state;
    final queue = state.reviewQueue;
    final item = queue.firstOrNull;
    if (item != null) _load(item);
    return Scaffold(
      bottomNavigationBar: MainNav(
        engine: widget.engine,
        current: MainTab.review,
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Review',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                  ),
                  if (queue.isNotEmpty)
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '1', style: amountStyle(fontSize: 14)),
                          const TextSpan(text: ' of '),
                          TextSpan(
                            text: '${queue.length}',
                            style: amountStyle(fontSize: 14),
                          ),
                        ],
                      ),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Palette.muted,
                      ),
                    ),
                ],
              ),
            ),
            if (item == null)
              const CardBox(
                padding: EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    Text(
                      'All caught up',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Every line has been reviewed.',
                      style: TextStyle(fontSize: 14, color: Palette.muted),
                    ),
                  ],
                ),
              )
            else ...[
              _lineCard(state, item),
              if (queue.length > 1) ...[
                const SizedBox(height: 12),
                _UpNext(state: state, items: queue.skip(1).take(3).toList()),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _lineCard(BudgetState state, ReviewItem item) {
    final transaction = item.transaction;
    final transfer = transaction.isTransfer;
    final hint = state.payeeHint(
      transaction.payee,
      exceptTransactionId: transaction.id,
    );
    final business = _business;
    final need = reviewNeed(
      category: _category,
      business: business,
      recipient: _recipient.text,
      transfer: transfer,
    );
    final account = state.account(transaction.accountId)?.name ?? '';
    final payee = transaction.payee.isEmpty ? 'No payee' : transaction.payee;
    return CardBox(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
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
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      [
                        formatDay(transaction.date),
                        account,
                        if (transaction.isSplit)
                          'line ${transaction.lines.indexOf(item.line) + 1} '
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
                formatSigned(item.line.amount),
                style: amountStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          if (hint != null)
            Align(
              alignment: Alignment.centerLeft,
              child: _HintChip(
                label: 'Last time: ${_describe(state, hint)}',
                onTap: () => setState(() {
                  _category = hint.category;
                  if (!transfer) _business = hint.business;
                }),
              ),
            ),
          LabeledField(
            label: 'Category',
            child: OutlinedButton(
              key: const ValueKey('review-category'),
              onPressed: () async {
                final picked = await pickCategory(
                  context,
                  state,
                  payee: transaction.payee,
                  date: transaction.date,
                );
                if (picked != null) setState(() => _category = picked);
              },
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
                        color: _category == null ? Palette.muted : Palette.ink,
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
            _businessField(state, item),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              FilledButton(
                onPressed: need == null ? () => _markReviewed(item) : null,
                style: FilledButton.styleFrom(
                  disabledBackgroundColor: const Color(0xFFD5D8D2),
                  disabledForegroundColor: const Color(0xFF4A4F54),
                ),
                child: const Text('Mark reviewed'),
              ),
              if (need != null)
                Text(
                  switch (need) {
                    ReviewNeed.category =>
                      'Pick a category to finish this line',
                    ReviewNeed.businessStatus =>
                      'Choose Personal or Business to finish this line',
                    ReviewNeed.businessTag =>
                      'Choose a Business Tag to finish this line',
                    ReviewNeed.recipient =>
                      'Add who received the gift to finish this line',
                  },
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Palette.problemText,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _businessField(BudgetState state, ReviewItem item) {
    final business = _business;
    final tag = business is Business ? business.tag : null;
    final tags = _allTags
        ? [for (final preset in state.businessTags) preset.name]
        : [
            ..._featuredTags,
            if (tag != null && tag.isNotEmpty && !_featuredTags.contains(tag))
              tag,
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        const FieldLabel('Personal or business'),
        Segmented<bool>(
          options: const [(false, 'Personal'), (true, 'Business')],
          selected: business == null ? null : business is Business,
          onChanged: (isBusiness) => setState(() {
            if (isBusiness && business is! Business) {
              _business = const Business('');
            } else if (!isBusiness) {
              _business = const Personal();
            }
          }),
        ),
        if (business is Business) ...[
          Wrap(
            spacing: 8,
            children: [
              for (final t in tags)
                // SelectChip fills the width it is given; keep it pill-sized.
                IntrinsicWidth(
                  child: SelectChip(
                    label: t,
                    selected: t == tag,
                    onTap: () => setState(() => _business = Business(t)),
                  ),
                ),
              if (!_allTags)
                TextButton(
                  onPressed: () => setState(() => _allTags = true),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    foregroundColor: Palette.teal,
                    textStyle: const TextStyle(
                      fontFamily: sansFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  child: const Text('All tags'),
                ),
            ],
          ),
          if (tag == 'Meals')
            Text.rich(
              TextSpan(
                text: 'Meals: 50% deductible · ',
                children: [
                  TextSpan(
                    // Rounded down to the cent.
                    text: Money(item.line.amount.cents.abs() ~/ 2)
                        .formatDollars(),
                    style: amountStyle(fontSize: 12),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 12, color: Palette.muted),
            ),
          if (tag == giftsTag)
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
      ],
    );
  }

  String _describe(BudgetState state, PayeeHint hint) {
    final category = categoryName(state, hint.category);
    return switch (hint.business) {
      Business(:final tag) => '$category · Business ($tag)',
      Personal() => '$category · Personal',
      null => category,
    };
  }
}

/// The dashed "Last time" chip. Tapping fills the fields; it never marks
/// the line Reviewed.
class _HintChip extends StatelessWidget {
  const _HintChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F8F5),
          border: Border.all(color: const Color(0xFF8C928A)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            const Icon(Icons.history, size: 16, color: Palette.muted),
            Flexible(child: Text(label, style: const TextStyle(fontSize: 13))),
          ],
        ),
      ),
    ),
  );
}

/// The next few Unreviewed lines.
class _UpNext extends StatelessWidget {
  const _UpNext({required this.state, required this.items});

  final BudgetState state;
  final List<ReviewItem> items;

  @override
  Widget build(BuildContext context) => CardBox(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text(
            'Up next',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Palette.muted,
            ),
          ),
        ),
        for (final item in items)
          Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Palette.divider)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.transaction.payee.isEmpty
                            ? 'No payee'
                            : item.transaction.payee,
                        style: const TextStyle(fontSize: 14),
                      ),
                      Text(
                        '${formatDay(item.transaction.date)} · '
                        '${state.account(item.transaction.accountId)?.name ?? ''}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Palette.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  formatSigned(item.line.amount),
                  style: amountStyle(fontSize: 14),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
