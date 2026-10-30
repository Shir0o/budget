import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../settings_widgets.dart';
import '../theme.dart';
import '../widgets.dart';
import 'business_parts.dart';
import 'edit_business_tag_screen.dart';

/// Business tags (canvas: Business tags): the 19 presets and any custom
/// tags, with the business-use % a tag needs for the chosen tax year. A tag
/// is independent of the line's Category, and only a person sets it.
class BusinessTagsScreen extends StatefulWidget {
  const BusinessTagsScreen({super.key, required this.engine});

  final BudgetEngine engine;

  @override
  State<BusinessTagsScreen> createState() => _BusinessTagsScreenState();
}

class _BusinessTagsScreenState extends State<BusinessTagsScreen> {
  late var _year = today().year;

  BudgetState get _state => widget.engine.state;

  Future<void> _add() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditBusinessTagScreen(engine: widget.engine),
      ),
    );
    setState(() {}); // The engine's state may have changed.
  }

  Future<void> _setBusinessUse(BusinessTag tag) async {
    final percent = await showDialog<int>(
      context: context,
      builder: (_) => _PercentDialog(
        tag: tag,
        year: _year,
        current: _state.businessUse(tag.name, _year),
      ),
    );
    if (percent == null || !mounted) return;
    widget.engine.execute(
      SetBusinessUse(tag: tag.name, year: _year, percent: percent),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final tags = state.businessTags;
    final years = businessYears(state);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BackHeader(title: 'Business tags'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
                    child: Hint(
                      'A Business Tag marks a transaction line as reportable '
                      'self-employment income or an expense. It is '
                      'independent of the line’s Category, and only you can '
                      'set it.',
                    ),
                  ),
                  CardBox(
                    child: BusinessYearPicker(
                      years: years,
                      year: _year,
                      onChanged: (year) => setState(() => _year = year),
                    ),
                  ),
                  const SizedBox(height: 12),
                  CardBox(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (i, tag) in tags.indexed)
                          _TagRow(
                            tag: tag,
                            percent: state.businessUse(tag.name, _year),
                            first: i == 0,
                            onTap: tag.rule is BusinessUseDeduction
                                ? () => _setBusinessUse(tag)
                                : null,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    key: const ValueKey('add-business-tag'),
                    onPressed: _add,
                    child: const Text('Add tag'),
                  ),
                  const SizedBox(height: 12),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Hint(
                      'Meals deduct 50%. Gifts deduct up to \$25 per '
                      'recipient each tax year. A business-use % is set per '
                      'tag and tax year.',
                    ),
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

class _TagRow extends StatelessWidget {
  const _TagRow({
    required this.tag,
    required this.percent,
    required this.first,
    required this.onTap,
  });

  final BusinessTag tag;
  final int? percent;
  final bool first;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: first
            ? null
            : const Border(top: BorderSide(color: Palette.divider)),
      ),
      child: Row(
        spacing: 12,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tag.name, style: const TextStyle(fontSize: 15)),
                Text(
                  '${scheduleCLineText(tag.line)} · ${tag.rule.label}',
                  style: const TextStyle(fontSize: 12, color: Palette.muted),
                ),
              ],
            ),
          ),
          if (onTap != null)
            TextButton(
              key: ValueKey('business-use-${tag.name}'),
              onPressed: onTap,
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                foregroundColor: percent == null
                    ? Palette.problemText
                    : Palette.teal,
              ),
              child: Text(percent == null ? 'Set %' : '$percent%'),
            ),
        ],
      ),
    ),
  );
}

/// Sets one tag's business-use % for one tax year.
class _PercentDialog extends StatefulWidget {
  const _PercentDialog({
    required this.tag,
    required this.year,
    required this.current,
  });

  final BusinessTag tag;
  final int year;
  final int? current;

  @override
  State<_PercentDialog> createState() => _PercentDialogState();
}

class _PercentDialogState extends State<_PercentDialog> {
  late final _percent = TextEditingController(
    text: widget.current?.toString() ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _percent.dispose();
    super.dispose();
  }

  void _done() {
    final value = int.tryParse(_percent.text.trim());
    if (value == null || value < 0 || value > 100) {
      setState(() => _error = 'Enter a whole number from 0 to 100');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.tag.name}, ${widget.year}'),
    content: TextField(
      key: const ValueKey('business-use-percent'),
      controller: _percent,
      autofocus: true,
      keyboardType: TextInputType.number,
      style: amountStyle(fontSize: 15),
      decoration: InputDecoration(
        labelText: 'Business use %',
        suffixText: '%',
        errorText: _error,
      ),
      onSubmitted: (_) => _done(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      TextButton(onPressed: _done, child: const Text('Save')),
    ],
  );
}
