import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import 'app_lock_gate.dart';
import 'budget_library.dart';
import 'desktop_menu.dart';
import 'services.dart';
import 'shell.dart';
import 'theme.dart';

class BudgetApp extends StatelessWidget {
  BudgetApp({
    super.key,
    BudgetEngine? engine,
    BudgetLibrary? library,
    AppServices? services,
  }) : assert(engine != null || library != null),
       services = services ?? AppServices.inMemory(),
       library = library ?? BudgetLibrary.single(engine!);

  /// The budgets on this device. Given just an [engine], it is the only one.
  final BudgetLibrary library;

  /// The device's key store, preferences, file dialog and lock check.
  /// Defaults to in-memory ones, for tests and previews.
  final AppServices services;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Budget',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    // The lock screen covers the whole window, and the shell frames the app's
    // screens: the phone app below the breakpoint, a Mac window above it
    // (ticket 61).
    builder: (context, child) => BudgetLibraryScope(
      library: library,
      child: AppServicesScope(
        services: services,
        child: DesktopMenuHost(
          child: AppLockGate(services: services, child: child!),
        ),
      ),
    ),
    home: const DesktopShell(),
  );
}
