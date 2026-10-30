part of 'tools.dart';

// Ticket 13's write tools, and the shapes one call works in: the client that
// sent it, the tool, and the one Event group it appends.

/// The MCP client that sent a call. Its announced name becomes the Actor
/// `mcp:<name>` on every Event it writes (ticket 13), so Change History shows
/// which AI app made a change.
final class McpClient {
  McpClient(String name) : name = _clientName(name);

  const McpClient._(this.name);

  /// The client whose name the server never learned.
  static const unknown = McpClient._('unknown');

  /// Trimmed, with runs of whitespace collapsed, at most 64 characters.
  final String name;

  /// `mcp:<name>`, the Actor on this client's groups.
  Actor get actor => Actor.fromValue('mcp:$name');

  static String _clientName(String name) {
    final cleaned = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    // A name that already reads `mcp:` isn't doubled.
    final withoutPrefix = cleaned.startsWith('mcp:')
        ? cleaned.substring('mcp:'.length)
        : cleaned;
    if (withoutPrefix.isEmpty) return unknown.name;
    return withoutPrefix.length > 64
        ? withoutPrefix.substring(0, 64)
        : withoutPrefix;
  }
}

/// One write tool: what the server lists a client, and the one Command a call
/// runs. One Command is one Event group, so a call is one revertable change.
final class WriteTool {
  const WriteTool({
    required this.name,
    required this.description,
    this.arguments = const {},
    this.required = const [],
    required this.build,
  });

  final String name;
  final String description;
  final Map<String, Object?> arguments;
  final List<String> required;

  /// The Command one call runs, or a refusal for its arguments.
  final Command Function(ToolRequest request, CalendarMonth thisMonth) build;

  ToolSpec get spec => ToolSpec(
    name: name,
    description: description,
    arguments: arguments,
    required: required,
    writes: true,
  );
}

/// One write tool call's answer: the single Event group it appended (ticket
/// 13). [id] is what `revert_change` takes, and Change History lists the same
/// group as one revertable entry.
final class ToolCallGroup {
  const ToolCallGroup({
    required this.budgetId,
    required this.id,
    required this.client,
    required this.events,
    this.summary,
  });

  final String budgetId;
  final String id;
  final McpClient client;
  final List<Event> events;

  /// How Change History reads the group, or null if it can't.
  final String? summary;

  Map<String, Object?> toJson() => {
    'budgetId': budgetId,
    'groupId': id,
    'actor': client.actor.value,
    'changes': events.length,
    'summary': ?summary,
  };
}

const _accountId = {'type': 'string', 'description': 'An account id.'};
const _categoryId = {
  'type': 'string',
  'description': 'A Category id, or readyToAssign for income.',
};
const _monthArgument = {
  'type': 'string',
  'description': 'YYYY-MM. Defaults to this month.',
};
const _amount = {
  'type': 'integer',
  'description': 'Whole cents. Negative for an outflow.',
};
const _interval = {
  'type': 'string',
  'enum': ['days', 'weeks', 'months', 'years'],
};

const _line = {
  'type': 'object',
  'properties': {
    'amountCents': _amount,
    'categoryId': _categoryId,
    'business': {
      'type': 'string',
      'enum': ['personal', 'business'],
    },
    'businessTag': {'type': 'string'},
    'memo': {'type': 'string'},
    'recipient': {'type': 'string', 'description': 'For a gift line.'},
  },
  'required': ['amountCents'],
  'additionalProperties': false,
};

