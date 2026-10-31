import 'package:flutter/material.dart';

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
/// Today every flow gets the presentation it already had on a phone: a route,
/// or a sheet for the two that have always been sheets. The desktop shell
/// chooses a sheet above the breakpoint here, and no flow screen changes.
Future<T?> openFlow<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  FlowPresentation presentation = FlowPresentation.route,
  bool showDragHandle = false,
}) => switch (presentation) {
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
