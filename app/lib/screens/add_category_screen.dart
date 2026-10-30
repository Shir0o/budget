import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import '../widgets.dart';

/// Adds a Category to an existing group or to a new one. The canvas has no
/// board for this; it follows the Add account form.
class AddCategoryScreen extends StatefulWidget {
  const AddCategoryScreen({super.key, required this.engine});

  final BudgetEngine engine;

  @override
  State<AddCategoryScreen> createState() => _AddCategoryScreenState();
}

class _AddCategoryScreenState extends State<AddCategoryScreen> {
  /// Null means a new group.
  late String? _groupId = widget.engine.state.categoryGroups.firstOrNull?.id;
  final _groupName = TextEditingController();
  final _name = TextEditingController();
  String? _groupNameError;
  String? _nameError;

  @override
  void dispose() {
    _groupName.dispose();
    _name.dispose();
    super.dispose();
  }

  void _save() {
    setState(() {
      _groupNameError = _groupId == null && _groupName.text.trim().isEmpty
          ? 'Name the group'
          : null;
      _nameError = _name.text.trim().isEmpty ? 'Name the Category' : null;
    });
    if (_groupNameError != null || _nameError != null) return;

    final engine = widget.engine;
    var groupId = _groupId;
    if (groupId == null) {
      final created = engine.execute(
        CreateCategoryGroup(name: _groupName.text),
      );
      if (created is! Accepted) return;
      groupId = created.events.single.payload['categoryGroupId'] as String;
    }
    final result = engine.execute(
      CreateCategory(groupId: groupId, name: _name.text),
    );
    if (result is Accepted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final groups = widget.engine.state.categoryGroups;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormHeader(
              title: 'Add category',
              onClose: () => Navigator.of(context).pop(),
              onSave: _save,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                children: [
                  CardBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 10,
                      children: [
                        const FieldLabel('Group'),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final group in groups)
                              SelectChip(
                                label: group.name,
                                selected: group.id == _groupId,
                                onTap: () =>
                                    setState(() => _groupId = group.id),
                              ),
                            SelectChip(
                              label: 'New group',
                              selected: _groupId == null,
                              onTap: () => setState(() => _groupId = null),
                            ),
                          ],
                        ),
                        if (_groupId == null)
                          TextField(
                            key: const ValueKey('group-name'),
                            controller: _groupName,
                            textCapitalization: TextCapitalization.words,
                            style: const TextStyle(fontSize: 15),
                            decoration: InputDecoration(
                              hintText: 'Group name, like Bills',
                              errorText: _groupNameError,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  CardBox(
                    child: LabeledField(
                      label: 'Name',
                      child: TextField(
                        key: const ValueKey('category-name'),
                        controller: _name,
                        textCapitalization: TextCapitalization.sentences,
                        style: const TextStyle(fontSize: 15),
                        decoration: InputDecoration(errorText: _nameError),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Hint(
                      'A Category starts at 0.00. Its money rolls over from '
                      'month to month.',
                    ),
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
