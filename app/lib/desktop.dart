import 'package:flutter/material.dart';

import 'theme.dart';

/// Above this width the app is on a desktop, not a phone.
const desktopBreakpoint = 900.0;

/// The reading width on a desktop. The same screens run inside it rather
/// than stretching every row across a wide window.
const desktopContentWidth = 720.0;

/// Frames the app's screens on a desktop: above [desktopBreakpoint] they sit
/// in one centred column with the canvas's vertical frame lines. Below it,
/// nothing changes.
class DesktopFrame extends StatelessWidget {
  const DesktopFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth < desktopBreakpoint
        ? child
        : ColoredBox(
            color: Palette.background,
            child: Center(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: Palette.background,
                  border: Border.symmetric(
                    vertical: BorderSide(color: Palette.cardBorder),
                  ),
                ),
                child: SizedBox(width: desktopContentWidth, child: child),
              ),
            ),
          ),
  );
}
