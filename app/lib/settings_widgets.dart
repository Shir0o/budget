import 'package:flutter/material.dart';

import 'theme.dart';

/// Back arrow and title, as at the top of the canvas's Settings screens.
class BackHeader extends StatelessWidget {
  const BackHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 16, 16, 4),
    child: Row(
      spacing: 4,
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          color: Palette.ink,
          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
        ),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

/// The grey note with a padlock under a settings card.
class InfoNote extends StatelessWidget {
  const InfoNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFFE7E9E4),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.lock_outline, size: 20, color: Palette.inkSoft),
        ),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              color: Palette.inkSoft,
              height: 1.45,
            ),
          ),
        ),
      ],
    ),
  );
}

/// One line in a settings card: a label, then a value and a chevron when
/// [onTap] is set. Rows without [onTap] only display.
class SettingsRow {
  const SettingsRow({required this.label, this.value, this.onTap});

  final String label;
  final String? value;
  final VoidCallback? onTap;
}

/// A titled card of [SettingsRow]s. Settings lists these, so a later ticket
/// adds a row by adding it to the right section.
class SettingsSection {
  const SettingsSection({required this.title, required this.rows});

  final String title;
  final List<SettingsRow> rows;
}

class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.section});

  final SettingsSection section;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Palette.card,
      border: Border.all(color: Palette.cardBorder),
      borderRadius: BorderRadius.circular(16),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Text(
            section.title.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Palette.muted,
              letterSpacing: 0.72,
            ),
          ),
        ),
        for (var i = 0; i < section.rows.length; i++)
          _RowTile(row: section.rows[i], first: i == 0),
      ],
    ),
  );
}

class _RowTile extends StatelessWidget {
  const _RowTile({required this.row, required this.first});

  final SettingsRow row;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final value = row.value;
    return Semantics(
      button: row.onTap != null,
      child: InkWell(
        onTap: row.onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: first
                ? null
                : const Border(top: BorderSide(color: Palette.divider)),
          ),
          child: Row(
            spacing: 12,
            children: [
              Text(row.label, style: const TextStyle(fontSize: 15)),
              const Spacer(),
              if (value != null)
                Flexible(
                  child: Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: Palette.muted),
                  ),
                ),
              if (row.onTap != null)
                const Icon(Icons.chevron_right, size: 18, color: Palette.muted),
            ],
          ),
        ),
      ),
    );
  }
}
