import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';

/// Picks a Category or Ready to Assign (canvas: CategoryPicker). Returns a
/// Category id, [readyToAssignCategory], or null when dismissed.
Future<String?> showCategoryPicker(
  BuildContext context, {
  required BudgetState state,
  required CalendarMonth month,
  required String title,
  String readyToAssignLabel = 'Ready to Assign',
  String? excluding,
  List<String> recent = const [],
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Palette.card,
  builder: (_) => _CategoryPicker(
    state: state,
    month: month,
    title: title,
    readyToAssignLabel: readyToAssignLabel,
    excluding: excluding,
    recent: recent,
  ),
);

/// Searchable: Ready to Assign, then [recent] Categories, then every other
/// active Category by group, each with the month's Available.
class _CategoryPicker extends StatefulWidget {
  const _CategoryPicker({
    required this.state,
    required this.month,
    required this.title,
    required this.readyToAssignLabel,
    required this.excluding,
    required this.recent,
  });

  final BudgetState state;
  final CalendarMonth month;
  final String title;
  final String readyToAssignLabel;
  final String? excluding;
  final List<String> recent;

  @override
  State<_CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends State<_CategoryPicker> {
  var _query = '';

  bool _matches(String name) =>
      name.toLowerCase().contains(_query.trim().toLowerCase());

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final month = widget.month;
    final searching = _query.trim().isNotEmpty;
    bool shown(Category c) =>
        !c.archived && c.id != widget.excluding && _matches(c.name);

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.72,
          color: Palette.muted,
        ),
      ),
    );

    Widget option(
      String id,
      String name,
      Money amount, {
      bool primary = false,
    }) => InkWell(
      key: ValueKey('pick-$id'),
      onTap: () => Navigator.of(context).pop(id),
      child: Container(
        constraints: const BoxConstraints(minHeight: 46),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Palette.divider)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 15,
                  color: primary ? Palette.teal : Palette.ink,
                  fontWeight: primary ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ),
            Text(
              amount.format(),
              style: amountStyle(fontSize: 13, color: Palette.muted),
            ),
          ],
        ),
      ),
    );

    Widget categoryOption(Category c) =>
        option(c.id, c.name, state.available(c.id, month));

    final recent = searching
        ? const <Category>[]
        : [
            for (final id in widget.recent)
              if (state.category(id) case final c? when shown(c)) c,
          ];

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('category-search'),
              onChanged: (value) => setState(() => _query = value),
              style: const TextStyle(fontSize: 15),
              decoration: const InputDecoration(
                hintText: 'Search categories',
                prefixIcon: Icon(Icons.search, size: 20),
              ),
            ),
            const SizedBox(height: 6),
            if (_matches(widget.readyToAssignLabel))
              option(
                readyToAssignCategory,
                widget.readyToAssignLabel,
                state.readyToAssign(thisMonth()),
                primary: true,
              ),
            if (recent.isNotEmpty) ...[
              heading('Recent'),
              for (final c in recent) categoryOption(c),
            ],
            for (final group in state.categoryGroups)
              for (final (i, c)
                  in state.categories
                      .where(
                        (c) =>
                            c.groupId == group.id &&
                            shown(c) &&
                            !recent.contains(c),
                      )
                      .indexed) ...[
                if (i == 0) heading(group.name),
                categoryOption(c),
              ],
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Hint('Numbers are ${monthName(month)} Available.'),
            ),
          ],
        ),
      ),
    );
  }
}
