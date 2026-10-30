import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import 'app_lock_gate.dart';
import 'budget_library.dart';
import 'desktop.dart';
import 'screens/budget_screen.dart';
import 'screens/welcome_screen.dart';
import 'services.dart';
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
    builder: (context, child) => BudgetLibraryScope(
      library: library,
      child: AppServicesScope(
        services: services,
        child: DesktopFrame(
          child: AppLockGate(services: services, child: child!),
        ),
      ),
    ),
    home: library.current.state.budget == null
        ? WelcomeScreen(engine: library.current)
        : BudgetScreen(engine: library.current),
  );
}
