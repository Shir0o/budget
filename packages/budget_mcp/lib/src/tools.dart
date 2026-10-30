import 'dart:convert';

import 'package:budget_core/budget_core.dart';

import 'budgets.dart';
import 'page.dart';

part 'tools_writes.dart';

/// One tool call: its name and arguments, as a client sent them.
final class ToolRequest {
  const ToolRequest(this.name, [this.arguments = const {}]);

  final String name;
  final Map<String, Object?> arguments;

  /// [key] as a non-empty string, or a refusal.
  String requireString(String key) {
    final value = arguments[key];
    if (value is String && value.isNotEmpty) return value;
    throw _Refusal('“$key” is required.');
  }

  String? string(String key) => switch (arguments[key]) {
    final String value when value.isNotEmpty => value,
    _ => null,
  };

  /// [key] as a string with empty allowed, or null when it isn't given.
  String? text(String key) => switch (arguments[key]) {
    final String value => value,
    _ => null,
  };

  int? integer(String key) => switch (arguments[key]) {
    final int value => value,
    final num value => value.toInt(),
    final String value => int.tryParse(value),
    _ => null,
  };

  bool? boolean(String key) => switch (arguments[key]) {
    final bool value => value,
    _ => null,
  };

  /// [key] inside [min]..[max], or [fallback] when it isn't given.
  int intIn(
    String key, {
    required int min,
    required int max,
    required int fallback,
  }) {
    final value = integer(key);
    if (value == null) return fallback;
    return value < min ? min : (value > max ? max : value);
  }

  /// A `YYYY-MM` argument, or [fallback].
  CalendarMonth month(String key, CalendarMonth fallback) {
    final value = string(key);
    if (value == null) return fallback;
    try {
      return CalendarMonth.parse(value);
    } on FormatException {
      throw _Refusal('“$key” must read YYYY-MM.');
    }
  }

  /// A `YYYY-MM-DD` argument, or null.
  CivilDate? date(String key) {
    final value = string(key);
    if (value == null) return null;
    try {
      return CivilDate.parse(value);
    } on FormatException {
      throw _Refusal('“$key” must read YYYY-MM-DD.');
    }
  }

  /// [key] as an int of cents, or a refusal.
  int requireInt(String key) {
    final value = integer(key);
    if (value == null) throw _Refusal('“$key” must be a whole number.');
    return value;
  }

  /// [key] as a required `YYYY-MM-DD`.
  CivilDate requireDate(String key) =>
      date(key) ?? (throw _Refusal('“$key” is required.'));

  /// One of [values] for [key], or a refusal.
  String requireOneOf(String key, Iterable<String> values) {
    final value = requireString(key);
    if (!values.contains(value)) {
      throw _Refusal('“$key” must be one of ${values.join(', ')}.');
    }
    return value;
  }
}

/// One tool's answer: the JSON object the client receives, with every string
/// redacted (ticket 13).
final class ToolResult {
  ToolResult(this.content, {this.isError = false});

  ToolResult.error(String message) : this({'error': message}, isError: true);

  final Map<String, Object?> content;
  final bool isError;

  String get text => jsonEncode(content);
}

/// One tool as the server lists it.
final class ToolSpec {
  const ToolSpec({
    required this.name,
    required this.description,
    this.arguments = const {},
    this.required = const [],
    this.writes = false,
  });

  final String name;
  final String description;

  /// The JSON Schema properties of its arguments.
  final Map<String, Object?> arguments;
  final List<String> required;

  /// Whether the call changes the budget. The server marks the rest
  /// read-only (ticket 13).
  final bool writes;

  Map<String, Object?> get inputSchema => {
    'type': 'object',
    'properties': arguments,
    if (required.isNotEmpty) 'required': required,
    'additionalProperties': false,
  };
}

