import 'package:budget_core/budget_core.dart';
import 'package:budget_simplefin/budget_simplefin.dart';
import 'package:budget_sync/budget_sync.dart';
import 'package:flutter/material.dart';

import 'budget_library.dart';
import 'desktop.dart';
import 'flows.dart';
import 'screens/account_register_screen.dart';
import 'screens/add_account_screen.dart';
import 'screens/budget_switcher.dart';
import 'screens/new_transaction_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/welcome_screen.dart';
import 'services.dart';
import 'theme.dart';
import 'widgets.dart';

/// The app window. Below [desktopBreakpoint] it is the phone app, untouched.
/// Above it, the app's screens run in a Mac window instead of one centred
/// column (ticket 61): a toolbar with the budget name, the month, New
/// transaction and Settings, and a sidebar of sections and accounts beside
/// them. A section swaps the content area with no route animation, and the
/// screens push their own routes into that area, so the sidebar is always
/// there.
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  /// The content area's Navigator: what a section and the screens it opens
  /// run in.
  final _contentKey = GlobalKey<NavigatorState>();
  var _section = Section.budget;
  var _month = thisMonth();
  var _syncBook = SyncBook.off;
  var _bankBook = const SimpleFinBook();
  BudgetLibrary? _library;
  BudgetEngine? _engine;
  BudgetState? _state;
  var _booksRead = false;

  @override
  void initState() {
    super.initState();
    // The sidebar's numbers follow every Event. The engine has no change
    // notification and every state change is an Event (ADR 0001), so each
    // frame compares the state object it replayed: a new one means a change.
    _watchNextFrame();
  }

  void _watchNextFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _followEngine();
      _watchNextFrame();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _library = BudgetLibraryScope.of(context);
    if (_booksRead) return;
    _booksRead = true;
    _readBooks();
  }

  /// A context inside the content area, for the flows the window itself opens.
  BuildContext get _content => _contentKey.currentState!.overlay!.context;

  void _followEngine() {
    final engine = _library?.current;
    if (engine == null || identical(engine.state, _state)) return;
    final switched = !identical(engine, _engine);
    _engine = engine;
    _state = engine.state;
    setState(() {
      // Another budget opens on its Budget month.
      if (switched) _section = Section.budget;
    });
  }

  /// The device's last sync and last bank fetch, which are not Events.
  Future<void> _readBooks() async {
    final services = AppServicesScope.of(context);
    final budget = _library?.current.state.budget;
    final bank = await services.prefs.readSimpleFinBook();
    final sync = budget == null
        ? SyncBook.off
        : await services.prefs.readSyncBook(budget.id);
    if (!mounted) return;
    setState(() {
      _bankBook = bank;
      _syncBook = sync;
    });
  }

  PageRoute<void> _sectionRoute(
    BudgetEngine engine,
    AppServices services,
    Section section,
  ) => PageRouteBuilder<void>(
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (_, _, _) => section.screen(engine, services),
  );

  /// Swaps the content area for [section]'s screen, with no route animation.
  void _go(Section section) {
    if (section == _section) return;
    _contentKey.currentState!.pushReplacement(
      _sectionRoute(_library!.current, AppServicesScope.of(context), section),
    );
    setState(() => _section = section);
  }

  Future<void> _openAccount(Account account) async {
    await _contentKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => AccountRegisterScreen(
          engine: _library!.current,
          accountId: account.id,
        ),
      ),
    );
    if (mounted) await _readBooks();
  }

  Future<void> _addAccount() async {
    await openFlow<void>(
      _content,
      builder: (_) => AddAccountScreen(engine: _library!.current),
    );
    if (mounted) await _readBooks();
  }

  Future<void> _newTransaction() => openFlow<void>(
    _content,
    builder: (_) => NewTransactionScreen(engine: _library!.current),
  );

  /// Opens another Budget in this window (ticket 68). Its section screens were
  /// built for the old engine, so the content area starts again on the Budget
  /// month of the one chosen.
  Future<void> _openBudget(String id) async {
    final library = _library!;
    if (library.entries.any((entry) => entry.id == id && entry.isOpen)) return;
    final engine = await library.switchTo(id);
    if (!mounted) return;
    _contentKey.currentState?.pushAndRemoveUntil(
      _sectionRoute(engine, AppServicesScope.of(context), Section.budget),
      (_) => false,
    );
    setState(() {
      _engine = engine;
      _state = engine.state;
      _section = Section.budget;
    });
    await _readBooks();
  }

  /// A new Budget is a draft until its first account is saved, which commits
  /// it and opens this window on it (as the Welcome flow already does).
  Future<void> _newBudget() => Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      builder: (_) => WelcomeScreen(engine: _library!.startNew()),
    ),
  );

  /// Settings is where Budgets are renamed, archived and made (ticket 66).
  Future<void> _manageBudgets() => _openSettings();

  /// A search result: a line still to Review opens Review, where the person
  /// can finish it; anything else opens its account's register.
  Future<void> _openTransaction(Transaction transaction) async {
    final state = _library!.current.state;
    final needsReview = state.reviewQueue.any(
      (item) => item.transaction.id == transaction.id,
    );
    if (needsReview) {
      _go(Section.review);
      return;
    }
    final account = state.account(transaction.accountId);
    if (account == null) return;
    await _openAccount(account);
  }

  Future<void> _openSettings() async {
    await _contentKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          engine: _library!.current,
          services: AppServicesScope.of(context),
        ),
      ),
    );
    if (mounted) await _readBooks();
  }

  /// `Synced 4:12 PM · Bank Oct 30`, or what is still off.
  String get _syncText {
    final last = _syncBook.lastSync;
    final fetched = _bankBook.lastFetch;
    return [
      last == null ? 'Sync off' : 'Synced ${formatTime(last)}',
      fetched == null ? 'No bank fetch' : 'Bank ${formatDay(fetched)}',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final library = BudgetLibraryScope.of(context);
    final engine = library.current;
    final services = AppServicesScope.of(context);
    // Welcome fills the window: there is nothing to navigate yet.
    if (engine.state.budget == null) return WelcomeScreen(engine: engine);
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth < desktopBreakpoint
          ? Section.budget.screen(engine, services)
          : DesktopWindowScope(
              month: _month,
              onMonthChanged: (month) => setState(() => _month = month),
              child: Scaffold(
                body: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Toolbar(
                      name: engine.state.budget!.name,
                      budgets: library.entries,
                      state: engine.state,
                      month: _month,
                      onMonthChanged: (month) => setState(() => _month = month),
                      onOpenBudget: _openBudget,
                      onNewBudget: _newBudget,
                      onManageBudgets: _manageBudgets,
                      onOpenTransaction: _openTransaction,
                      onNewTransaction: _newTransaction,
                      onSettings: _openSettings,
                    ),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Sidebar(
                            state: engine.state,
                            section: _section,
                            onSection: _go,
                            onAccount: _openAccount,
                            onAddAccount: _addAccount,
                            sync: _syncText,
                          ),
                          Expanded(
                            child: Navigator(
                              key: _contentKey,
                              onGenerateRoute: (_) =>
                                  _sectionRoute(engine, services, _section),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// The budget name and its switcher popover, the month, search, New
/// transaction and Settings.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.name,
    required this.budgets,
    required this.state,
    required this.month,
    required this.onMonthChanged,
    required this.onOpenBudget,
    required this.onNewBudget,
    required this.onManageBudgets,
    required this.onOpenTransaction,
    required this.onNewTransaction,
    required this.onSettings,
  });

  final String name;
  final List<BudgetEntry> budgets;

  /// The open budget, for search.
  final BudgetState state;
  final CalendarMonth month;
  final ValueChanged<CalendarMonth> onMonthChanged;
  final ValueChanged<String> onOpenBudget;
  final VoidCallback onNewBudget;
  final VoidCallback onManageBudgets;
  final ValueChanged<Transaction> onOpenTransaction;
  final VoidCallback onNewTransaction;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => Container(
    height: 60,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: const BoxDecoration(
      color: Palette.card,
      border: Border(bottom: BorderSide(color: Palette.cardBorder)),
    ),
    child: Row(
      spacing: 12,
      children: [
        BudgetSwitcherMenu(
          name: name,
          entries: budgets,
          onOpen: onOpenBudget,
          onNew: onNewBudget,
          onManage: onManageBudgets,
        ),
        const Spacer(),
        MonthSwitcher(month: month, onChanged: onMonthChanged),
        _ToolbarSearch(state: state, onOpen: onOpenTransaction),
        FilledButton.icon(
          onPressed: onNewTransaction,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New transaction'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
        ),
        IconButton(
          onPressed: onSettings,
          tooltip: 'Settings',
          icon: const Icon(Icons.settings_outlined),
          color: Palette.inkSoft,
          iconSize: 22,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        ),
      ],
    ),
  );
}

/// The toolbar's search field: every transaction whose payee or memo contains
/// what was typed, newest first. Choosing one opens it (ticket 68).
class _ToolbarSearch extends StatefulWidget {
  const _ToolbarSearch({required this.state, required this.onOpen});

  final BudgetState state;
  final ValueChanged<Transaction> onOpen;

  @override
  State<_ToolbarSearch> createState() => _ToolbarSearchState();
}

class _ToolbarSearchState extends State<_ToolbarSearch> {
  final _controller = SearchController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Iterable<Widget> _suggestions(SearchController controller) {
    final query = controller.text.trim();
    if (query.isEmpty) {
      return const [_SearchNote('Search payees and memos')];
    }
    final results = _findTransactions(widget.state, query);
    if (results.isEmpty) {
      return const [_SearchNote('No matching transactions')];
    }
    return [
      for (final transaction in results)
        _SearchResult(
          transaction: transaction,
          account: widget.state.account(transaction.accountId)?.name ?? '',
          needsReview: widget.state.reviewQueue.any(
            (item) => item.transaction.id == transaction.id,
          ),
          onTap: () {
            controller.closeView(null);
            // The field starts empty the next time it is opened.
            controller.clear();
            widget.onOpen(transaction);
          },
        ),
    ];
  }

  @override
  Widget build(BuildContext context) => SearchAnchor(
    searchController: _controller,
    // A floating view beside the window, as a Mac search field behaves.
    isFullScreen: false,
    viewHintText: 'Search payees and memos',
    builder: (context, controller) => SizedBox(
      width: 240,
      child: TextField(
        key: const ValueKey('toolbar-search'),
        controller: controller,
        onTap: controller.openView,
        style: const TextStyle(fontSize: 14),
        decoration: const InputDecoration(
          hintText: 'Search',
          prefixIcon: Icon(Icons.search, size: 18),
          prefixIconConstraints: BoxConstraints(minWidth: 34),
        ),
      ),
    ),
    suggestionsBuilder: (context, controller) => _suggestions(controller),
  );
}

/// One search result: its payee, the date and account, and its amount.
class _SearchResult extends StatelessWidget {
  const _SearchResult({
    required this.transaction,
    required this.account,
    required this.needsReview,
    required this.onTap,
  });

  final Transaction transaction;
  final String account;
  final bool needsReview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    return InkWell(
      key: ValueKey('search-${t.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          spacing: 12,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    t.payee.isEmpty ? 'No payee' : t.payee,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15),
                  ),
                  Text(
                    [
                      formatDay(t.date),
                      account,
                      if (needsReview) 'To review',
                    ].join(' · '),
                    style: const TextStyle(fontSize: 12, color: Palette.muted),
                  ),
                ],
              ),
            ),
            Text(formatSigned(t.amount), style: amountStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

/// What the search view says when there is nothing to list.
class _SearchNote extends StatelessWidget {
  const _SearchNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13, color: Palette.muted),
    ),
  );
}

