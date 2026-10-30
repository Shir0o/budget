import 'package:budget_core/budget_core.dart';
import 'package:budget_migration/budget_migration.dart';

/// The Actual import wizard's state while the person moves between its
/// screens. Nothing is written until Map tags commits, so backing up a step
/// keeps every decision.
final class ImportDraft {
  ImportDraft({required this.export, required this.tags, required this.today});

  final ActualExport export;

  /// The Business Tag decisions, in the order Map tags lists them.
  final List<TagMapping> tags;
  final CivilDate today;

  ImportPlan plan() =>
      buildImportPlan(export: export, tagMappings: tags, today: today);
}