/// Ticket 13's write tools, in its order. `revert_change` undoes one group
/// MCP itself wrote; there is no tool that deletes anything or marks a line
/// Reviewed.
final writeTools = <WriteTool>[
  WriteTool(
    name: 'create_transaction',
    description:
        'Adds an Unreviewed transaction. Its lines must add up to '
        'amountCents. Only a person marks a line Reviewed.',
    arguments: {
      'budgetId': BudgetTools._budgetId,
      'accountId': _accountId,
      'date': {'type': 'string', 'description': 'YYYY-MM-DD.'},
      'amountCents': _amount,
      'payee': {'type': 'string'},
      'memo': {'type': 'string'},
      'lines': {'type': 'array', 'items': _line, 'minItems': 1},
    },
    required: ['budgetId', 'accountId', 'date', 'amountCents', 'lines'],
    build: _createTransaction,
  ),
  WriteTool(
    name: 'update_transaction',
    description:
        'Changes a transaction’s payee, date, memo or cleared status. '
        'Fields left out stay as they are.',
    arguments: {
      'budgetId': BudgetTools._budgetId,
      'transactionId': {'type': 'string'},
      'payee': {'type': 'string'},
      'date': {'type': 'string', 'description': 'YYYY-MM-DD.'},
      'memo': {'type': 'string'},
      'cleared': {
        'type': 'string',
        'enum': ['uncleared', 'cleared', 'reconciled'],
      },
    },
    required: ['budgetId', 'transactionId'],
    build: _updateTransaction,
  ),
  WriteTool(
    name: 'split_transaction',
    description:
        'Replaces a transaction’s whole line set. The lines must add up to '
        'amountCents.',
    arguments: {
      'budgetId': BudgetTools._budgetId,
      'transactionId': {'type': 'string'},
      'amountCents': _amount,
      'lines': {'type': 'array', 'items': _line, 'minItems': 1},
    },
    required: ['budgetId', 'transactionId', 'amountCents', 'lines'],
    build: _splitTransaction,
  ),
  WriteTool(
    name: 'assign',
    description:
        'Sets a Category’s Assigned for a month, instead of adding to it. '
        'Recorded as a delta in Change History.',
    arguments: {
      'budgetId': BudgetTools._budgetId,
      'categoryId': _categoryId,
      'month': _monthArgument,
      'amountCents': _amount,
    },
    required: ['budgetId', 'categoryId', 'amountCents'],
    build: _assign,
  ),
  WriteTool(
    name: 'move_money',
    description:
        'Moves money of one month’s Available between Categories, or back to '
        'Ready to Assign with toCategoryId readyToAssign.',
    arguments: {
      'budgetId': BudgetTools._budgetId,
      'fromCategoryId': _categoryId,
      'toCategoryId': _categoryId,
      'month': _monthArgument,
      'amountCents': {
        'type': 'integer',
        'description': 'Whole cents, above 0.',
      },
    },
    required: ['budgetId', 'fromCategoryId', 'toCategoryId', 'amountCents'],
    build: _moveMoney,
  ),
  WriteTool(
    name: 'create_schedule',
    description:
        'Adds a Scheduled Transaction. It counts in nothing until '
        'somebody enters it.',
    arguments: {
      'budgetId': BudgetTools._budgetId,
      'accountId': _accountId,
      'payee': {'type': 'string'},
      'amountCents': _amount,
      'categoryId': _categoryId,
      'every': {'type': 'integer', 'minimum': 1},
      'interval': _interval,
      'nextDue': {'type': 'string', 'description': 'YYYY-MM-DD.'},
      'memo': {'type': 'string'},
    },
    required: [
      'budgetId',
      'accountId',
      'payee',
      'amountCents',
      'categoryId',
      'every',
      'interval',
      'nextDue',
    ],
    build: _createSchedule,
  ),
  WriteTool(
    name: 'update_schedule',
    description:
        'Changes a Scheduled Transaction’s fields. Fields left out stay as '
        'they are.',
    arguments: {
      'budgetId': BudgetTools._budgetId,
      'scheduleId': {'type': 'string'},
      'accountId': _accountId,
      'payee': {'type': 'string'},
      'amountCents': _amount,
      'categoryId': _categoryId,
      'every': {'type': 'integer', 'minimum': 1},
      'interval': _interval,
      'nextDue': {'type': 'string', 'description': 'YYYY-MM-DD.'},
      'memo': {'type': 'string'},
    },
    required: ['budgetId', 'scheduleId'],
    build: _updateSchedule,
  ),
  WriteTool(
    name: 'set_target',
    description:
        'Gives a Category a Target, replacing the one it had. kind is '
        'repeating (every and interval and nextDue), byDate (date), '
        'keepAtLeast, or schedule.',
    arguments: {
      'budgetId': BudgetTools._budgetId,
      'categoryId': _categoryId,
      'kind': {
        'type': 'string',
        'enum': ['repeating', 'byDate', 'keepAtLeast', 'schedule'],
      },
      'amountCents': _amount,
      'every': {'type': 'integer', 'minimum': 1},
      'interval': _interval,
      'nextDue': {'type': 'string', 'description': 'YYYY-MM-DD.'},
      'date': {'type': 'string', 'description': 'YYYY-MM-DD, for byDate.'},
    },
    required: ['budgetId', 'categoryId', 'kind'],
    build: _setTarget,
  ),
  WriteTool(
    name: 'clear_target',
    description: 'Removes a Category’s Target.',
    arguments: {'budgetId': BudgetTools._budgetId, 'categoryId': _categoryId},
    required: ['budgetId', 'categoryId'],
    build: _clearTarget,
  ),
  WriteTool(
    name: 'create_category',
    description:
        'Adds a Category to an existing group. list_categories gives the '
        'group ids.',
    arguments: {
      'budgetId': BudgetTools._budgetId,
      'groupId': {'type': 'string'},
      'name': {'type': 'string'},
    },
    required: ['budgetId', 'groupId', 'name'],
    build: _createCategory,
  ),
  WriteTool(
    name: 'rename_category',
    description: 'Renames a Category. Its group, Target and lines stay.',
    arguments: {
      'budgetId': BudgetTools._budgetId,
      'categoryId': _categoryId,
      'name': {'type': 'string'},
    },
    required: ['budgetId', 'categoryId', 'name'],
    build: _renameCategory,
  ),
  WriteTool(
    name: 'archive_category',
    description:
        'Archives a Category. Refused while its Available is not 0.00.',
    arguments: {
      'budgetId': BudgetTools._budgetId,
      'categoryId': _categoryId,
      'month': _monthArgument,
    },
    required: ['budgetId', 'categoryId'],
    build: _archiveCategory,
  ),
  WriteTool(
    name: 'suggest_review',
    description:
        'Fills a line’s Category and business status. The line stays '
        'Unreviewed: only a person marks it Reviewed in the app.',
    arguments: {
      'budgetId': BudgetTools._budgetId,
      'transactionId': {'type': 'string'},
      'lineId': {'type': 'string'},
      'categoryId': _categoryId,
      'business': {
        'type': 'string',
        'enum': ['personal', 'business'],
      },
      'businessTag': {'type': 'string'},
      'recipient': {'type': 'string', 'description': 'For a gift line.'},
    },
    required: ['budgetId', 'transactionId', 'lineId'],
    build: _suggestReview,
  ),
  WriteTool(
    name: 'revert_change',
    description:
        'Reverts one Event group MCP wrote, by the groupId a write tool '
        'returned. Nothing is erased, and a revert can be redone.',
    arguments: {
      'budgetId': BudgetTools._budgetId,
      'groupId': {'type': 'string'},
    },
    required: ['budgetId', 'groupId'],
    build: _revertChange,
  ),
];