/// Every transaction whose payee or memo contains [query], newest first.
List<Transaction> _findTransactions(BudgetState state, String query) {
  final needle = query.toLowerCase();
  bool matches(String value) => value.toLowerCase().contains(needle);
  return [
    for (final transaction in state.transactions)
      if (matches(transaction.payee) ||
          matches(transaction.memo) ||
          transaction.lines.any((line) => matches(line.memo)))
        transaction,
  ]..sort((a, b) => b.date.compareTo(a.date));
}

/// Every section, then the budget accounts with their total, Tracking Accounts
/// apart, Add account and the sync line.
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.state,
    required this.section,
    required this.onSection,
    required this.onAccount,
    required this.onAddAccount,
    required this.sync,
  });

  final BudgetState state;
  final Section section;
  final ValueChanged<Section> onSection;
  final ValueChanged<Account> onAccount;
  final VoidCallback onAddAccount;
  final String sync;

  @override
  Widget build(BuildContext context) {
    final budget = [
      for (final account in state.accounts)
        if (account.type.onBudget) account,
    ];
    final tracking = [
      for (final account in state.accounts)
        if (!account.type.onBudget) account,
    ];
    return Container(
      key: const ValueKey('sidebar'),
      width: 240,
      decoration: const BoxDecoration(
        color: Palette.card,
        border: Border(right: BorderSide(color: Palette.cardBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              children: [
                for (final item in Section.values)
                  _SectionRow(
                    section: item,
                    badge: item.badge(state),
                    selected: item == section,
                    onTap: () => onSection(item),
                  ),
                if (budget.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _AccountGroup(
                    title: 'Budget accounts',
                    total: budget.fold<Money>(
                      Money.zero,
                      (sum, account) => sum + state.balance(account.id),
                    ),
                    accounts: budget,
                    state: state,
                    onAccount: onAccount,
                  ),
                ],
                if (tracking.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _AccountGroup(
                    title: 'Tracking accounts',
                    accounts: tracking,
                    state: state,
                    onAccount: onAccount,
                  ),
                ],
                const SizedBox(height: 8),
                _AddAccountRow(onTap: onAddAccount),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Palette.cardBorder)),
            ),
            child: Text(
              sync,
              key: const ValueKey('sync-status'),
              style: const TextStyle(fontSize: 11, color: Palette.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// One section in the sidebar, dark when it is the one on screen.
class _SectionRow extends StatelessWidget {
  const _SectionRow({
    required this.section,
    required this.badge,
    required this.selected,
    required this.onTap,
  });

  final Section section;

  /// A count shown after the label, hidden at 0.
  final int badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: badge > 0 ? '${section.label}, $badge to review' : section.label,
    excludeSemantics: true,
    child: InkWell(
      key: ValueKey('section-${section.name}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? Palette.zeroPill : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          spacing: 10,
          children: [
            Icon(
              section.icon,
              size: 18,
              color: selected ? Palette.ink : Palette.muted,
            ),
            Expanded(
              child: Text(
                section.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: Palette.ink,
                ),
              ),
            ),
            if (badge > 0)
              Container(
                key: ValueKey('${section.label}-badge'),
                constraints: const BoxConstraints(minWidth: 18),
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Palette.problemText,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$badge',
                  style: amountStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// A titled list of accounts, with the total when it is budget money.
class _AccountGroup extends StatelessWidget {
  const _AccountGroup({
    required this.title,
    required this.accounts,
    required this.state,
    required this.onAccount,
    this.total,
  });

  final String title;
  final List<Account> accounts;
  final BudgetState state;
  final ValueChanged<Account> onAccount;

  /// Shown on the right of the title, for budget accounts only.
  final Money? total;

  @override
  Widget build(BuildContext context) {
    final total = this.total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.88,
                    color: Palette.muted,
                  ),
                ),
              ),
              if (total != null)
                Text(
                  total.format(),
                  key: const ValueKey('budget-accounts-total'),
                  style: amountStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Palette.muted,
                  ),
                ),
            ],
          ),
        ),
        for (final account in accounts)
          _AccountRow(
            account: account,
            balance: state.balance(account.id),
            // A card's balance owed, or an overdrawn account, is a problem.
            problem:
                account.type.onBudget && state.balance(account.id).isNegative,
            onTap: () => onAccount(account),
          ),
      ],
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.account,
    required this.balance,
    required this.problem,
    required this.onTap,
  });

  final Account account;
  final Money balance;
  final bool problem;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    key: ValueKey('account-${account.id}'),
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              account.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: Palette.inkSoft),
            ),
          ),
          Text(
            balance.format(),
            style: amountStyle(
              fontSize: 12,
              color: problem ? Palette.problemText : Palette.ink,
            ),
          ),
        ],
      ),
    ),
  );
}

class _AddAccountRow extends StatelessWidget {
  const _AddAccountRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        spacing: 10,
        children: [
          const Icon(Icons.add, size: 16, color: Palette.teal),
          const Text(
            'Add account',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Palette.teal,
            ),
          ),
        ],
      ),
    ),
  );
}
