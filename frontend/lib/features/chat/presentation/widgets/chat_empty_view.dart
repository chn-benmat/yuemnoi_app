import 'package:flutter/material.dart';
import '../../domain/entities/chat_conversation.dart';
import 'chat_avatar.dart';

class ChatEmptyView extends StatelessWidget {
  const ChatEmptyView({super.key, required this.conversation});

  final ChatConversation conversation;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ChatAvatar(
              asset: conversation.avatarAsset,
              size: 72,
              isOnline: conversation.isOnline,
            ),
            const SizedBox(height: 16),
            Text(
              conversation.name,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2C2D30),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              conversation.isOtherUserUnavailable
                  ? 'ยังไม่มีประวัติการสนทนา'
                  : conversation.itemName != null
                  ? 'เริ่มพูดคุยเกี่ยวกับ "${conversation.itemName}"'
                  : 'ยังไม่มีประวัติการสนทนา เริ่มพิมพ์ข้อความได้เลย',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Color(0xFF7A8090)),
            ),
          ],
        ),
      ),
    );
  }
}
