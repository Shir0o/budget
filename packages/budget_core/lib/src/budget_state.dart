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

/// Whether a line is a personal or a business expense (ticket 09).
sealed class BusinessStatus {
  const BusinessStatus();

  /// Restores a status from a line's stored `business` and `businessTag`.
  static BusinessStatus? fromJson(Object? business, Object? tag) =>
      switch (business) {
        'personal' => const Personal(),
        'business' => Business(tag as String),
        _ => null,
      };

  /// The line's stored `business` and `businessTag`.
  Map<String, Object?> toJson();
}

final class Personal extends BusinessStatus {
  const Personal();

  @override
  Map<String, Object?> toJson() => {'business': 'personal'};

  @override
  bool operator ==(Object other) => other is Personal;

  @override
  int get hashCode => 0;
}

/// A reportable self-employment expense under a Business Tag.
final class Business extends BusinessStatus {
  const Business(this.tag);

  final String tag;

  @override
  Map<String, Object?> toJson() => {'business': 'business', 'businessTag': tag};

  @override
  bool operator ==(Object other) => other is Business && other.tag == tag;

  @override
  int get hashCode => tag.hashCode;
}

/// The preset Business Tags (ticket 04). Custom tags arrive with ticket 11.
const presetBusinessTags = [
  'Self-employment income',
  'Advertising',
  'Car & truck',
  'Contract labor',
  'Insurance',
  'Legal & professional',
  'Office expense',
  'Rent / lease',
  'Supplies',
  'Taxes & licenses',
  'Travel',
  'Meals',
  'Utilities',
  'Conferences & education',
  'Software & subscriptions',
  'Phone & internet',
  'Gifts',
  'Bank & payment fees',
  'Other business expense',
];

/// A transaction's cleared status (ticket 09).
enum ClearedStatus { uncleared, cleared, reconciled }

final class TransactionLine {
  const TransactionLine({
    required this.id,
    required this.amount,
    required this.category,
    this.business,
    this.memo = '',
    this.reviewed = false,
  });

  final String id;
  final Money amount;

  /// A Category id, [readyToAssignCategory] for income, or null while
  /// uncategorized.
  final String? category;

  /// Null until set.
  final BusinessStatus? business;
  final String memo;

  /// Only a person marks a line Reviewed (ADR 0003).
  final bool reviewed;
}

final class Transaction {
  const Transaction({
    required this.id,
    required this.accountId,
    required this.date,
    required this.payee,
    required this.amount,
    required this.lines,
    this.memo = '',
    this.cleared = ClearedStatus.uncleared,
  });

  final String id;
  final String accountId;
  final CivilDate date;
  final String payee;
  final String memo;
  final ClearedStatus cleared;

  /// Negative for an outflow. Always the sum of [lines].
  final Money amount;
  final List<TransactionLine> lines;

  /// Whether it has more than one line.
  bool get isSplit => lines.length > 1;

  Transaction _copyWith({
    CivilDate? date,
    String? payee,
    String? memo,
    ClearedStatus? cleared,
    Money? amount,
    List<TransactionLine>? lines,
  }) => Transaction(
    id: id,
    accountId: accountId,
    date: date ?? this.date,
    payee: payee ?? this.payee,
    memo: memo ?? this.memo,
    cleared: cleared ?? this.cleared,
    amount: amount ?? this.amount,
    lines: lines ?? this.lines,
  );
}

/// A budget as of some point in its Event log. Every query is a pure
/// function of the Events replayed into it.
final class BudgetState {
  /// Replays [events] in HLC order. Unknown event types are skipped, so an
  /// older app can still read a log written by a newer one.
  ///
  /// Replaying in order makes each transaction field, and each whole line
  /// set, last writer wins, and a delete beats any edit (ticket 06).
  factory BudgetState.replay(Iterable<Event> events) {
    final state = BudgetState._();
    final ordered = events.toList()..sort((a, b) => a.hlc.compareTo(b.hlc));
    for (final event in ordered) {
      state._apply(event);
    }
    for (final transaction in state._transactions.values) {
      for (final line in transaction.lines) {
        final category = line.category;
        if (category == null || category == readyToAssignCategory) continue;
        state._add(
          state._activity,
          category,
          CalendarMonth.of(transaction.date),
          line.amount,
        );
      }
    }
    return state;
  }

  BudgetState._();

  Budget? _budget;
  final _accounts = <String, Account>{};
  final _transactions = <String, Transaction>{};
  final _deleted = <String>{};
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