const _reconciledIsAPersons =
    'Reconciled is the person\'s call: they must make that change in the app.';

Command _createTransaction(ToolRequest request, CalendarMonth thisMonth) =>
    CreateTransaction(
      accountId: request.requireString('accountId'),
      date: request.requireDate('date'),
      amount: Money(request.requireInt('amountCents')),
      lines: _lines(request),
      payee: request.text('payee')?.trim() ?? '',
      memo: request.text('memo') ?? '',
    );

Command _updateTransaction(ToolRequest request, CalendarMonth thisMonth) =>
    EditTransaction(
      transactionId: request.requireString('transactionId'),
      payee: request.text('payee'),
      date: request.date('date'),
      memo: request.text('memo'),
      cleared: switch (request.string('cleared')) {
        null => null,
        'reconciled' => throw const _Refusal(_reconciledIsAPersons),
        final name =>
          ClearedStatus.values.asNameMap()[name] ??
              (throw const _Refusal('“cleared” must be uncleared or cleared.')),
      },
    );

Command _splitTransaction(ToolRequest request, CalendarMonth thisMonth) =>
    EditTransaction(
      transactionId: request.requireString('transactionId'),
      amount: Money(request.requireInt('amountCents')),
      lines: _lines(request),
    );

Command _assign(ToolRequest request, CalendarMonth thisMonth) => SetAssignment(
  categoryId: request.requireString('categoryId'),
  month: request.month('month', thisMonth),
  amount: Money(request.requireInt('amountCents')),
);

