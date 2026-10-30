import 'dart:typed_data';

import 'package:budget_core/budget_core.dart';

import 'actual_fixture.dart' show syntheticZip;

// A small, entirely synthetic YNAB export alongside the imported Actual
// history it is compared with. No real financial data (AGENTS.md).
//
// The history covers Jan to Apr 2024 for Everyday Checking, Rainy Day
// Savings and Travel Card. It has a starting balance, income, a card
// purchase, both sides of a transfer, a split, a transaction only YNAB has,
// one only the budget has, and a rent date that moved by two days.

const ynabRegisterCsv = '''Account,Flag,Date,Payee,Category Group/Category,Category Group,Category,Memo,Outflow,Inflow,Cleared
Everyday Checking,Green,01/02/2024,Starting Balance,Inflow: Ready to Assign,Inflow: Ready to Assign,Inflow: Ready to Assign,,,5000.00,Cleared
Everyday Checking,,01/05/2024,Landlord,Bills: Rent,Bills,Rent,Rent for January,1500.00,,Cleared
Everyday Checking,,01/06/2024,Corner Market,Bills: Groceries,Bills,Groceries,,120.40,,Cleared
Everyday Checking,,01/15/2024,Employer,Inflow: Ready to Assign,Inflow: Ready to Assign,Inflow: Ready to Assign,,,3200.00,Cleared
Travel Card,,01/20/2024,Corner Market,Bills: Groceries,Bills,Groceries,,60.00,,Uncleared
Everyday Checking,,02/02/2024,Landlord,Bills: Rent,Bills,Rent,,1500.00,,Cleared
Everyday Checking,,02/03/2024,Transfer : Rainy Day Savings,,,,,200.00,,Cleared
Rainy Day Savings,,02/03/2024,Transfer : Everyday Checking,,,,,,200.00,Cleared
Everyday Checking,,03/02/2024,Corner Market,Bills: Groceries,Bills,Groceries,,42.75,,Uncleared
Everyday Checking,,04/05/2024,Corner Market,Bills: Groceries,Bills,Groceries,Split (1/2) veg,30.00,,Cleared
Everyday Checking,,04/05/2024,Corner Market,Fun: Meals,Fun,Meals,Split (2/2) lunch,15.00,,Cleared
''';

const ynabPlanCsv = '''Month,Category Group/Category,Category Group,Category,Assigned,Activity,Available
Jan 2024,Inflow: Ready to Assign,Inflow: Ready to Assign,Inflow: Ready to Assign,,3200.00,3200.00
Jan 2024,Bills,Bills,,1650.00,-1680.40,-30.40
Jan 2024,Bills: Rent,Bills,Rent,"1,500.00",-1500.00,0.00
Jan 2024,Bills: Groceries,Bills,Groceries,150.00,-180.40,-30.40
Jan 2024,Fun: Meals,Fun,Meals,25.00,0.00,25.00
Jan 2024,Credit Card Payments: Travel Card,Credit Card Payments,Travel Card,0.00,60.00,60.00
Feb 2024,Bills: Rent,Bills,Rent,1500.00,-1500.00,0.00
Feb 2024,Bills: Groceries,Bills,Groceries,0.00,0.00,-30.40
Feb 2024,Credit Card Payments: Travel Card,Credit Card Payments,Travel Card,0.00,60.00,35.00
''';

/// The YNAB export as a zip, as YNAB writes it.
Uint8List syntheticYnabZip({
  String register = ynabRegisterCsv,
  String plan = ynabPlanCsv,
  String budget = 'Home',
}) => syntheticZip({
  '$budget as of Oct 30, 2026 - Register.csv': register,
  '$budget as of Oct 30, 2026 - Plan.csv': plan,
});