/// The read tools ticket 13 lists, and the write tools Read-write mode adds.
/// Nothing here deletes anything or marks a line Reviewed.
final class BudgetTools {
  BudgetTools({
    required this.store,
    required this.events,
    required this.writes,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final McpStore store;
  final EventSource events;
  final BudgetWrites writes;
  final DateTime Function() _now;

  static const _budgetId = {
    'type': 'string',
    'description': 'The budget id from list_budgets.',
  };
  static const _page = {
    'type': 'integer',
    'minimum': 1,
    'description': 'Page number, from 1.',
  };
  static const _limit = {
    'type': 'integer',
    'minimum': 1,
    'maximum': maxPageSize,
    'description': 'Results per page, at most $maxPageSize.',
  };

  /// The read tools, in ticket 13's order.
  static const specs = <ToolSpec>[
    ToolSpec(
      name: 'list_budgets',
      description:
          'Every budget this app has, with its MCP mode. Budgets set to Off '
          'are left out.',
    ),
    ToolSpec(
      name: 'get_month',
      description:
          'One month: Ready to Assign, then each Category’s Assigned, '
          'Activity, Available and overspending, and what its Target needs.',
      arguments: {
        'budgetId': _budgetId,
        'month': {
          'type': 'string',
          'description': 'YYYY-MM. Defaults to this month.',
        },
      },
      required: ['budgetId'],
    ),
    ToolSpec(
      name: 'list_categories',
      description: 'Every Category group and Category, archived ones included.',
      arguments: {'budgetId': _budgetId},
      required: ['budgetId'],
    ),
    ToolSpec(
      name: 'list_accounts',
      description:
          'Every account with its balance and cleared balance, and net worth. '
          'Account names carry at most a last-4 suffix.',
      arguments: {'budgetId': _budgetId},
      required: ['budgetId'],
    ),
    ToolSpec(
      name: 'search_transactions',
      description:
          'Transactions newest first, filtered, at most $maxPageSize per page.',
      arguments: {
        'budgetId': _budgetId,
        'accountId': {'type': 'string'},
        'categoryId': {'type': 'string'},
        'from': {'type': 'string', 'description': 'YYYY-MM-DD, inclusive.'},
        'to': {'type': 'string', 'description': 'YYYY-MM-DD, inclusive.'},
        'payee': {
          'type': 'string',
          'description': 'Case-insensitive contains.',
        },
        'reviewed': {
          'type': 'boolean',
          'description':
              'true: every line Reviewed. false: any line still Unreviewed.',
        },
        'page': _page,
        'limit': _limit,
      },
      required: ['budgetId'],
    ),
    ToolSpec(
      name: 'get_transaction',
      description: 'One transaction, with its account and every line.',
      arguments: {
        'budgetId': _budgetId,
        'transactionId': {'type': 'string'},
      },
      required: ['budgetId', 'transactionId'],
    ),
    ToolSpec(
      name: 'list_unreviewed',
      description:
          'Unreviewed lines, newest first, and what each one still needs. '
          'Reading them never marks them Reviewed.',
      arguments: {'budgetId': _budgetId, 'page': _page, 'limit': _limit},
      required: ['budgetId'],
    ),
    ToolSpec(
      name: 'list_targets',
      description:
          'Each Category’s Target, Automation Mode and what it still needs '
          'this month.',
      arguments: {
        'budgetId': _budgetId,
        'month': {
          'type': 'string',
          'description': 'YYYY-MM. Defaults to this month.',
        },
      },
      required: ['budgetId'],
    ),
    ToolSpec(
      name: 'get_forecast',
      description:
          'Scheduled Transactions expanded over the next months (at most 12).',
      arguments: {
        'budgetId': _budgetId,
        'months': {'type': 'integer', 'minimum': 1, 'maximum': 12},
        'month': {'type': 'string', 'description': 'YYYY-MM to start at.'},
      },
      required: ['budgetId'],
    ),
    ToolSpec(
      name: 'get_business_report',
      description:
          'One tax year’s Business Tags, deductible totals and every tagged '
          'line, at most $maxPageSize lines per page. Records only.',
      arguments: {
        'budgetId': _budgetId,
        'year': {'type': 'integer'},
        'page': _page,
        'limit': _limit,
      },
      required: ['budgetId'],
    ),
    ToolSpec(
      name: 'get_change_history',
      description:
          'Change History, newest first: what changed, who or what changed '
          'it, and whether it was reverted.',
      arguments: {
        'budgetId': _budgetId,
        'actor': {
          'type': 'string',
          'enum': [
            'person',
            'bankSync',
            'automation',
            'import',
            'mcp',
            'revert',
          ],
        },
        'page': _page,
        'limit': _limit,
      },
      required: ['budgetId'],
    ),
  ];

  /// The write tools ticket 13 gives Read-write mode, as here they are.
  static final writeToolNames = {for (final tool in writeTools) tool.name};

  /// The write tools' specs, beside [specs] in the server's list.
  static final writeSpecs = [for (final tool in writeTools) tool.spec];

  /// Tools that never exist here (ticket 13): a line is Reviewed in the app,
  /// and nothing is deleted through MCP.
  static const neverToolNames = {
    'mark_reviewed',
    'set_reviewed',
    'review_transaction',
    'delete_transaction',
    'delete_account',
    'delete_budget',
    'delete_category',
  };

  /// Runs [request], [client] being the MCP client that sent it: its name
  /// becomes the Actor on every write, and the last-used line in Settings.
  Future<ToolResult> call(
    ToolRequest request, {
    McpClient client = McpClient.unknown,
  }) async {
    try {
      if (_spec(request.name) case final spec?) {
        return await _read(spec, request, client);
      }
      if (_writeTool(request.name) case final tool?) {
        return await _write(tool, request, client);
      }
      if (neverToolNames.contains(request.name)) {
        return ToolResult.error(
          'MCP can’t mark lines Reviewed or delete anything. Do it in the app.',
        );
      }
      return ToolResult.error('No tool named “${request.name}”.');
    } on _Refusal catch (refusal) {
      return ToolResult.error(refusal.message);
    } on StateError catch (error) {
      return ToolResult.error(error.message);
    }
  }

  Future<ToolResult> _read(
    ToolSpec spec,
    ToolRequest request,
    McpClient client,
  ) async {
    if (spec.name == 'list_budgets') {
      return ToolResult(
        _redact({
          'budgets': [
            for (final budget in await store.read())
              if (budget.book.mode.allowsRead)
                {
                  'id': budget.id,
                  'name': budget.name,
                  'mode': budget.book.mode.label,
                },
          ],
        }),
      );
    }
    final budget = await _open(request);
    final log = await events.events(budget);
    await store.recordUse(budget.id, client.name, _now());
    final state = BudgetState.replay(log);
    final content = switch (spec.name) {
      'get_month' => _month(state, budget, request),
      'list_categories' => _categories(state, budget),
      'list_accounts' => _accounts(state, budget),
      'search_transactions' => _search(state, budget, request),
      'get_transaction' => _transaction(
        state,
        budget,
        request.requireString('transactionId'),
      ),
      'list_unreviewed' => _unreviewed(state, budget, request),
      'list_targets' => _targets(state, budget, request),
      'get_forecast' => _forecast(state, budget, request),
      'get_business_report' => _business(state, budget, request),
      'get_change_history' => _history(log, budget, request),
      _ => throw _Refusal('No tool named “${spec.name}”.'),
    };
    return ToolResult(_redact(content));
  }

  ToolSpec? _spec(String name) {
    for (final spec in specs) {
      if (spec.name == name) return spec;
    }
    return null;
  }

  WriteTool? _writeTool(String name) {
    for (final tool in writeTools) {
      if (tool.name == name) return tool;
    }
    return null;
  }

  /// Runs one write tool: Read-write only, one Event group, actor
  /// `mcp:<client>` (ticket 13).
  Future<ToolResult> _write(
    WriteTool tool,
    ToolRequest request,
    McpClient client,
  ) async {
    final budget = await _open(request);
    if (!budget.book.mode.allowsWrite) {
      return ToolResult.error('MCP is read-only for this budget.');
    }
    // A card or account number is refused before it can be stored, rather
    // than redacted afterwards (ticket 13).
    _checkNumbers(request.arguments);
    final command = tool.build(request, _thisMonth());
    if (command is RevertGroup) {
      final entry = ChangeHistory.of(await events.events(budget))
          .entry(command.groupId);
      if (entry == null) throw const _Refusal('No change with that group id.');
      if (entry.actor.kind != ActorKind.mcp) {
        throw const _Refusal('MCP can only revert changes it made.');
      }
    }
    final result = await writes.write(budget, command, client.actor);
    await store.recordUse(budget.id, client.name, _now());
    switch (result) {
      case Rejected(:final reason):
        return ToolResult.error(_rejection(reason));
      case Accepted(events: final written) when written.isNotEmpty:
        final groupId = written.first.groupId;
        final group = ToolCallGroup(
          budgetId: budget.id,
          id: groupId,
          client: client,
          events: written,
          summary: ChangeHistory.of(await events.events(budget))
              .entry(groupId)
              ?.summary,
        );
        return ToolResult(_redact(group.toJson()));
      case Accepted():
        return ToolResult.error('That would change nothing.');
    }
  }

  /// Refuses [value]'s text if it looks like a card or account number
  /// (ticket 13). Ids are opaque values made here, so they are left out.
  void _checkNumbers(Object? value, {String? key}) {
    switch (value) {
      case final Map<Object?, Object?> map:
        for (final MapEntry(:key, :value) in map.entries) {
          _checkNumbers(value, key: key is String ? key : null);
        }
      case final List<Object?> list:
        for (final item in list) {
          _checkNumbers(item, key: key);
        }
      case final String text
          when (key == null || !_isId(key)) && containsSensitiveNumber(text):
        throw const _Refusal(_sensitiveNumber);
    }
  }

  /// The budget in [request], refusing one whose mode is Off.
  Future<McpBudget> _open(ToolRequest request) async {
    final id = request.requireString('budgetId');
    final budget = await store.budget(id);
    if (budget == null) throw const _Refusal('No budget with that id.');
    if (!budget.book.mode.allowsRead) {
      throw const _Refusal(
        'MCP is off for this budget. Turn it on in Settings → AI apps (MCP).',
      );
    }
    return budget;
  }

  Map<String, Object?> _month(
    BudgetState state,
    McpBudget budget,
    ToolRequest request,
  ) {
    final month = request.month('month', _thisMonth());
    return {
      'budgetId': budget.id,
      'month': month.toIso(),
      'readyToAssignCents': state.readyToAssign(month).cents,
      'categories': [
        for (final category in state.categories)
          {
            'id': category.id,
            'name': category.name,
            'group': state.categoryGroup(category.groupId)?.name ?? '',
            'archived': category.archived,
            'assignedCents': state.assigned(category.id, month).cents,
            'activityCents': state.activity(category.id, month).cents,
            'availableCents': state.available(category.id, month).cents,
            'cashOverspentCents': state
                .cashOverspending(category.id, month)
                .cents,
            'creditOverspentCents': state
                .creditOverspending(category.id, month)
                .cents,
            'targetNeededCents': state.needed(category.id, month).cents,
          },
      ],
    };
  }

  Map<String, Object?> _categories(BudgetState state, McpBudget budget) => {
    'budgetId': budget.id,
    'groups': [
      for (final group in state.categoryGroups)
        {'id': group.id, 'name': group.name},
    ],
    'categories': [
      for (final category in state.categories)
        {
          'id': category.id,
          'name': category.name,
          'groupId': category.groupId,
          'archived': category.archived,
          'cardAccountId': category.cardAccountId,
        },
    ],
  };

  Map<String, Object?> _accounts(BudgetState state, McpBudget budget) => {
    'budgetId': budget.id,
    'netWorthCents': state.netWorth.cents,
    'accounts': [
      for (final account in state.accounts)
        {
          'id': account.id,
          'name': redactAccountName(account.name),
          'type': account.type.name,
          'onBudget': account.type.onBudget,
          'balanceCents': state.balance(account.id).cents,
          'clearedBalanceCents': state.clearedBalance(account.id).cents,
        },
    ],
  };

  Map<String, Object?> _search(
    BudgetState state,
    McpBudget budget,
    ToolRequest request,
  ) {
    final accountId = request.string('accountId');
    final categoryId = request.string('categoryId');
    final from = request.date('from');
    final to = request.date('to');
    final payee = request.string('payee')?.toLowerCase();
    final reviewed = request.boolean('reviewed');
    final ordered = state.transactions.toList();
    final position = {for (final (i, t) in ordered.indexed) t.id: i};
    final matches =
        <Transaction>[
          for (final transaction in ordered)
            if (accountId == null || transaction.accountId == accountId)
              if (categoryId == null ||
                  transaction.lines.any((line) => line.category == categoryId))
                if (from == null || transaction.date.compareTo(from) >= 0)
                  if (to == null || transaction.date.compareTo(to) <= 0)
                    if (payee == null ||
                        transaction.payee.toLowerCase().contains(payee))
                      if (reviewed == null ||
                          reviewed ==
                              transaction.lines.every((line) => line.reviewed))
                        transaction,
        ]..sort((a, b) {
          final byDate = b.date.compareTo(a.date);
          return byDate != 0 ? byDate : position[b.id]! - position[a.id]!;
        });
    final page = paginate(
      matches,
      page: request.integer('page') ?? 1,
      limit: request.integer('limit') ?? defaultPageSize,
    );
    return {
      'budgetId': budget.id,
      ..._pageMeta(page),
      'transactions': [
        for (final transaction in page.items)
          _transactionJson(state, transaction),
      ],
    };
  }

  Map<String, Object?> _transaction(
    BudgetState state,
    McpBudget budget,
    String id,
  ) {
    final transaction = state.transaction(id);
    if (transaction == null) {
      throw const _Refusal('No transaction with that id.');
    }
    return {
      'budgetId': budget.id,
      'transaction': _transactionJson(state, transaction),
    };
  }

  Map<String, Object?> _transactionJson(
    BudgetState state,
    Transaction transaction,
  ) => {
    'id': transaction.id,
    'accountId': transaction.accountId,
    'account': _accountName(state, transaction.accountId),
    'date': transaction.date.toIso(),
    'payee': transaction.payee,
    'memo': transaction.memo,
    'amountCents': transaction.amount.cents,
    'cleared': transaction.cleared.name,
    'startingBalance': transaction.startingBalance,
    'transferAccountId': transaction.transferAccountId,
    'lines': [
      for (final line in transaction.lines)
        {
          'id': line.id,
          'amountCents': line.amount.cents,
          'categoryId': line.category,
          'category': _categoryName(state, line.category),
          'business': switch (line.business) {
            Personal() => 'personal',
            Business() => 'business',
            null => null,
          },
          'businessTag': switch (line.business) {
            Business(:final tag) => tag,
            _ => null,
          },
          'recipient': line.recipient,
          'memo': line.memo,
          'reviewed': line.reviewed,
        },
    ],
  };

  Map<String, Object?> _unreviewed(
    BudgetState state,
    McpBudget budget,
    ToolRequest request,
  ) {
    final queue = state.reviewQueue;
    final page = paginate(
      queue,
      page: request.integer('page') ?? 1,
      limit: request.integer('limit') ?? defaultPageSize,
    );
    return {
      'budgetId': budget.id,
      ..._pageMeta(page),
      'lines': [
        for (final item in page.items)
          {
            'transactionId': item.transaction.id,
            'lineId': item.line.id,
            'date': item.transaction.date.toIso(),
            'payee': item.transaction.payee,
            'account': _accountName(state, item.transaction.accountId),
            'amountCents': item.line.amount.cents,
            'needs': reviewNeed(
              category: item.line.category,
              business: item.line.business,
              recipient: item.line.recipient,
            )?.name,
          },
      ],
    };
  }

  Map<String, Object?> _targets(
    BudgetState state,
    McpBudget budget,
    ToolRequest request,
  ) {
    final month = request.month('month', _thisMonth());
    return {
      'budgetId': budget.id,
      'month': month.toIso(),
      'targets': [
        for (final category in state.categories)
          if (state.target(category.id) case final target?)
            {
              'categoryId': category.id,
              'category': category.name,
              'kind': switch (target) {
                RepeatingTarget() => 'repeating',
                ByDateTarget() => 'byDate',
                KeepAtLeastTarget() => 'keepAtLeast',
                DrivenByScheduleTarget() => 'schedule',
              },
              'amountCents': switch (target) {
                RepeatingTarget(:final amount) => amount.cents,
                ByDateTarget(:final amount) => amount.cents,
                KeepAtLeastTarget(:final amount) => amount.cents,
                DrivenByScheduleTarget() => null,
              },
              'automationMode': state.automationMode(category.id).name,
              'assignedCents': state.assigned(category.id, month).cents,
              'neededCents': state.needed(category.id, month).cents,
              'underfundedCents': state.underfunded(category.id, month).cents,
            },
      ],
    };
  }

  Map<String, Object?> _forecast(
    BudgetState state,
    McpBudget budget,
    ToolRequest request,
  ) {
    final months = request.intIn('months', min: 1, max: 12, fallback: 12);
    final start = request.month('month', _thisMonth());
    final forecast = Forecast.of(state, start: start, months: months);
    return {
      'budgetId': budget.id,
      'startMonth': start.toIso(),
      'startingBalanceCents': forecast.startingBalance.cents,
      'months': [
        for (final month in forecast.months)
          {
            'month': month.month.toIso(),
            'inflowCents': month.inflow.cents,
            'outflowCents': month.outflow.cents,
            'balanceCents': month.balance.cents,
            'underfunded': month.isUnderfunded,
          },
      ],
    };
  }

  Map<String, Object?> _business(
    BudgetState state,
    McpBudget budget,
    ToolRequest request,
  ) {
    final year = request.integer('year') ?? _now().year;
    final report = state.businessReport(year);
    final page = paginate(
      report.lines,
      page: request.integer('page') ?? 1,
      limit: request.integer('limit') ?? defaultPageSize,
    );
    return {
      'budgetId': budget.id,
      'year': year,
      'incomeCents': report.income.cents,
      'deductibleExpensesCents': report.deductibleExpenses.cents,
      'netCents': report.net.cents,
      'rows': [
        for (final row in report.rows)
          {
            'tag': row.tag.name,
            'line': row.tag.line,
            'rule': row.tag.rule.label,
            'grossCents': row.gross.cents,
            'deductibleCents': row.deductible.cents,
          },
      ],
      ..._pageMeta(page),
      'lines': [
        for (final line in page.items)
          {
            'date': line.transaction.date.toIso(),
            'payee': line.transaction.payee,
            'account': redactAccountName(line.account),
            'amountCents': line.line.amount.cents,
            'grossCents': line.gross.cents,
            'deductibleCents': line.deductible.cents,
            'tag': line.tag.name,
            'recipient': line.line.recipient,
            'reviewed': line.line.reviewed,
          },
      ],
      'warnings': [
        for (final warning in report.warnings) _warning(warning, year),
      ],
      'footer': businessReportFooter,
    };
  }

  String _warning(BusinessWarning warning, int year) => switch (warning) {
    UnreviewedLines(:final count) =>
      '$count ${count == 1 ? 'line is' : 'lines are'} still Unreviewed in $year.',
    MissingBusinessUse(:final tag) =>
      'Business use % is not set for ${tag.name} in $year.',
    GiftWithoutRecipient(:final line) =>
      'A ${line.tag.name} line on ${line.transaction.date.toIso()} '
          'has no recipient.',
  };

  Map<String, Object?> _history(
    List<Event> events,
    McpBudget budget,
    ToolRequest request,
  ) {
    final actor = request.string('actor');
    final kind = switch (actor) {
      null => null,
      _ => ActorKind.values.asNameMap()[actor],
    };
    if (actor != null && kind == null) {
      throw const _Refusal('“actor” must name a kind of Actor.');
    }
    final history = ChangeHistory.of(events);
    final entries = history.entries(
      filter: HistoryFilter(actors: kind == null ? null : {kind}),
    );
    final page = paginate(
      entries,
      page: request.integer('page') ?? 1,
      limit: request.integer('limit') ?? defaultPageSize,
    );
    return {
      'budgetId': budget.id,
      ..._pageMeta(page),
      'entries': [
        for (final entry in page.items)
          {
            'groupId': entry.groupId,
            'time': entry.time.toIso8601String(),
            'actor': entry.actor.value,
            'by': entry.by?.value,
            'summary': entry.summary,
            'revertedBy': entry.revertedBy,
            'changes': [
              for (final change in entry.changes)
                {
                  'label': change.label,
                  'before': change.before,
                  'after': change.after,
                  'note': change.note,
                },
            ],
          },
      ],
    };
  }

  Map<String, Object?> _pageMeta(Page<Object?> page) => {
    'page': page.page,
    'pageSize': page.pageSize,
    'total': page.total,
    'hasMore': page.hasMore,
  };

  String _accountName(BudgetState state, String id) =>
      redactAccountName(state.account(id)?.name ?? 'Unknown account');

  String _categoryName(BudgetState state, String? id) => switch (id) {
    null => 'Uncategorized',
    readyToAssignCategory => 'Ready to Assign',
    final id => state.category(id)?.name ?? 'Unknown Category',
  };

  CalendarMonth _thisMonth() =>
      CalendarMonth.of(CivilDate.fromDateTime(_now()));

  /// [content] with every string redacted (ticket 13).
  /// [content] with every user string redacted (ticket 13). Ids are opaque
  /// values made here, never a card or account number, and a client must get
  /// them back unchanged to call the next tool.
  Map<String, Object?> _redact(Map<String, Object?> content) =>
      redactJson(content, skipKey: _isId)! as Map<String, Object?>;

  static bool _isId(String key) =>
      key == 'id' || key == 'groupId' || key.endsWith('Id');
}

/// A refusal with a message the client sees: a bad argument, an unknown
/// budget, or a mode that doesn't allow the call.
final class _Refusal implements Exception {
  const _Refusal(this.message);

  final String message;
}
