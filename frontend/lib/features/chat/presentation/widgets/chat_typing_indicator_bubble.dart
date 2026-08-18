import 'package:flutter/material.dart';
import 'chat_avatar.dart';

class ChatTypingIndicatorBubble extends StatefulWidget {
  const ChatTypingIndicatorBubble({super.key, this.avatarAsset});

  final String? avatarAsset;

  @override
  State<ChatTypingIndicatorBubble> createState() => _ChatTypingIndicatorBubbleState();
}

class _ChatTypingIndicatorBubbleState extends State<ChatTypingIndicatorBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('chat-typing-indicator-bubble'),
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      color: Colors.transparent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 2),
            child: ChatAvatar(
              asset: widget.avatarAsset ?? 'assets/images/user1.png',
              size: 28,
              showStatus: false,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFE4E6EB),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(18),
              ),
            ),
            child: AnimatedBuilder(
              animation: _animController,
              builder: (context, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (index) {
                    final delay = index * 0.25;
                    final progress = (_animController.value - delay) % 1.0;
                    final offset = (progress >= 0 && progress <= 0.5)
                        ? -4.0 * (1 - (progress - 0.25).abs() / 0.25)
                        : 0.0;
                    return Container(
                      margin: EdgeInsets.only(right: index < 2 ? 4 : 0),
                      transform: Matrix4.translationValues(0, offset, 0),
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF65676B),
                        shape: BoxShape.circle,
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
