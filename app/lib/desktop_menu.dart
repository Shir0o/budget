import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'desktop.dart';
import 'widgets.dart';

/// The menus a Mac window carries (ticket 69), in the order macOS shows them.
enum DesktopMenu {
  budget('Budget'),
  file('File'),
  edit('Edit'),
  view('View'),
  transaction('Transaction'),
  window('Window'),
  help('Help');

  const DesktopMenu(this.label);

  final String label;
}

/// One thing a Mac window's menu bar and keyboard shortcuts do (ticket 69).
///
/// Each is the action the toolbar or sidebar button of the same name runs, so
/// the menus, the keys and the buttons can't drift apart.
enum DesktopAction {
  newBudget(DesktopMenu.file, title: 'New budget…'),
  manageBudgets(DesktopMenu.file, title: 'Manage budgets…'),
  newAccount(DesktopMenu.file, title: 'New account…'),
  settings(
    DesktopMenu.budget,
    title: 'Settings…',
    shortcut: SingleActivator(LogicalKeyboardKey.comma, meta: true),
  ),
  undo(
    DesktopMenu.edit,
    title: 'Undo',
    shortcut: SingleActivator(LogicalKeyboardKey.keyZ, meta: true),
  ),
  search(
    DesktopMenu.edit,
    title: 'Search Transactions',
    shortcut: SingleActivator(LogicalKeyboardKey.keyF, meta: true),
  ),
  sectionBudget(
    DesktopMenu.view,
    section: Section.budget,
    shortcut: SingleActivator(LogicalKeyboardKey.digit1, meta: true),
  ),
  sectionReview(
    DesktopMenu.view,
    section: Section.review,
    shortcut: SingleActivator(LogicalKeyboardKey.digit2, meta: true),
  ),
  sectionAccounts(DesktopMenu.view, section: Section.accounts),
  sectionHistory(
    DesktopMenu.view,
    section: Section.history,
    shortcut: SingleActivator(LogicalKeyboardKey.digit5, meta: true),
  ),
  sectionForecast(
    DesktopMenu.view,
    section: Section.forecast,
    shortcut: SingleActivator(LogicalKeyboardKey.digit3, meta: true),
  ),
  sectionBusinessReport(
    DesktopMenu.view,
    section: Section.businessReport,
    shortcut: SingleActivator(LogicalKeyboardKey.digit4, meta: true),
  ),
  previousMonth(
    DesktopMenu.view,
    title: 'Previous month',
    shortcut: SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true),
  ),
  nextMonth(
    DesktopMenu.view,
    title: 'Next month',
    shortcut: SingleActivator(LogicalKeyboardKey.bracketRight, meta: true),
  ),
  newTransaction(
    DesktopMenu.transaction,
    title: 'New transaction…',
    shortcut: SingleActivator(LogicalKeyboardKey.keyN, meta: true),
  ),
  goToReview(DesktopMenu.transaction, title: 'Go to Review');

  const DesktopAction(
    this.menu, {
    this.title = '',
    this.section,
    this.shortcut,
  });

  final DesktopMenu menu;

  /// The item's own words, when it doesn't open a section.
  final String title;

  /// The section this opens, for the View menu's items.
  final Section? section;
  final SingleActivator? shortcut;

  /// What the menu item reads: the section's label, or its own.
  String get label => section?.label ?? title;

  /// The action that opens [section], so the View menu lists them in the
  /// same order as the sidebar.
  static DesktopAction forSection(Section section) =>
      values.firstWhere((action) => action.section == section);
}