  /// Every transaction not deleted, in the order they were added.
  List<Transaction> get transactions => List.unmodifiable(_transactions.values);

  /// Null when it doesn't exist or was deleted.
  Transaction? transaction(String id) => _transactions[id];

  /// [accountId]'s transactions, newest date first. Same-day ones are
  /// newest added first.
  List<Transaction> register(String accountId) {
    final list = [
      for (final t in _transactions.values)
        if (t.accountId == accountId) t,
    ].reversed.toList();
    // List.sort isn't stable, so break ties on the position added.
    final position = {for (final (i, t) in list.indexed) t.id: i};
    return list..sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      return byDate != 0 ? byDate : position[a.id]! - position[b.id]!;
    });
  }

  /// The sum of [accountId]'s transactions.
  Money balance(String accountId) => _sum(accountId, (_) => true);

  /// The sum of [accountId]'s cleared and reconciled transactions.
  Money clearedBalance(String accountId) =>
      _sum(accountId, (t) => t.cleared != ClearedStatus.uncleared);

  Money _sum(String accountId, bool Function(Transaction) include) {
    var total = Money.zero;
    for (final t in _transactions.values) {
      if (t.accountId == accountId && include(t)) total += t.amount;
    }
    return total;
  }

  /// Active Categories most recently used on a transaction line, newest
  /// first, at most [limit].
  List<String> recentCategories({int limit = 3}) {
    final recent = <String>{};
    for (final t in _transactions.values.toList().reversed) {
      for (final line in t.lines) {
        final category = _categories[line.category];
        if (category != null && !category.archived) recent.add(category.id);
        if (recent.length == limit) return recent.toList();
      }
    }
    return recent.toList();
  }

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
  /// income lines in budget accounts, less uncategorized outflows
  /// (ticket 09), less every Assignment in any month (future ones too),
  /// less cash overspending from months before [month]. Negative means
  /// over-assigned.
  Money readyToAssign(CalendarMonth month) {
    var total = Money.zero;
    for (final transaction in _transactions.values) {
      for (final line in transaction.lines) {
        if (line.category == readyToAssignCategory ||
            (line.category == null && line.amount.isNegative)) {
          total += line.amount;
        }
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

  /// Every month any Category has an Assignment in, in order.
  List<CalendarMonth> get assignmentMonths =>
      {for (final byMonth in _assigned.values) ...byMonth.keys}.toList()
        ..sort();

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
        final id = p['transactionId'] as String;
        if (_deleted.contains(id)) return;
        _transactions[id] = Transaction(
          id: id,
          accountId: p['accountId'] as String,
          date: CivilDate.parse(p['date'] as String),
          payee: p['payee'] as String,
          memo: p['memo'] as String? ?? '',
          cleared: ClearedStatus.values.byName(
            p['cleared'] as String? ?? ClearedStatus.uncleared.name,
          ),
          amount: Money(p['amountCents'] as int),
          lines: _lines(p['lines'] as List),
        );
      case EventType.transactionFieldsSet:
        final id = p['transactionId'] as String;
        final transaction = _transactions[id];
        if (transaction == null) return;
        final fields = (p['fields'] as Map).cast<String, Object?>();
        final date = fields['date'] as String?;
        final cleared = fields['cleared'] as String?;
        _transactions[id] = transaction._copyWith(
          date: date == null ? null : CivilDate.parse(date),
          payee: fields['payee'] as String?,
          memo: fields['memo'] as String?,
          cleared: cleared == null
              ? null
              : ClearedStatus.values.byName(cleared),
        );
      case EventType.transactionSplitSet:
        final id = p['transactionId'] as String;
        final transaction = _transactions[id];
        if (transaction == null) return;
        _transactions[id] = transaction._copyWith(
          amount: Money(p['amountCents'] as int),
          lines: _lines(p['lines'] as List),
        );
      case EventType.transactionDeleted:
        final id = p['transactionId'] as String;
        _deleted.add(id);
        _transactions.remove(id);
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

  static List<TransactionLine> _lines(List<Object?> lines) => [
    for (final line in lines.cast<Map>())
      TransactionLine(
        id: line['lineId'] as String,
        amount: Money(line['amountCents'] as int),
        category: line['category'] as String?,
        business: BusinessStatus.fromJson(
          line['business'],
          line['businessTag'],
        ),
        memo: line['memo'] as String? ?? '',
        reviewed: line['reviewed'] as bool? ?? false,
      ),
  ];
}
