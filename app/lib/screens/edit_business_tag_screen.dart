import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';
import 'business_parts.dart';

/// The four deduction rules a person can pick for a custom tag (ticket 04).
enum _RuleKind { full, percent, businessUse, giftCap }

/// Adds a custom Business Tag: its name, its Schedule C line and its
/// deduction rule. The 19 presets can't be changed.
class EditBusinessTagScreen extends StatefulWidget {
  const EditBusinessTagScreen({super.key, required this.engine});

  final BudgetEngine engine;

  @override
  State<EditBusinessTagScreen> createState() => _EditBusinessTagScreenState();
}

class _EditBusinessTagScreenState extends State<EditBusinessTagScreen> {
  final _name = TextEditingController();
  final _percent = TextEditingController(text: '50');
  final _cap = TextEditingController(text: '25.00');
  var _line = '27a (other)';
  var _kind = _RuleKind.full;
  String? _nameError;
  String? _percentError;
  String? _capError;

  @override
  void dispose() {
    _name.dispose();
    _percent.dispose();
    _cap.dispose();
    super.dispose();
  }

  int? get _percentValue => int.tryParse(_percent.text.trim());

  Money? get _capValue => Money.tryParse(_cap.text);

  DeductionRule? get _rule => switch (_kind) {
    _RuleKind.full => const FullDeduction(),
    _RuleKind.percent => switch (_percentValue) {
      final percent? when percent >= 1 && percent <= 100 => PercentDeduction(
        percent,
      ),
      _ => null,
    },
    _RuleKind.businessUse => const BusinessUseDeduction(),
    _RuleKind.giftCap => switch (_capValue) {
      final cap? when cap.isPositive => PerRecipientCapDeduction(cap),
      _ => null,
    },
  };

  void _save() {
    final rule = _rule;
    setState(() {
      _nameError = _name.text.trim().isEmpty ? 'Name the tag' : null;
      _percentError = _kind == _RuleKind.percent && rule == null
          ? 'Enter a whole number from 1 to 100'
          : null;
      _capError = _kind == _RuleKind.giftCap && rule == null
          ? 'Enter an amount above 0.00'
          : null;
    });
    if (_nameError != null || _percentError != null || _capError != null) {
      return;
    }
    final result = widget.engine.execute(
      CreateBusinessTag(name: _name.text, line: _line, rule: rule!),
    );
    switch (result) {
      case Accepted():
        Navigator.of(context).pop();
      case Rejected(reason: Rejection.businessTagExists):
        setState(() => _nameError = 'That tag already exists');
      case Rejected():
        setState(() => _nameError = 'Check the tag’s details');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormHeader(
            title: 'New tag',
            onClose: () => Navigator.of(context).pop(),
            onSave: _save,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                CardBox(
                  child: LabeledField(
                    label: 'Name',
                    child: TextField(
                      key: const ValueKey('business-tag-name'),
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      style: const TextStyle(fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'Like Studio rent',
                        errorText: _nameError,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                CardBox(
                  child: LabeledField(
                    label: 'Schedule C line',
                    child: DropdownButtonFormField<String>(
                      key: const ValueKey('business-line'),
                      initialValue: _line,
                      isExpanded: true,
                      style: const TextStyle(fontSize: 15, color: Palette.ink),
                      items: [
                        for (final line in scheduleCLines)
                          DropdownMenuItem(
                            value: line,
                            child: Text(scheduleCLineText(line)),
                          ),
                      ],
                      onChanged: (line) {
                        if (line != null) setState(() => _line = line);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                CardBox(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 10,
                    children: [
                      const FieldLabel('Deduction rule'),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final (kind, label) in const [
                            (_RuleKind.full, '100%'),
                            (_RuleKind.percent, 'A percent'),
                            (_RuleKind.businessUse, 'Business use %'),
                            (_RuleKind.giftCap, 'Gift cap'),
                          ])
                            SelectChip(
                              label: label,
                              selected: _kind == kind,
                              onTap: () => setState(() => _kind = kind),
                            ),
                        ],
                      ),
                      if (_kind == _RuleKind.percent)
                        LabeledField(
                          label: 'Percent deductible',
                          child: TextField(
                            key: const ValueKey('business-tag-percent'),
                            controller: _percent,
                            keyboardType: TextInputType.number,
                            style: amountStyle(fontSize: 15),
                            decoration: InputDecoration(
                              suffixText: '%',
                              errorText: _percentError,
                            ),
                          ),
                        ),
                      if (_kind == _RuleKind.giftCap)
                        LabeledField(
                          label: 'Cap per recipient',
                          child: TextField(
                            key: const ValueKey('business-tag-cap'),
                            controller: _cap,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            style: amountStyle(fontSize: 15),
                            decoration: InputDecoration(errorText: _capError),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Hint(
                    'A custom tag reports on the Schedule C line you pick. '
                    'The app produces records, not tax advice.',
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
