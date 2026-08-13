import 'package:flutter/material.dart';

import '../constants/colors.dart';

class AppFieldLabel extends StatelessWidget {
  const AppFieldLabel({
    super.key,
    required this.text,
    this.padding = const EdgeInsets.only(left: 4, bottom: 8),
  });

  final String text;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: padding,
      child: Text(
        text,
        style:
            theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.labelColor,
            ) ??
            const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.labelColor,
            ),
      ),
    );
  }
}