/// The imported Actual history [syntheticYnabZip] is compared with: the same
/// transactions, Card and Categories, with the March purchase missing (YNAB
/// only), a Coffee Shop purchase of its own (budget only) and the February
/// rent dated two days later.
ImportBatch actualHistory() {
  ImportLine line(
    int cents,
    String? category, {
    String memo = '',
    bool reviewed = true,
  }) => ImportLine(
    amount: Money(cents),
    category: category,
    memo: memo,
    reviewed: reviewed,
  );

  ImportTransaction transaction({
    required String id,
    required String accountId,
    required String date,
    required String payee,
    required List<ImportLine> lines,
    int? amountCents,
    String memo = '',
    ClearedStatus cleared = ClearedStatus.cleared,
    String? transferAccountId,
    String? transferTransactionId,
    bool startingBalance = false,
    String? importedCategory,
  }) => ImportTransaction(
    id: id,
    accountId: accountId,
    date: CivilDate.parse(date),
    payee: payee,
    memo: memo,
    cleared: cleared,
    amount: Money(
      amountCents ?? lines.fold(0, (total, line) => total + line.amount.cents),
    ),
    lines: lines,
    transferAccountId: transferAccountId,
    transferTransactionId: transferTransactionId,
    startingBalance: startingBalance,
    importedCategory: importedCategory,
  );

  return ImportBatch(
    accounts: const [
      ImportAccount(
        id: 'acct-checking',
        name: 'Everyday Checking',
        type: AccountType.checking,
      ),
      ImportAccount(
        id: 'acct-savings',
        name: 'Rainy Day Savings',
        type: AccountType.savings,
      ),
      ImportAccount(
        id: 'acct-card',
        name: 'Travel Card',
        type: AccountType.creditCard,
      ),
    ],
    categoryGroups: const [
      ImportCategoryGroup(id: 'grp-bills', name: 'Bills'),
      ImportCategoryGroup(id: 'grp-fun', name: 'Fun'),
      ImportCategoryGroup(id: 'grp-card', name: 'Credit Card Payments'),
    ],
    categories: const [
      ImportCategory(id: 'cat-rent', groupId: 'grp-bills', name: 'Rent'),
      ImportCategory(
        id: 'cat-groceries',
        groupId: 'grp-bills',
        name: 'Groceries',
      ),
      ImportCategory(id: 'cat-meals', groupId: 'grp-fun', name: 'Meals'),
      ImportCategory(
        id: 'cat-card',
        groupId: 'grp-card',
        name: 'Travel Card Payment',
        cardAccountId: 'acct-card',
      ),
    ],
    transactions: [
      transaction(
        id: 'tx-open',
        accountId: 'acct-checking',
        date: '2024-01-02',
        payee: 'Starting Balance',
        lines: [line(500000, readyToAssignCategory)],
        startingBalance: true,
      ),
      transaction(
        id: 'tx-rent-jan',
        accountId: 'acct-checking',
        date: '2024-01-05',
        payee: 'Landlord',
        memo: 'Rent for January',
        lines: [line(-150000, 'cat-rent')],
      ),
      transaction(
        id: 'tx-groceries-jan',
        accountId: 'acct-checking',
        date: '2024-01-06',
        payee: 'Corner Market',
        lines: [line(-12040, 'cat-groceries')],
      ),
      transaction(
        id: 'tx-income',
        accountId: 'acct-checking',
        date: '2024-01-15',
        payee: 'Employer',
        lines: [line(320000, readyToAssignCategory)],
        importedCategory: 'Paycheck',
      ),
      transaction(
        id: 'tx-card-jan',
        accountId: 'acct-card',
        date: '2024-01-20',
        payee: 'Corner Market',
        lines: [line(-6000, 'cat-groceries')],
        cleared: ClearedStatus.uncleared,
      ),
      transaction(
        id: 'tx-rent-feb',
        accountId: 'acct-checking',
        date: '2024-02-04',
        payee: 'Landlord',
        lines: [line(-150000, 'cat-rent')],
      ),
      transaction(
        id: 'tx-transfer-out',
        accountId: 'acct-checking',
        date: '2024-02-03',
        payee: 'Transfer : Rainy Day Savings',
        lines: [line(-20000, null)],
        transferAccountId: 'acct-savings',
        transferTransactionId: 'tx-transfer-in',
      ),
      transaction(
        id: 'tx-transfer-in',
        accountId: 'acct-savings',
        date: '2024-02-03',
        payee: 'Transfer : Everyday Checking',
        lines: [line(20000, null)],
        transferAccountId: 'acct-checking',
        transferTransactionId: 'tx-transfer-out',
      ),
      transaction(
        id: 'tx-coffee',
        accountId: 'acct-checking',
        date: '2024-02-20',
        payee: 'Coffee Shop',
        lines: [line(-425, 'cat-meals')],
      ),
      transaction(
        id: 'tx-split',
        accountId: 'acct-checking',
        date: '2024-04-05',
        payee: 'Corner Market',
        amountCents: -4500,
        lines: [
          line(-3000, 'cat-groceries', memo: 'veg'),
          line(-1500, 'cat-meals', memo: 'lunch'),
        ],
      ),
    ],
    assignments: [
      ImportAssignment(
        categoryId: 'cat-rent',
        month: CalendarMonth(2024, 1),
        amount: const Money(150000),
      ),
      ImportAssignment(
        categoryId: 'cat-groceries',
        month: CalendarMonth(2024, 1),
        amount: const Money(15000),
      ),
      ImportAssignment(
        categoryId: 'cat-rent',
        month: CalendarMonth(2024, 2),
        amount: const Money(150000),
      ),
    ],
    schedules: const [],
    targets: const [],
    expectedBalancesCents: const {
      'acct-checking': 483035,
      'acct-savings': 20000,
      'acct-card': -6000,
    },
  );
}
