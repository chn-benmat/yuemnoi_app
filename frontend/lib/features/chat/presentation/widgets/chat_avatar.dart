import 'package:flutter/material.dart';

class ChatAvatar extends StatelessWidget {
  const ChatAvatar({
    super.key,
    required this.asset,
    required this.size,
    this.isOnline = false,
  });

  final String asset;
  final double size;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE0B9FF)),
              ),
              child: ClipOval(child: Image.asset(asset, fit: BoxFit.cover)),
            ),
          ),
          if (isOnline)
            Positioned(
              right: -1,
              bottom: 2,
              child: Container(
                width: size * 0.24,
                height: size * 0.24,
                decoration: BoxDecoration(
                  color: const Color(0xFF20D31A),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
