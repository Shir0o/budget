import 'civil_date.dart';
import 'event.dart';
import 'money.dart';

/// The kinds of budget account this version supports. Credit cards and
/// tracking accounts arrive with ticket 05.
enum AccountType { checking, savings, cash }

final class Budget {
  const Budget({required this.id, required this.name});

  final String id;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is Budget && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

final class Account {
  const Account({required this.id, required this.name, required this.type});

  final String id;
  final String name;
  final AccountType type;

  @override
  bool operator ==(Object other) =>
      other is Account &&
      other.id == id &&
      other.name == name &&
      other.type == type;

  @override
  int get hashCode => Object.hash(id, name, type);
}

final class TransactionLine {
  const TransactionLine({
    required this.id,
    required this.amount,
    required this.category,
  });

  final String id;
  final Money amount;

  /// [readyToAssignCategory] for income.
  final String category;
}

final class Transaction {
  const Transaction({
    required this.id,
    required this.accountId,
    required this.date,
    required this.payee,
    required this.amount,
    required this.lines,
  });

  final String id;
  final String accountId;
  final CivilDate date;
  final String payee;
  final Money amount;
  final List<TransactionLine> lines;
}

/// A budget as of some point in its Event log. Every query is a pure
/// function of the Events replayed into it.
final class BudgetState {
  /// Replays [events] in HLC order. Unknown event types are skipped, so an
  /// older app can still read a log written by a newer one.
  factory BudgetState.replay(Iterable<Event> events) {
    final state = BudgetState._();
    final ordered = events.toList()..sort((a, b) => a.hlc.compareTo(b.hlc));
    for (final event in ordered) {
      state._apply(event);
    }
    return state;
  }

  BudgetState._();

  Budget? _budget;
  final _accounts = <String, Account>{};
  final _transactions = <Transaction>[];

  /// Null until the budget is created.
  Budget? get budget => _budget;

  /// In the order they were added.
  List<Account> get accounts => List.unmodifiable(_accounts.values);

  Account? account(String id) => _accounts[id];

  List<Transaction> get transactions => List.unmodifiable(_transactions);

  /// Income lines (lines categorized to Ready to Assign) in budget accounts
  /// (ticket 07). Assignments, overspending and uncategorized outflows join
  /// this sum in later tickets.
  Money get readyToAssign {
    var total = Money.zero;
    for (final transaction in _transactions) {
      for (final line in transaction.lines) {
        if (line.category == readyToAssignCategory) total += line.amount;
      }
    }
    return total;
  }

  void _apply(Event event) {
    final p = event.payload;
    switch (event.type) {
      case EventType.budgetCreated:
        _budget = Budget(id: event.budgetId, name: p['name'] as String);
      case EventType.accountCreated:
        final id = p['accountId'] as String;
        _accounts[id] = Account(
          id: id,
          name: p['name'] as String,
          type: AccountType.values.byName(p['accountType'] as String),
        );
      case EventType.transactionCreated:
        _transactions.add(
          Transaction(
            id: p['transactionId'] as String,
            accountId: p['accountId'] as String,
            date: CivilDate.parse(p['date'] as String),
            payee: p['payee'] as String,
            amount: Money(p['amountCents'] as int),
            lines: [
              for (final line in (p['lines'] as List).cast<Map>())
                TransactionLine(
                  id: line['lineId'] as String,
                  amount: Money(line['amountCents'] as int),
                  category: line['category'] as String,
                ),
            ],
          ),
        );
    }
  }
}
