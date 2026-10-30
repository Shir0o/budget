import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../budget_library.dart';
import '../theme.dart';
import '../widgets.dart';
import 'budget_screen.dart';

const _typeLabels = {
  AccountType.checking: 'Checking',
  AccountType.savings: 'Savings',
  AccountType.cash: 'Cash',
  AccountType.creditCard: 'Credit card',
  AccountType.tracking: 'Tracking',
};

/// Add account (canvas: AddAccount). On first run, [newBudgetName] is set
/// and the budget is created together with its first account.
class AddAccountScreen extends StatefulWidget {
  const AddAccountScreen({super.key, required this.engine, this.newBudgetName});

  final BudgetEngine engine;
  final String? newBudgetName;

  @override
  State<AddAccountScreen> createState() => _AddAccountScreenState();
}

class _AddAccountScreenState extends State<AddAccountScreen> {
  var _type = AccountType.checking;
  final _name = TextEditingController(text: _typeLabels[AccountType.checking]);
  var _nameEdited = false;
  final _balance = TextEditingController();
  var _asOf = today();
  String? _nameError;
  String? _balanceError;
  var _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    super.dispose();
  }

  void _selectType(AccountType type) => setState(() {
    _type = type;
    if (!_nameEdited) _name.text = _typeLabels[type]!;
  });

  Future<void> _save() async {
    if (_saving) return;
    final balance = _balance.text.trim().isEmpty
        ? Money.zero
        : Money.tryParse(_balance.text);
    setState(() {
      _nameError = _name.text.trim().isEmpty ? 'Name the account' : null;
      _balanceError = balance == null ? 'Enter an amount like 1,234.56' : null;
    });
    if (_nameError != null || balance == null) return;

    final engine = widget.engine;
    final library = BudgetLibraryScope.of(context);
    final newBudgetName = widget.newBudgetName;
    if (newBudgetName != null && engine.state.budget == null) {
      engine.execute(CreateBudget(name: newBudgetName));
    }
    final result = engine.execute(
      AddAccount(
        name: _name.text,
        type: _type,
        // A card's balance is entered as the amount owed.
        startingBalance: _type == AccountType.creditCard ? -balance : balance,
        asOf: _asOf,
      ),
    );
    if (result is! Accepted) return;

    final navigator = Navigator.of(context);
    if (newBudgetName != null) {
      // The new budget gets its own store file and key now.
      _saving = true;
      final stored = await library.commit(engine);
      navigator.pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => BudgetScreen(engine: stored)),
        (_) => false,
      );
    } else {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormHeader(
              title: 'Add account',
              onClose: () => Navigator.of(context).pop(),
              onSave: _save,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                children: [
                  CardBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 10,
                      children: [
                        const FieldLabel('Type'),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final MapEntry(key: type, value: label)
                                in _typeLabels.entries)
                              SelectChip(
                                label: label,
                                selected: type == _type,
                                onTap: () => _selectType(type),
                              ),
                          ],
                        ),
                        const Hint(
                          'Budget account: money here can be assigned. '
                          'Tracking accounts (401k, mortgage) count toward '
                          'net worth only.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  CardBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 12,
                      children: [
                        LabeledField(
                          label: 'Name',
                          child: TextField(
                            key: const ValueKey('account-name'),
                            controller: _name,
                            onChanged: (_) => _nameEdited = true,
                            textCapitalization: TextCapitalization.words,
                            style: const TextStyle(fontSize: 15),
                            decoration: InputDecoration(errorText: _nameError),
                          ),
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 10,
                          children: [
                            Expanded(
                              child: LabeledField(
                                label: _type == AccountType.creditCard
                                    ? 'Amount owed'
                                    : 'Current balance',
                                child: TextField(
                                  key: const ValueKey('account-balance'),
                                  controller: _balance,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                        signed: true,
                                      ),
                                  style: amountStyle(),
                                  decoration: InputDecoration(
                                    hintText: '0.00',
                                    errorText: _balanceError,
                                    errorMaxLines: 2,
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: LabeledField(
                                label: 'As of',
                                child: DateField(
                                  value: _asOf,
                                  onChanged: (date) =>
                                      setState(() => _asOf = date),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_type.onBudget && _type != AccountType.creditCard)
                          const Hint(
                            'Recorded as a Starting Balance transaction that '
                            'goes to Ready to Assign.',
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    decoration: BoxDecoration(
                      color: Palette.summary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 12,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.credit_card,
                            size: 20,
                            color: Palette.inkSoft,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'A credit card gets its own Card Payment '
                            'Category. An existing card balance starts as '
                            'unfunded debt.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Palette.inkSoft,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
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
