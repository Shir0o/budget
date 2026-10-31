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

  Future<void> _switchBudget() => showBudgetSwitcher(_content);

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
                      month: _month,
                      onMonthChanged: (month) => setState(() => _month = month),
                      onSwitchBudget: _switchBudget,
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

/// The budget name, the month, New transaction and Settings.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.name,
    required this.month,
    required this.onMonthChanged,
    required this.onSwitchBudget,
    required this.onNewTransaction,
    required this.onSettings,
  });

  final String name;
  final CalendarMonth month;
  final ValueChanged<CalendarMonth> onMonthChanged;
  final VoidCallback onSwitchBudget;
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
        Semantics(
          button: true,
          label: 'Switch budget',
          child: InkWell(
            onTap: onSwitchBudget,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down, size: 16),
                ],
              ),
            ),
          ),
        ),
        const Spacer(),
        MonthSwitcher(month: month, onChanged: onMonthChanged),
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
