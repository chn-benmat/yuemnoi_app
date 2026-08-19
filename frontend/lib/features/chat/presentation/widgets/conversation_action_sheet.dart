import 'package:flutter/material.dart';

import '../../../../core/services/chat_pin_service.dart';
import '../../domain/entities/chat_conversation.dart';

/// เมนูกดค้างที่รายการแชท (Conversation Long Press Action Sheet) ตามสไตล์ Messenger
class ConversationActionSheet extends StatelessWidget {
  const ConversationActionSheet({
    super.key,
    required this.conversation,
    required this.isPinned,
    required this.onTogglePin,
    required this.onDelete,
  });

  final ChatConversation conversation;
  final bool isPinned;
  final VoidCallback onTogglePin;
  final VoidCallback onDelete;

  static Future<void> show(
    BuildContext context, {
    required ChatConversation conversation,
    required VoidCallback onTogglePin,
    required VoidCallback onDelete,
  }) {
    final isPinned = ChatPinService.instance.isPinned(conversation.id);

    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (modalContext) => ConversationActionSheet(
        conversation: conversation,
        isPinned: isPinned,
        onTogglePin: () {
          Navigator.of(modalContext).pop();
          onTogglePin();
        },
        onDelete: () {
          Navigator.of(modalContext).pop();
          _confirmDelete(context, onDelete);
        },
      ),
    );
  }

  static void _confirmDelete(BuildContext context, VoidCallback onConfirm) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'ลบการสนทนานี้หรือไม่?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'ข้อความทั้งหมดในการสนทนานี้จะถูกลบถาวร และไม่สามารถกู้คืนได้',
          style: TextStyle(fontSize: 14, color: Color(0xFF4A4D52)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('ยกเลิก', style: TextStyle(color: Color(0xFF6B7280))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onConfirm();
            },
            child: const Text('ลบแชท'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF242526),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.only(top: 10, bottom: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white30,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),

            _ActionTile(
              icon: Icons.push_pin_rounded,
              title: isPinned ? 'ยกเลิกการปักหมุด' : 'ปักหมุด',
              onTap: onTogglePin,
            ),
            const Divider(height: 1, color: Color(0xFF3A3B3C)),
            _ActionTile(
              icon: Icons.delete_outline_rounded,
              title: 'ลบ',
              isDestructive: true,
              onTap: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.isDestructive = false,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? const Color(0xFFEF4444) : Colors.white;

    return Material(
      color: Colors.transparent,
      child: ListTile(
        leading: Icon(icon, color: color, size: 24),
        title: Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: isDestructive ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}
