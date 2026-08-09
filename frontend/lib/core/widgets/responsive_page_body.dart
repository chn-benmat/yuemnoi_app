import 'package:flutter/material.dart';

/// A scrollable, width-constrained page body that adapts its gutters to the
/// available phone viewport.
class ResponsivePageBody extends StatelessWidget {
  const ResponsivePageBody({
    super.key,
    required this.child,
    this.maxContentWidth = 480,
    this.compactBreakpoint = 360,
    this.horizontalPadding = 24,
    this.compactHorizontalPadding = 16,
    this.verticalPadding = 32,
    this.compactVerticalPadding = 16,
  });

  final Widget child;
  final double maxContentWidth;
  final double compactBreakpoint;
  final double horizontalPadding;
  final double compactHorizontalPadding;
  final double verticalPadding;
  final double compactVerticalPadding;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompactWidth = constraints.maxWidth < compactBreakpoint;
          final isCompactHeight = constraints.maxHeight < 600;
          final horizontal = isCompactWidth
              ? compactHorizontalPadding
              : horizontalPadding;
          final vertical = isCompactHeight
              ? compactVerticalPadding
              : verticalPadding;

          return SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.symmetric(
              horizontal: horizontal,
              vertical: vertical,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContentWidth),
                child: SizedBox(width: double.infinity, child: child),
              ),
            ),
          );
        },
      ),
    );
  }
}
