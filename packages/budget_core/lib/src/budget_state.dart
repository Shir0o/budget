import 'civil_date.dart';
import 'event.dart';
import 'money.dart';
import 'review.dart';
import 'target.dart';

part 'automation.dart';
part 'budget_math.dart';
part 'business.dart';
part 'forecast.dart';
part 'schedules.dart';

/// The kinds of account (ticket 07). All but [tracking] are budget
/// accounts.
enum AccountType {
  checking,
  savings,
  cash,
  creditCard,

  /// Counts toward net worth only, such as a 401k or a mortgage.
  tracking;

  /// Whether money in it affects the budget.
  bool get onBudget => this != tracking;
}

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
    this.cardAccountId,
  });

  final String id;
  final String groupId;
  final String name;
  final bool archived;

  /// The credit card account whose Card Payment Category this is, or null
  /// for an ordinary Category.
  final String? cardAccountId;
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

/// A transaction's cleared status (ticket 09).
enum ClearedStatus { uncleared, cleared, reconciled }

/// A bank charge that looks like a line entered by hand or from a schedule
/// (ticket 10, step 4). It waits on the transaction it might be, in
/// [Transaction.pendingMatch], and changes nothing until a person confirms
/// it: neither the amount nor the balance moves.
final class ProposedMatch {
  const ProposedMatch({
    required this.bankId,
    required this.date,
    required this.amount,
    required this.description,
    this.memo = '',
    this.pending = false,
  });

  factory ProposedMatch.fromJson(Map<String, Object?> json) => ProposedMatch(
    bankId: json['bankId'] as String,
    date: CivilDate.parse(json['date'] as String),
    amount: Money(json['amountCents'] as int),
    description: json['description'] as String? ?? '',
    memo: json['memo'] as String? ?? '',
    pending: json['pending'] as bool? ?? false,
  );

  /// The bank's id for the charge, which a confirmed match links.
  final String bankId;

  final CivilDate date;

  /// Negative for an outflow. The line's amount is exactly this, which is
  /// what makes it look like the same charge.
  final Money amount;

  /// What the bank calls the payee.
  final String description;
  final String memo;
  final bool pending;

  Map<String, Object?> toJson() => {
    'bankId': bankId,
    'date': date.toIso(),
    'amountCents': amount.cents,
    'description': description,
    'memo': memo,
    'pending': pending,
  };
}

