import 'package:flutter/material.dart';

class MapControlButton extends StatelessWidget {
  const MapControlButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.backgroundColor = Colors.white,
    this.color = const Color(0xFF334155),
    this.loading = false,
    this.circular = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color color;
  final bool loading;
  final bool circular;

  @override
  Widget build(BuildContext context) => Material(
    color: backgroundColor,
    elevation: 4,
    shadowColor: Colors.black26,
    borderRadius: BorderRadius.circular(circular ? 24 : 13),
    clipBehavior: Clip.antiAlias,
    child: SizedBox.square(
      dimension: 42,
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: tooltip,
        onPressed: loading ? null : onPressed,
        icon: loading
            ? SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(color: color, strokeWidth: 2),
              )
            : Icon(icon, size: 22, color: color),
      ),
    ),
  );
}