Command _moveMoney(ToolRequest request, CalendarMonth thisMonth) => MoveMoney(
  fromCategoryId: request.requireString('fromCategoryId'),
  toCategoryId: request.requireString('toCategoryId'),
  month: request.month('month', thisMonth),
  amount: Money(request.requireInt('amountCents')),
);

Command _createSchedule(ToolRequest request, CalendarMonth thisMonth) =>
    CreateSchedule(
      accountId: request.requireString('accountId'),
      payee: request.requireString('payee'),
      amount: Money(request.requireInt('amountCents')),
      category: request.requireString('categoryId'),
      every: request.requireInt('every'),
      interval: _targetInterval(request, mustGive: true)!,
      nextDue: request.requireDate('nextDue'),
      memo: request.text('memo') ?? '',
    );

Command _updateSchedule(ToolRequest request, CalendarMonth thisMonth) =>
    EditSchedule(
      scheduleId: request.requireString('scheduleId'),
      accountId: request.string('accountId'),
      payee: request.text('payee'),
      amount: switch (request.integer('amountCents')) {
        final cents? => Money(cents),
        null => null,
      },
      category: request.string('categoryId'),
      every: request.integer('every'),
      interval: _targetInterval(request),
      nextDue: request.date('nextDue'),
      memo: request.text('memo'),
    );

Command _setTarget(ToolRequest request, CalendarMonth thisMonth) {
  final amount = Money(request.integer('amountCents') ?? 0);
  final target = switch (request.requireOneOf('kind', const [
    'repeating',
    'byDate',
    'keepAtLeast',
    'schedule',
  ])) {
    'repeating' => RepeatingTarget(
      amount: amount,
      every: request.integer('every') ?? 1,
      interval: _targetInterval(request) ?? TargetInterval.months,
      nextDue: request.requireDate('nextDue'),
    ),
    'byDate' => ByDateTarget(amount: amount, date: request.requireDate('date')),
    'keepAtLeast' => KeepAtLeastTarget(amount: amount),
    _ => const DrivenByScheduleTarget(),
  };
  return SetTarget(
    categoryId: request.requireString('categoryId'),
    target: target,
  );
}

Command _clearTarget(ToolRequest request, CalendarMonth thisMonth) =>
    ClearTarget(categoryId: request.requireString('categoryId'));

Command _createCategory(ToolRequest request, CalendarMonth thisMonth) =>
    CreateCategory(
      groupId: request.requireString('groupId'),
      name: request.requireString('name'),
    );

Command _renameCategory(ToolRequest request, CalendarMonth thisMonth) =>
    RenameCategory(
      categoryId: request.requireString('categoryId'),
      name: request.requireString('name'),
    );

Command _archiveCategory(ToolRequest request, CalendarMonth thisMonth) =>
    ArchiveCategory(
      categoryId: request.requireString('categoryId'),
      month: request.month('month', thisMonth),
    );

Command _suggestReview(ToolRequest request, CalendarMonth thisMonth) =>
    SuggestReview(
      transactionId: request.requireString('transactionId'),
      lineId: request.requireString('lineId'),
      category: request.string('categoryId'),
      business: _business(request),
      recipient: request.text('recipient'),
    );

Command _revertChange(ToolRequest request, CalendarMonth thisMonth) =>
    RevertGroup(groupId: request.requireString('groupId'));

/// The lines of a [CreateTransaction] or [EditTransaction], each in cents.
List<LineInput> _lines(ToolRequest request) {
  final lines = request.arguments['lines'];
  if (lines is! List || lines.isEmpty) {
    throw const _Refusal('“lines” must be one or more lines.');
  }
  return [
    for (final line in lines)
      _lineInput(switch (line) {
        final Map value => value.cast<String, Object?>(),
        _ => throw const _Refusal('Each line must be an object.'),
      }),
  ];
}