final class TransactionLine {
  const TransactionLine({
    required this.id,
    required this.amount,
    required this.category,
    this.business,
    this.memo = '',
    this.recipient,
    this.note,
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

  /// Who received a gift line (Business Tag [giftsTag]). Null when unset.
  final String? recipient;

  /// Why a bank fetch put the line back in Review, such as
  /// `changed by bank: −$48.20 → −$15.00` (ticket 10). Null otherwise, and
  /// cleared once a person reviews the line again.
  final String? note;

  /// Only a person marks a line Reviewed (ADR 0003).
  /// See [reviewNeed] for what it takes.
  final bool reviewed;
}

/// Marks a [_copyWith] argument that isn't given, so a null can clear a
/// field that is otherwise left alone.
const _unchanged = Object();

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
    this.transferAccountId,
    this.transferTransactionId,
    this.startingBalance = false,
    this.bankId,
    this.importedCategory,
    this.pendingMatch,
  });

  final String id;
  final String accountId;
  final CivilDate date;
  final String payee;
  final String memo;
  final ClearedStatus cleared;

  /// For one side of a transfer, the other side's account and transaction.
  final String? transferAccountId;
  final String? transferTransactionId;

  /// A card or tracking account's opening balance. Its line has no
  /// Category and doesn't touch the budget (ticket 07 example 6).
  final bool startingBalance;

  /// The SimpleFIN id a bank fetch imported this under, so a later fetch
  /// updates it in place (ticket 10). Null for a transaction someone
  /// entered by hand.
  final String? bankId;

  /// The Actual income category this transaction's income lost when it went
  /// to Ready to Assign (ticket 14). Read-only metadata; null otherwise.
  final String? importedCategory;

  /// A bank charge that looks like this line, waiting on a person to
  /// confirm or reject it (ticket 10, step 4). Nothing merges until they
  /// do, and it changes no amount.
  final ProposedMatch? pendingMatch;

  bool get isTransfer => transferTransactionId != null;

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
    Object? bankId = _unchanged,
    Object? pendingMatch = _unchanged,
  }) => Transaction(
    id: id,
    accountId: accountId,
    date: date ?? this.date,
    payee: payee ?? this.payee,
    memo: memo ?? this.memo,
    cleared: cleared ?? this.cleared,
    amount: amount ?? this.amount,
    lines: lines ?? this.lines,
    transferAccountId: transferAccountId,
    transferTransactionId: transferTransactionId,
    startingBalance: startingBalance,
    bankId: identical(bankId, _unchanged) ? this.bankId : bankId as String?,
    importedCategory: importedCategory,
    pendingMatch: identical(pendingMatch, _unchanged)
        ? this.pendingMatch
        : pendingMatch as ProposedMatch?,
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
    state._ledger = _Ledger(state);
    return state;
  }

  BudgetState._();

  Budget? _budget;
  final _accounts = <String, Account>{};
  final _transactions = <String, Transaction>{};
  final _deleted = <String>{};
  final _groups = <String, CategoryGroup>{};
  final _categories = <String, Category>{};

  /// Deleted entities, kept so a revert can restore them (ticket 11).
  final _removedTransactions = <String, Transaction>{};
  final _removedAccounts = <String, Account>{};
  final _removedGroups = <String, CategoryGroup>{};
  final _removedCategories = <String, Category>{};

  /// Totals by Category id, then month.
  final _assigned = <String, Map<CalendarMonth, Money>>{};

  /// Card Payment Category ids by card account id.
  final _cardPayment = <String, String>{};

  /// Targets, Automation Modes and the priority order (ticket 08).
  final _targets = <String, Target>{};
  final _modes = <String, AutomationMode>{};
  var _priority = <String>[];

  /// Scheduled Transactions (ticket 10).
  final _schedules = <String, Schedule>{};

  /// Deleted ones, kept so a revert can restore them (ticket 11).
  final _removedSchedules = <String, Schedule>{};

  /// Custom Business Tags by name, and business-use % by tag, then tax year
  /// (ticket 11).
  final _customBusinessTags = <String, BusinessTag>{};
  final _businessUse = <String, Map<int, int>>{};

  late final _Ledger _ledger;

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

  /// The sum of [categoryId]'s transaction lines in budget accounts dated
  /// in [month] (ticket 07). For a Card Payment Category it is the card
  /// spending moved in, less refunds and payments.
  Money activity(String categoryId, CalendarMonth month) =>
      _ledger.at(categoryId, month)?.activity ?? Money.zero;

  /// Last month's Available when it was 0 or more. A negative Available
  /// doesn't carry; it is overspending (ticket 07).
  Money carry(String categoryId, CalendarMonth month) {
    final previous = available(categoryId, month.previous);
    return previous.isNegative ? Money.zero : previous;
  }

  /// Carry + Assigned + Activity (ticket 07).
  Money available(String categoryId, CalendarMonth month) =>
      _ledger.at(categoryId, month)?.available ?? Money.zero;

  /// The part of a negative Available caused by spending from cash
  /// accounts. It comes out of next month's Ready to Assign.
  Money cashOverspending(String categoryId, CalendarMonth month) =>
      _ledger.at(categoryId, month)?.cashOverspent ?? Money.zero;

  /// The part of a negative Available caused by card spending that wasn't
  /// funded. It stays as unfunded card debt instead.
  Money creditOverspending(String categoryId, CalendarMonth month) =>
      _ledger.at(categoryId, month)?.creditOverspent ?? Money.zero;

  /// The single, global pool as it stands during [month] (ticket 07):
  /// income lines in budget accounts, less uncategorized outflows
  /// (ticket 09), less every Assignment in any month (future ones too),
  /// less cash overspending from months before [month]. Negative means
  /// over-assigned.
  Money readyToAssign(CalendarMonth month) {
    var total = Money.zero;
    for (final transaction in _transactions.values) {
      if (_accounts[transaction.accountId]?.type.onBudget == false) continue;
      final counts = !transaction.isTransfer && !transaction.startingBalance;
      for (final line in transaction.lines) {
        if (line.category == readyToAssignCategory ||
            (counts && line.category == null && line.amount.isNegative)) {
          total += line.amount;
        }
      }
    }
    for (final byMonth in _assigned.values) {
      for (final amount in byMonth.values) {
        total -= amount;
      }
    }
    return total - _ledger.cashOverspentBefore(month);
  }

  /// Every month any Category has an Assignment in, in order.
  List<CalendarMonth> get assignmentMonths =>
      {for (final byMonth in _assigned.values) ...byMonth.keys}.toList()
        ..sort();

  /// The last month in which [categoryId] has an Assignment or Activity.
  CalendarMonth? lastActiveMonth(String categoryId) {
    final assigned = _assigned[categoryId]?.keys.toList() ?? const [];
    return [?_ledger.lastActive[categoryId], ...assigned].fold<CalendarMonth?>(
      null,
      (last, month) => last == null || month.compareTo(last) > 0 ? month : last,
    );
  }

  /// [accountId]'s Card Payment Category, or null when it isn't a card.
  Category? cardPaymentCategory(String accountId) =>
      _categories[_cardPayment[accountId]];

  /// How much of a card's debt at the end of [month] its Card Payment
  /// Category doesn't cover (ticket 07 examples 4 and 6). Zero for any
  /// other account.
  Money unfundedDebt(String accountId, CalendarMonth month) {
    final payment = _cardPayment[accountId];
    if (payment == null) return Money.zero;
    final debt = -_sum(
      accountId,
      (t) => CalendarMonth.of(t.date).compareTo(month) <= 0,
    );
    final unfunded = debt - available(payment, month);
    return unfunded.isPositive ? unfunded : Money.zero;
  }

  /// The sum of every account's balance, tracking accounts included.
  Money get netWorth => _accounts.keys.fold(
    Money.zero,
    (total, accountId) => total + balance(accountId),
  );

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
          transferAccountId: p['transferAccountId'] as String?,
          transferTransactionId: p['transferTransactionId'] as String?,
          startingBalance: p['startingBalance'] as bool? ?? false,
          bankId: p['bankId'] as String?,
          importedCategory: p['importedCategory'] as String?,
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
          bankId: fields.containsKey('bankId') ? fields['bankId'] : _unchanged,
          pendingMatch: switch (fields['pendingMatch']) {
            final Map match => ProposedMatch.fromJson(
              match.cast<String, Object?>(),
            ),
            _ when fields.containsKey('pendingMatch') => null,
            _ => _unchanged,
          },
        );
      case EventType.transactionSplitSet:
        final id = p['transactionId'] as String;
        final transaction = _transactions[id];
        if (transaction == null) return;
        _transactions[id] = transaction._copyWith(
          amount: Money(p['amountCents'] as int),
          lines: _lines(p['lines'] as List),
        );
      case EventType.reviewSet:
        _applyReviewSet(event);
      case EventType.transactionDeleted:
        final id = p['transactionId'] as String;
        _deleted.add(id);
        _move(_transactions, _removedTransactions, id);
      case EventType.transactionRestored:
        final id = p['transactionId'] as String;
        if (!_removedTransactions.containsKey(id)) return;
        _deleted.remove(id);
        _move(_removedTransactions, _transactions, id);
      case EventType.accountDeleted:
        _move(_accounts, _removedAccounts, p['accountId'] as String);
      case EventType.accountRestored:
        _move(_removedAccounts, _accounts, p['accountId'] as String);
      case EventType.categoryGroupDeleted:
        _move(_groups, _removedGroups, p['categoryGroupId'] as String);
      case EventType.categoryGroupRestored:
        _move(_removedGroups, _groups, p['categoryGroupId'] as String);
      case EventType.categoryDeleted:
        _move(_categories, _removedCategories, p['categoryId'] as String);
      case EventType.categoryRestored:
        _move(_removedCategories, _categories, p['categoryId'] as String);
      case EventType.reconciled:
        final accountId = p['accountId'] as String;
        for (final t in _transactions.values.toList()) {
          if (t.accountId == accountId && t.cleared == ClearedStatus.cleared) {
            _transactions[t.id] = t._copyWith(
              cleared: ClearedStatus.reconciled,
            );
          }
        }
      case EventType.categoryGroupCreated:
        final id = p['categoryGroupId'] as String;
        _groups[id] = CategoryGroup(id: id, name: p['name'] as String);
      case EventType.categoryCreated:
        final id = p['categoryId'] as String;
        final card = p['cardAccountId'] as String?;
        _categories[id] = Category(
          id: id,
          groupId: p['categoryGroupId'] as String,
          name: p['name'] as String,
          cardAccountId: card,
        );
        if (card != null) _cardPayment[card] = id;
      case EventType.categoryRenamed:
        final category = _categories[p['categoryId'] as String];
        if (category == null) return;
        _categories[category.id] = Category(
          id: category.id,
          groupId: category.groupId,
          name: p['name'] as String,
          archived: category.archived,
          cardAccountId: category.cardAccountId,
        );
      case EventType.categoryArchived || EventType.categoryUnarchived:
        final category = _categories[p['categoryId'] as String];
        if (category == null) return;
        _categories[category.id] = Category(
          id: category.id,
          groupId: category.groupId,
          name: category.name,
          archived: event.type == EventType.categoryArchived,
          cardAccountId: category.cardAccountId,
        );
      case EventType.assignmentChanged:
        _add(
          _assigned,
          p['category'] as String,
          CalendarMonth.parse(p['month'] as String),
          Money(p['deltaCents'] as int),
        );
      case EventType.targetSet:
        _targets[p['categoryId'] as String] = Target.fromJson(
          (p['target'] as Map).cast<String, Object?>(),
        );
      case EventType.targetCleared:
        _targets.remove(p['categoryId'] as String);
      case EventType.automationModeSet:
        // A null mode, as a revert writes, goes back to the default.
        final id = p['categoryId'] as String;
        final mode = p['mode'] as String?;
        mode == null
            ? _modes.remove(id)
            : _modes[id] = AutomationMode.values.byName(mode);
      case EventType.prioritySet:
        _priority = (p['categoryIds'] as List).cast<String>();
      case EventType.scheduleCreated:
        final id = p['scheduleId'] as String;
        if (_removedSchedules.containsKey(id)) return;
        _schedules[id] = Schedule.fromJson(id, p);
      case EventType.scheduleFieldsSet:
        final id = p['scheduleId'] as String;
        final schedule = _schedules[id];
        if (schedule == null) return;
        final fields = (p['fields'] as Map).cast<String, Object?>();
        _schedules[id] = schedule._copyWith(
          accountId: fields['accountId'] as String?,
          payee: fields['payee'] as String?,
          memo: fields['memo'] as String?,
          amount: switch (fields['amountCents']) {
            final int cents => Money(cents),
            _ => null,
          },
          category: fields['category'] as String?,
          every: fields['every'] as int?,
          interval: switch (fields['interval']) {
            final String name => TargetInterval.values.byName(name),
            _ => null,
          },
          nextDue: switch (fields['nextDue']) {
            final String iso => CivilDate.parse(iso),
            _ => null,
          },
        );
      case EventType.scheduleDeleted:
        _move(_schedules, _removedSchedules, p['scheduleId'] as String);
      case EventType.scheduleRestored:
        _move(_removedSchedules, _schedules, p['scheduleId'] as String);
      case EventType.businessTagCreated:
        final tag = BusinessTag.fromJson(p);
        _customBusinessTags[tag.name] = tag;
      case EventType.businessUseSet:
        final year = p['year'] as int;
        final byYear = _businessUse.putIfAbsent(p['tag'] as String, () => {});
        switch (p['percent']) {
          case final int percent:
            byYear[year] = percent;
          case null:
            // A revert writes null to unset a percentage it added.
            byYear.remove(year);
        }
    }
  }

  static void _move<T>(Map<String, T> from, Map<String, T> to, String id) {
    final value = from.remove(id);
    if (value != null) to[id] = value;
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
        recipient: line['recipient'] as String?,
        note: line['note'] as String?,
        reviewed: line['reviewed'] as bool? ?? false,
      ),
  ];

  /// Marks one line Reviewed with a person's values. A ReviewSet from any
  /// other actor is ignored, so a merged log can't bypass ADR 0003.
  void _applyReviewSet(Event event) {
    if (!event.actor.isPerson) return;
    final p = event.payload;
    final transaction = _transactions[p['transactionId'] as String];
    if (transaction == null) return;
    final lineId = p['lineId'] as String;
    _transactions[transaction.id] = transaction._copyWith(
      lines: [
        for (final line in transaction.lines)
          line.id != lineId
              ? line
              : TransactionLine(
                  id: line.id,
                  amount: line.amount,
                  category: p['category'] as String?,
                  business: BusinessStatus.fromJson(
                    p['business'],
                    p['businessTag'],
                  ),
                  memo: line.memo,
                  recipient: p['recipient'] as String?,
                  reviewed: true,
                ),
      ],
    );
  }
}
