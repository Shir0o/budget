import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import 'screens/budget_screen.dart';
import 'screens/welcome_screen.dart';
import 'theme.dart';

class BudgetApp extends StatelessWidget {
  const BudgetApp({super.key, required this.engine});

  final BudgetEngine engine;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Budget',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    home: engine.state.budget == null
        ? WelcomeScreen(engine: engine)
        : BudgetScreen(engine: engine),
  );
}
