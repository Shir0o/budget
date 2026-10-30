import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';

/// A minimal form for income to Ready to Assign. Ticket 03 replaces it with
/// the full New transaction screen.
class RecordIncomeScreen extends StatefulWidget {
  const RecordIncomeScreen({super.key, required this.engine});

  final BudgetEngine engine;

  @override
  State<RecordIncomeScreen> createState() => _RecordIncomeScreenState();
}

class _RecordIncomeScreenState extends State<RecordIncomeScreen> {
  final _amount = TextEditingController();
  final _payee = TextEditingController();
  late String? _accountId = widget.engine.state.accounts.firstOrNull?.id;
  var _date = today();
  String? _amountError;

  @override
  void dispose() {
    _amount.dispose();
    _payee.dispose();
    super.dispose();
  }

  void _save() {
    final amount = Money.tryParse(_amount.text);
    final accountId = _accountId;
    if (amount == null || !amount.isPositive) {
      setState(() => _amountError = 'Enter an amount above 0.00');
      return;
    }
    if (accountId == null) return;
    final result = widget.engine.execute(
      RecordIncome(
        accountId: accountId,
        amount: amount,
        date: _date,
        payee: _payee.text,
      ),
    );
    if (result is Accepted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = widget.engine.state.accounts;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormHeader(
              title: 'Record income',
              onClose: () => Navigator.of(context).pop(),
              onSave: _save,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                children: [
                  CardBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 12,
                      children: [
                        LabeledField(
                          label: 'Amount',
                          child: TextField(
                            key: const ValueKey('income-amount'),
                            controller: _amount,
                            autofocus: true,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            style: amountStyle(),
                            decoration: InputDecoration(
                              hintText: '0.00',
                              errorText: _amountError,
                            ),
                          ),
                        ),
                        LabeledField(
                          label: 'Payee',
                          child: TextField(
                            key: const ValueKey('income-payee'),
                            controller: _payee,
                            textCapitalization: TextCapitalization.words,
                            style: const TextStyle(fontSize: 15),
                          ),
                        ),
                        LabeledField(
                          label: 'Date',
                          child: DateField(
                            value: _date,
                            onChanged: (date) => setState(() => _date = date),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  CardBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 10,
                      children: [
                        const FieldLabel('Account'),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final account in accounts)
                              SelectChip(
                                label: account.name,
                                selected: account.id == _accountId,
                                onTap: () =>
                                    setState(() => _accountId = account.id),
                              ),
                          ],
                        ),
                        const Hint('Income goes to Ready to Assign.'),
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