LineInput _lineInput(Map<String, Object?> line) => LineInput(
  amount: Money(switch (line['amountCents']) {
    final int cents => cents,
    final double cents
        when cents.isFinite && cents == cents.truncateToDouble() =>
      cents.toInt(),
    _ => throw const _Refusal('“amountCents” must be whole cents.'),
  }),
  category: switch (line['categoryId']) {
    final String id when id.isNotEmpty => id,
    _ => null,
  },
  business: switch (line['business']) {
    'personal' => const Personal(),
    'business' => Business((line['businessTag'] as String?)?.trim() ?? ''),
    null => null,
    _ => throw const _Refusal('“business” must be personal or business.'),
  },
  memo: line['memo'] as String? ?? '',
  recipient: switch (line['recipient']) {
    final String recipient => recipient.trim(),
    _ => null,
  },
);

/// `personal` or `business` (with a tag), or null when the call leaves it out.
BusinessStatus? _business(ToolRequest request) =>
    switch (request.string('business')) {
      null => null,
      'personal' => const Personal(),
      'business' => Business(request.string('businessTag')?.trim() ?? ''),
      _ => throw const _Refusal('“business” must be personal or business.'),
    };

/// `days`, `weeks`, `months` or `years`, or null when it isn't given.
TargetInterval? _targetInterval(ToolRequest request, {bool mustGive = false}) =>
    switch (request.string('interval')) {
      final name? =>
        TargetInterval.values.asNameMap()[name] ??
            (throw const _Refusal(
              '“interval” must be days, weeks, months or years.',
            )),
      null when mustGive => throw const _Refusal('“interval” is required.'),
      null => null,
    };

/// Ticket 13's wording for a value that looks like a card or account number.
const _sensitiveNumber = 'Account or card numbers can\'t be stored.';

/// A client-facing sentence for a Command's [Rejection].
String _rejection(Rejection reason) => switch (reason) {
  Rejection.accountNumberNotAllowed => _sensitiveNumber,
  Rejection.unknownAccount => 'No account with that id.',
  Rejection.unknownCategory => 'No Category with that id.',
  Rejection.unknownCategoryGroup => 'No Category group with that id.',
  Rejection.categoryArchived => 'That Category is archived.',
  Rejection.categoryHasBalance =>
    'That Category still has money. Move it out before archiving it.',
  Rejection.unknownTransaction => 'No transaction with that id.',
  Rejection.unknownLine => 'That transaction has no such line.',
  Rejection.unknownSchedule => 'No Scheduled Transaction with that id.',
  Rejection.alreadyReviewed =>
    'That line is already Reviewed. Change it in the app.',
  Rejection.transferNotReviewable =>
    'A transfer line has nothing to suggest: a transfer isn’t spending.',
  Rejection.personRequired =>
    'Only a person marks a line Reviewed. Use suggest_review instead.',
  Rejection.noChange => 'That would change nothing.',
  Rejection.nameRequired => 'A name is required.',
  Rejection.zeroAmount => 'An amount of 0.00 changes nothing.',
  Rejection.noLines => 'Give at least one line.',
  Rejection.splitDoesNotSum => 'The lines must add up to the amount.',
  Rejection.amountMustBePositive => 'The amount must be more than zero.',
  Rejection.incomeMustBePositive => 'Income must be more than zero.',
  Rejection.sameCategory => 'Choose two different Categories.',
  Rejection.sameAccount => 'Choose two different accounts.',
  Rejection.businessTagRequired =>
    '“business” needs a “businessTag”. Give the tag the line reports under.',
  Rejection.categoryRequired => 'A Category is required.',
  Rejection.scheduleCategoryRequired =>
    'Income needs readyToAssign as its Category, and an outflow a Category.',
  Rejection.targetAmountMustBePositive => 'The Target must be more than zero.',
  Rejection.intervalMustBePositive => '“every” must be 1 or more.',
  Rejection.reconciledNeedsConfirmation => _reconciledIsAPersons,
  Rejection.unknownGroup => 'No change with that group id.',
  Rejection.alreadyReverted => 'That change is already reverted.',
  Rejection.hasDependents || Rejection.cannotRevert =>
    'That change can’t be reverted from here. Do it in the app.',
  _ => 'The app refused that change (${reason.name}).',
};
