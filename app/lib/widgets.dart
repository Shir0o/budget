import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import 'screens/accounts_screen.dart';
import 'screens/budget_screen.dart';
import 'screens/history_screen.dart';
import 'screens/review_screen.dart';
import 'theme.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// `Nov 1, 2026`
String formatDate(CivilDate date) =>
    '${_months[date.month - 1]} ${date.day}, ${date.year}';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// `Nov 14`
String formatDay(CivilDate date) => '${_months[date.month - 1]} ${date.day}';

/// `4:12 PM`
String formatTime(DateTime time) {
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${time.hour < 12 ? 'AM' : 'PM'}';
}

/// `Nov 2026`
String formatMonth(CalendarMonth month) =>
    '${_months[month.month - 1]} ${month.year}';

/// `November`
String monthName(CalendarMonth month) => _monthNames[month.month - 1];

CivilDate today() => CivilDate.fromDateTime(DateTime.now());

CalendarMonth thisMonth() => CalendarMonth.of(today());

/// A Category's Available as a pill: teal above zero, grey at zero and
/// orange when overspent.
class AvailablePill extends StatelessWidget {
  const AvailablePill(this.amount, {super.key});

  final Money amount;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = amount.isNegative
        ? (Palette.problemPill, Palette.problemText)
        : amount.isPositive
        ? (Palette.positivePill, Palette.positiveText)
        : (Palette.zeroPill, Palette.inkSoft);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        amount.format(),
        style: amountStyle(
          fontSize: 13,
          fontWeight: amount.isNegative ? FontWeight.w600 : FontWeight.w500,
          color: foreground,
        ),
      ),
    );
  }
}

/// The bottom navigation's tabs.
enum MainTab { budget, review, accounts, history }

/// The bottom navigation. Review shows a badge with the Unreviewed count.
class MainNav extends StatelessWidget {
  const MainNav({super.key, required this.engine, required this.current});

  final BudgetEngine engine;
  final MainTab current;

  void _go(BuildContext context, MainTab tab) {
    if (tab == current) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => switch (tab) {
          MainTab.budget => BudgetScreen(engine: engine),
          MainTab.review => ReviewScreen(engine: engine),
          MainTab.accounts => AccountsScreen(engine: engine),
          MainTab.history => HistoryScreen(engine: engine),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unreviewed = engine.state.reviewQueue.length;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Palette.card,
        border: Border(top: BorderSide(color: Palette.cardBorder)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 80,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                for (final (tab, label, icon, badge) in [
                  (MainTab.budget, 'Budget', Icons.table_chart_outlined, 0),
                  (MainTab.review, 'Review', Icons.check, unreviewed),
                  (
                    MainTab.accounts,
                    'Accounts',
                    Icons.account_balance_outlined,
                    0,
                  ),
                  (MainTab.history, 'History', Icons.schedule, 0),
                ])
                  Expanded(
                    child: _NavTab(
                      label: label,
                      icon: icon,
                      badge: badge,
                      selected: tab == current,
                      onTap: () => _go(context, tab),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.label,
    required this.icon,
    required this.badge,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;

  /// A count shown on the icon, hidden at 0.
  final int badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    label: badge > 0 ? '$label, $badge to review' : label,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 4,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 56,
                height: 30,
                decoration: BoxDecoration(
                  color: selected ? Palette.positivePill : null,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: selected ? Palette.positiveText : Palette.muted,
                ),
              ),
              if (badge > 0)
                Positioned(
                  right: 4,
                  top: -4,
                  child: Container(
                    key: ValueKey('$label-badge'),
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
                ),
            ],
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? Palette.ink : Palette.muted,
            ),
          ),
        ],
      ),
    ),
  );
}

/// A white card with the canvas border.
class CardBox extends StatelessWidget {
  const CardBox({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding ?? const EdgeInsets.fromLTRB(16, 14, 16, 14),
    decoration: BoxDecoration(
      color: Palette.card,
      border: Border.all(color: Palette.cardBorder),
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: Palette.inkSoft,
    ),
  );
}

class Hint extends StatelessWidget {
  const Hint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 12, color: Palette.muted, height: 1.4),
  );
}

/// A label above its field, 6 px apart.
class LabeledField extends StatelessWidget {
  const LabeledField({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    spacing: 6,
    children: [FieldLabel(label), child],
  );
}

/// A choice chip in the canvas style: dark when selected. The tap target is
/// 44 px tall even though the pill is 36.
class SelectChip extends StatelessWidget {
  const SelectChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Center(
          widthFactor: 1,
          child: Container(
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: selected ? Palette.ink : Palette.card,
              border: Border.all(
                color: selected ? Palette.ink : Palette.fieldBorder,
              ),
              borderRadius: BorderRadius.circular(999),
            ),
            // Sized to the label, so a chip in a Wrap doesn't fill the row.
            child: Align(
              widthFactor: 1,
              heightFactor: 1,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                  color: selected ? Palette.background : Palette.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Close, title and a dark Save pill, as on the canvas's form screens.
class FormHeader extends StatelessWidget {
  const FormHeader({
    super.key,
    required this.title,
    required this.onClose,
    required this.onSave,
    this.actions = const [],
  });

  final String title;
  final VoidCallback onClose;

  /// Null disables Save.
  final VoidCallback? onSave;

  /// Shown before Save.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 16, 16, 4),
    child: Row(
      spacing: 4,
      children: [
        IconButton(
          onPressed: onClose,
          tooltip: 'Close',
          icon: const Icon(Icons.close, size: 22, color: Palette.ink),
          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
        ),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
        ...actions,
        FilledButton(
          onPressed: onSave,
          style: FilledButton.styleFrom(
            backgroundColor: Palette.ink,
            foregroundColor: Palette.background,
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 18),
          ),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

/// A date shown like a text field; tapping opens the date picker.
class DateField extends StatelessWidget {
  const DateField({super.key, required this.value, required this.onChanged});

  final CivilDate value;
  final ValueChanged<CivilDate> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(10),
    onTap: () async {
      final picked = await pickDate(context, value);
      if (picked != null) onChanged(picked);
    },
    child: InputDecorator(
      decoration: const InputDecoration(),
      child: Text(formatDate(value), style: const TextStyle(fontSize: 15)),
    ),
  );
}

/// Opens the date picker at [value]. Null when dismissed.
Future<CivilDate?> pickDate(BuildContext context, CivilDate value) async {
  final picked = await showDatePicker(
    context: context,
    initialDate: DateTime(value.year, value.month, value.day),
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );
  return picked == null ? null : CivilDate.fromDateTime(picked);
}

/// The canvas's warning for payees and memos (ticket 09).
const accountNumberMessage = 'Don’t store account numbers here.';

/// `+1,500.00` or `−12.50`, as in the register.
String formatSigned(Money amount) =>
    '${amount.isPositive ? '+' : ''}${amount.format()}';

/// The canvas's segmented control. [selected] may be null when nothing is
/// chosen yet.
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<(T, String)> options;
  final T? selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: Palette.zeroPill,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      spacing: 3,
      children: [
        for (final (value, label) in options)
          Expanded(
            child: Semantics(
              button: true,
              selected: value == selected,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(value),
                child: Container(
                  height: 40,
                  alignment: Alignment.center,
                  decoration: value == selected
                      ? BoxDecoration(
                          color: Palette.card,
                          borderRadius: BorderRadius.circular(9),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x1F17191B),
                              offset: Offset(0, 1),
                              blurRadius: 2,
                            ),
                          ],
                        )
                      : null,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: value == selected
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: value == selected ? Palette.ink : Palette.inkSoft,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
