import 'package:flutter/material.dart';

class ResponsiveAppBarTitle extends StatelessWidget {
  const ResponsiveAppBarTitle(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        text,
        maxLines: 1,
        style:
            style ??
            const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
      ),
    );
  }
}
