import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class ChatAvatar extends StatelessWidget {
  const ChatAvatar({
    super.key,
    required this.asset,
    required this.size,
    this.isOnline = false,
    this.showStatus = true,
    this.showBorder = false,
  });

  final String asset;
  final double size;
  final bool isOnline;
  final bool showStatus;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    final isNetwork = asset.startsWith('http://') || asset.startsWith('https://');
    final Widget imageWidget = isNetwork
        ? CachedNetworkImage(
            imageUrl: asset,
            fit: BoxFit.cover,
            placeholder: (_, _) => const ColoredBox(
              color: Color(0xFFF0F1F2),
              child: Center(
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            errorWidget: (_, _, _) =>
                Image.asset('assets/images/user.png', fit: BoxFit.cover),
          )
        : Image.asset(
            asset.isEmpty ? 'assets/images/user.png' : asset,
            fit: BoxFit.cover,
          );

    final dotSize = (size * 0.24).clamp(10.0, 20.0);

    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: showBorder
                ? Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFE0B9FF)),
                    ),
                    child: ClipOval(child: imageWidget),
                  )
                : ClipOval(child: imageWidget),
          ),
          // จุดสถานะออนไลน์ (เขียว) หรือ ออฟไลน์ (เทา)
          if (showStatus)
            Positioned(
              right: -1,
              bottom: 2,
              child: Container(
                key: ValueKey(isOnline ? 'avatar-status-online' : 'avatar-status-offline'),
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  color: isOnline ? const Color(0xFF10B981) : const Color(0xFF9CA3AF),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
