import 'package:budget_core/budget_core.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// `Nov 1, 2026`
String formatDate(CivilDate date) =>
    '${_months[date.month - 1]} ${date.day}, ${date.year}';

/// `Nov 2026`
String formatMonth(CivilDate date) => '${_months[date.month - 1]} ${date.year}';

CivilDate today() => CivilDate.fromDateTime(DateTime.now());

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
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? Palette.ink : Palette.card,
              border: Border.all(
                color: selected ? Palette.ink : Palette.fieldBorder,
              ),
              borderRadius: BorderRadius.circular(999),
            ),
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
  );
}

/// Close, title and a dark Save pill, as on the canvas's form screens.
class FormHeader extends StatelessWidget {
  const FormHeader({
    super.key,
    required this.title,
    required this.onClose,
    required this.onSave,
  });

  final String title;
  final VoidCallback onClose;
  final VoidCallback onSave;

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
      final picked = await showDatePicker(
        context: context,
        initialDate: DateTime(value.year, value.month, value.day),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (picked != null) onChanged(CivilDate.fromDateTime(picked));
    },
    child: InputDecorator(
      decoration: const InputDecoration(),
      child: Text(formatDate(value), style: const TextStyle(fontSize: 15)),
    ),
  );
}
