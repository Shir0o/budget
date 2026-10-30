import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import 'app_lock_gate.dart';
import 'screens/budget_screen.dart';
import 'screens/welcome_screen.dart';
import 'services.dart';
import 'theme.dart';

class BudgetApp extends StatelessWidget {
  BudgetApp({super.key, required this.engine, AppServices? services})
    : services = services ?? AppServices.inMemory();

  final BudgetEngine engine;

  /// The device's key store, preferences, file dialog and lock check.
  /// Defaults to in-memory ones, for tests and previews.
  final AppServices services;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Budget',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    builder: (context, child) => AppServicesScope(
      services: services,
      child: AppLockGate(services: services, child: child!),
    ),
    home: engine.state.budget == null
        ? WelcomeScreen(engine: engine)
        : BudgetScreen(engine: engine),
  );
}
