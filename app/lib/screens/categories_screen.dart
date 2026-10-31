import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../flows.dart';
import '../theme.dart';
import '../widgets.dart';
import 'add_category_screen.dart';
import 'category_screen.dart';

/// Categories & priority (canvas: Categories): drag to set the order
/// automation fills Targets in. Each row shows the Category's Automation
/// Mode, which is set on the Category screen.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key, required this.engine});

  final BudgetEngine engine;

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  Future<void> _open(Widget screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));
    setState(() {});
  }

  /// Opens Add category, one of the short flows (ticket 60).
  Future<void> _openFlow(Widget screen) async {
    await openFlow<void>(context, builder: (_) => screen);
    if (mounted) setState(() {});
  }

  void _reorder(List<Category> categories, int from, int to) {
    final ids = [for (final c in categories) c.id];
    final moved = ids.removeAt(from);
    ids.insert(to, moved);
    widget.engine.execute(SetPriority(categoryIds: ids));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.engine.state;
    final categories = state.priority;
    final archived = state.categories.where((c) => c.archived).length;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 16, 4),
              child: Row(
                spacing: 4,
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Back',
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
                    icon: const Icon(Icons.chevron_left, color: Palette.ink),
                  ),
                  const Expanded(
                    child: Text(
                      'Categories & priority',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () =>
                        _openFlow(AddCategoryScreen(engine: widget.engine)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      textStyle: const TextStyle(
                        fontFamily: sansFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    child: const Text('Add'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                children: [
                  const Text(
                    'Drag to set the order automation fills Targets in. The '
                    'mode is set on each Category.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Palette.inkSoft,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (categories.isNotEmpty)
                    CardBox(
                      padding: EdgeInsets.zero,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: ReorderableListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          buildDefaultDragHandles: false,
                          itemCount: categories.length,
                          onReorderItem: (from, to) =>
                              _reorder(categories, from, to),
                          itemBuilder: (context, i) => _PriorityRow(
                            key: ValueKey(categories[i].id),
                            index: i,
                            name: categories[i].name,
                            mode: state.automationMode(categories[i].id),
                            onTap: () => _open(
                              CategoryScreen(
                                engine: widget.engine,
                                categoryId: categories[i].id,
                                month: thisMonth(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    const Hint('No Categories yet.'),
                  const SizedBox(height: 12),
                  CardBox(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _InfoRow(
                          label: 'Category groups',
                          value: state.categoryGroups
                              .map((g) => g.name)
                              .join(', '),
                        ),
                        _InfoRow(
                          label: 'Archived',
                          value: '$archived',
                          divided: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Hint(
                    'A Category can only be archived once its Available is '
                    '0.00.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriorityRow extends StatelessWidget {
  const _PriorityRow({
    super.key,
    required this.index,
    required this.name,
    required this.mode,
    required this.onTap,
  });

  final int index;
  final String name;
  final AutomationMode mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Palette.card,
    child: InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.only(left: 8, right: 16),
        decoration: BoxDecoration(
          border: index == 0
              ? null
              : const Border(top: BorderSide(color: Palette.divider)),
        ),
        child: Row(
          spacing: 10,
          children: [
            ReorderableDragStartListener(
              index: index,
              child: Semantics(
                label: 'Reorder $name',
                button: true,
                child: const SizedBox(
                  width: 32,
                  height: 44,
                  child: Icon(
                    Icons.drag_indicator,
                    size: 18,
                    color: Color(0xFF8C928A),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 18,
              child: Text(
                '${index + 1}',
                style: amountStyle(fontSize: 12, color: Palette.muted),
              ),
            ),
            Expanded(child: Text(name, style: const TextStyle(fontSize: 15))),
            Text(switch (mode) {
              AutomationMode.off => 'Off',
              AutomationMode.suggest => 'Suggest',
              AutomationMode.auto => 'Auto',
            }, style: const TextStyle(fontSize: 13, color: Palette.muted)),
          ],
        ),
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.divided = false,
  });

  final String label;
  final String value;
  final bool divided;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 52),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: BoxDecoration(
      border: divided
          ? const Border(top: BorderSide(color: Palette.divider))
          : null,
    ),
    child: Row(
      spacing: 12,
      children: [
        Text(label, style: const TextStyle(fontSize: 15)),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: Palette.muted),
          ),
        ),
      ],
    ),
  );
}
