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

final class CategoryGroup {
  const CategoryGroup({required this.id, required this.name});

  final String id;
  final String name;
}

final class Category {
  const Category({
    required this.id,
    required this.groupId,
    required this.name,
    this.archived = false,
  });

  final String id;
  final String groupId;
  final String name;
  final bool archived;
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
  final _groups = <String, CategoryGroup>{};
  final _categories = <String, Category>{};

  /// Totals by Category id, then month.
  final _assigned = <String, Map<CalendarMonth, Money>>{};
  final _activity = <String, Map<CalendarMonth, Money>>{};

  /// Null until the budget is created.
  Budget? get budget => _budget;

  /// In the order they were added.
  List<Account> get accounts => List.unmodifiable(_accounts.values);

  Account? account(String id) => _accounts[id];

  List<Transaction> get transactions => List.unmodifiable(_transactions);

  /// In the order they were added.
  List<CategoryGroup> get categoryGroups => List.unmodifiable(_groups.values);

  CategoryGroup? categoryGroup(String id) => _groups[id];

  /// Every Category, archived ones included, in the order they were added.
  List<Category> get categories => List.unmodifiable(_categories.values);

  Category? category(String id) => _categories[id];

  /// The money assigned to [categoryId] for [month].
  Money assigned(String categoryId, CalendarMonth month) =>
      _assigned[categoryId]?[month] ?? Money.zero;

  /// The sum of [categoryId]'s transaction lines dated in [month]
  /// (ticket 07). Every account is a non-card budget account for now; card
  /// rules arrive with ticket 05.
  Money activity(String categoryId, CalendarMonth month) =>
      _activity[categoryId]?[month] ?? Money.zero;

  /// Last month's Available when it was 0 or more. A negative Available
  /// doesn't carry; it is overspending (ticket 07).
  Money carry(String categoryId, CalendarMonth month) {
    final previous = available(categoryId, month.previous);
    return previous.isNegative ? Money.zero : previous;
  }

  /// Carry + Assigned + Activity (ticket 07).
  Money available(String categoryId, CalendarMonth month) =>
      _availableByMonth(categoryId, month).lastOrNull?.$2 ?? Money.zero;

  /// The single, global pool as it stands during [month] (ticket 07):
  /// income lines in budget accounts, less every Assignment in any month
  /// (future ones too), less cash overspending from months before [month].
  /// Uncategorized outflows join this sum with ticket 09. Negative means
  /// over-assigned.
  Money readyToAssign(CalendarMonth month) {
    var total = Money.zero;
    for (final transaction in _transactions) {
      for (final line in transaction.lines) {
        if (line.category == readyToAssignCategory) total += line.amount;
      }
    }
    for (final byMonth in _assigned.values) {
      for (final amount in byMonth.values) {
        total -= amount;
      }
    }
    for (final categoryId in {..._assigned.keys, ..._activity.keys}) {
      for (final (_, balance) in _availableByMonth(
        categoryId,
        month.previous,
      )) {
        if (balance.isNegative) total += balance;
      }
    }
    return total;
  }

  /// The last month in which [categoryId] has an Assignment or Activity.
  CalendarMonth? lastActiveMonth(String categoryId) =>
      _activeMonths(categoryId).lastOrNull;

  /// The months with an Assignment or Activity for [categoryId], in order.
  List<CalendarMonth> _activeMonths(String categoryId) => {
    ...?_assigned[categoryId]?.keys,
    ...?_activity[categoryId]?.keys,
  }.toList()..sort();

  /// Available for each month from [categoryId]'s first Assignment or
  /// Activity through [last].
  Iterable<(CalendarMonth, Money)> _availableByMonth(
    String categoryId,
    CalendarMonth last,
  ) sync* {
    final first = _activeMonths(categoryId).firstOrNull;
    if (first == null) return;
    var balance = Money.zero;
    for (var month = first; month.compareTo(last) <= 0; month = month.next) {
      final carry = balance.isNegative ? Money.zero : balance;
      balance =
          carry + assigned(categoryId, month) + activity(categoryId, month);
      yield (month, balance);
    }
  }

  void _add(
    Map<String, Map<CalendarMonth, Money>> totals,
    String categoryId,
    CalendarMonth month,
    Money amount,
  ) {
    final byMonth = totals.putIfAbsent(categoryId, () => {});
    byMonth[month] = (byMonth[month] ?? Money.zero) + amount;
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
        final transaction = Transaction(
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
        );
        _transactions.add(transaction);
        for (final line in transaction.lines) {
          if (line.category == readyToAssignCategory) continue;
          _add(
            _activity,
            line.category,
            CalendarMonth.of(transaction.date),
            line.amount,
          );
        }
      case EventType.categoryGroupCreated:
        final id = p['categoryGroupId'] as String;
        _groups[id] = CategoryGroup(id: id, name: p['name'] as String);
      case EventType.categoryCreated:
        final id = p['categoryId'] as String;
        _categories[id] = Category(
          id: id,
          groupId: p['categoryGroupId'] as String,
          name: p['name'] as String,
        );
      case EventType.categoryArchived:
        final category = _categories[p['categoryId'] as String];
        if (category == null) return;
        _categories[category.id] = Category(
          id: category.id,
          groupId: category.groupId,
          name: category.name,
          archived: true,
        );
      case EventType.assignmentChanged:
        _add(
          _assigned,
          p['category'] as String,
          CalendarMonth.parse(p['month'] as String),
          Money(p['deltaCents'] as int),
        );
    }
  }
}
