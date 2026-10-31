import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'desktop.dart';
import 'theme.dart';

/// How a short flow opens.
enum FlowPresentation {
  /// A full-screen route, which is what a phone shows.
  route,

  /// A sheet over the current screen. Split and Revert conflict are sheets on
  /// a phone already; the rest become sheets on a desktop (ticket 61).
  sheet,
}

/// Opens one short flow through the one place that picks how it is presented,
/// so a flow screen is written once and never reads the layout itself.
///
/// A phone gets the presentation it already had: a route, or a sheet for the
/// two flows that have always been sheets. Above the desktop breakpoint every
/// short flow is a sheet hanging from the top of the current section
/// (ticket 63), so the sidebar and toolbar stay where they are.
Future<T?> openFlow<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  FlowPresentation presentation = FlowPresentation.route,
  bool showDragHandle = false,
}) {
  if (MediaQuery.sizeOf(context).width >= desktopBreakpoint) {
    return _openDesktopSheet(context, builder);
  }
  return switch (presentation) {
    FlowPresentation.route => Navigator.of(
      context,
    ).push<T>(MaterialPageRoute<T>(builder: builder)),
    FlowPresentation.sheet => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.card,
      showDragHandle: showDragHandle,
      // A sheet with a handle is rounded at the top, as the budget switcher is.
      shape: showDragHandle
          ? const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            )
          : null,
      builder: builder,
    ),
  };
}

/// The widest a desktop sheet gets; a narrow window shrinks it.
const _sheetWidth = 720.0;

/// A Mac sheet: attached to the top of the content area, as wide as the
/// reading column, with its bottom corners rounded. The route is modal, so
/// Esc and a click outside close it without saving anything.
Future<T?> _openDesktopSheet<T>(BuildContext context, WidgetBuilder builder) =>
    showDialog<T>(
      context: context,
      // The sheet belongs to the section under it, so it opens in the content
      // area rather than over the whole window.
      useRootNavigator: false,
      barrierColor: const Color(0x33000000),
      builder: (context) => _DesktopSheet(builder: builder),
    );

class _DesktopSheet extends StatefulWidget {
  const _DesktopSheet({required this.builder});

  final WidgetBuilder builder;

  @override
  State<_DesktopSheet> createState() => _DesktopSheetState();
}

class _DesktopSheetState extends State<_DesktopSheet> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// Esc closes the sheet, even while a field has focus, where the text
  /// editing shortcuts would otherwise swallow it. A sheet opened on top
  /// (a date picker, say) gets the key instead.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return false;
    }
    Navigator.of(context).maybePop();
    return true;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: constraints.maxWidth < _sheetWidth
              ? constraints.maxWidth
              : _sheetWidth,
          maxHeight: constraints.maxHeight,
        ),
        child: Material(
          key: const ValueKey('flow-sheet'),
          elevation: 16,
          color: Palette.background,
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(18),
          ),
          clipBehavior: Clip.antiAlias,
          child: widget.builder(context),
        ),
      ),
    ),
  );
}