/// The window's menu bar: seven menus whose items run [onAction] (ticket 69).
/// Each item carries the key that also runs it, as macOS lists it.
List<PlatformMenuItem> desktopMenus(ValueChanged<DesktopAction> onAction) {
  PlatformMenuItem item(DesktopAction action) => PlatformMenuItem(
    label: action.label,
    shortcut: action.shortcut,
    onSelected: () => onAction(action),
  );

  /// One menu, its groups separated, and a group the platform has no items
  /// for left out (the platform's own items, off the Mac).
  PlatformMenu menu(DesktopMenu menu, List<List<PlatformMenuItem>> groups) =>
      PlatformMenu(
        label: menu.label,
        menus: [
          for (final items in groups)
            if (items.isNotEmpty) PlatformMenuItemGroup(members: items),
        ],
      );

  /// The platform's own items, where it has them.
  List<PlatformMenuItem> provided(List<PlatformProvidedMenuItemType> types) => [
    for (final type in types)
      if (PlatformProvidedMenuItem.hasMenu(type))
        PlatformProvidedMenuItem(type: type),
  ];

  return [
    // The app menu, as macOS names it: the app's own settings and quitting.
    menu(DesktopMenu.budget, [
      [item(DesktopAction.settings)],
      provided([
        PlatformProvidedMenuItemType.hide,
        PlatformProvidedMenuItemType.hideOtherApplications,
        PlatformProvidedMenuItemType.showAllApplications,
      ]),
      provided([PlatformProvidedMenuItemType.quit]),
    ]),
    // A Budget is a file in this app.
    menu(DesktopMenu.file, [
      [item(DesktopAction.newBudget), item(DesktopAction.manageBudgets)],
      [item(DesktopAction.newAccount)],
    ]),
    menu(DesktopMenu.edit, [
      [item(DesktopAction.undo)],
      [item(DesktopAction.search)],
    ]),
    menu(DesktopMenu.view, [
      [
        for (final section in Section.values)
          item(DesktopAction.forSection(section)),
      ],
      [item(DesktopAction.previousMonth), item(DesktopAction.nextMonth)],
    ]),
    menu(DesktopMenu.transaction, [
      [item(DesktopAction.newTransaction)],
      [item(DesktopAction.goToReview)],
    ]),
    menu(DesktopMenu.window, [
      provided([
        PlatformProvidedMenuItemType.minimizeWindow,
        PlatformProvidedMenuItemType.zoomWindow,
      ]),
      provided([PlatformProvidedMenuItemType.toggleFullScreen]),
    ]),
    menu(DesktopMenu.help, [
      provided([PlatformProvidedMenuItemType.about]),
    ]),
  ];
}

/// What a Mac window's menu items run: the window on screen registers itself
/// here, so the app's one menu bar reaches whatever window is showing
/// (ticket 69).
class DesktopCommands {
  /// The window's action runner, or null when the window isn't showing.
  ValueChanged<DesktopAction>? run;
}

/// Gives the app's menu bar the window's actions.
class DesktopCommandsScope extends InheritedWidget {
  const DesktopCommandsScope({
    super.key,
    required this.commands,
    required super.child,
  });

  final DesktopCommands commands;

  static DesktopCommands? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DesktopCommandsScope>()
      ?.commands;

  @override
  bool updateShouldNotify(DesktopCommandsScope old) => commands != old.commands;
}

/// The app's menu bar (ticket 69). macOS shows one for the app rather than one
/// per window, and a phone has none, so it is mounted here, above the window,
/// and only at desktop width.
class DesktopMenuHost extends StatefulWidget {
  const DesktopMenuHost({super.key, required this.child});

  final Widget child;

  @override
  State<DesktopMenuHost> createState() => _DesktopMenuHostState();
}

class _DesktopMenuHostState extends State<DesktopMenuHost> {
  final _commands = DesktopCommands();

  @override
  Widget build(BuildContext context) {
    final app = DesktopCommandsScope(commands: _commands, child: widget.child);
    if (defaultTargetPlatform != TargetPlatform.macOS ||
        MediaQuery.sizeOf(context).width < desktopBreakpoint) {
      return app;
    }
    return PlatformMenuBar(
      menus: desktopMenus((action) => _commands.run?.call(action)),
      child: app,
    );
  }
}
