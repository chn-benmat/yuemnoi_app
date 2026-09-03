import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../domain/entities/chat_message.dart';

String _extractActualTextMessage(String raw) {
  final trimmed = raw.trim();
  if (trimmed.startsWith('↩ ตอบกลับ:') ||
      trimmed.startsWith('💬 ตอบกลับ') ||
      trimmed.startsWith('↪ ตอบกลับ')) {
    final newlineIdx = trimmed.indexOf('\n');
    if (newlineIdx != -1) {
      return trimmed.substring(newlineIdx + 1).trim();
    }
    final parts = trimmed.split('|');
    if (parts.length >= 2) {
      return parts.last.trim();
    }
    final colonIdx = trimmed.indexOf(':');
    if (colonIdx != -1) {
      return trimmed.substring(colonIdx + 1).trim();
    }
  }
  return trimmed;
}

class ChatMessageComposer extends StatelessWidget {
  const ChatMessageComposer({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onCamera,
    required this.onGallery,
    this.replyingMessage,
    this.editingMessage,
    this.onCancelReplyOrEdit,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final ChatMessage? replyingMessage;
  final ChatMessage? editingMessage;
  final VoidCallback? onCancelReplyOrEdit;

  @override
  Widget build(BuildContext context) {
    final isReplying = replyingMessage != null;
    final isEditing = editingMessage != null;

    return ColoredBox(
      color: const Color(0xFFF5F6F7),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isReplying || isEditing)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.primaryColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isEditing ? Icons.edit_rounded : Icons.reply_rounded,
                      size: 18,
                      color: AppColors.primaryColor,
                    ),
                    const SizedBox(width: 8),
                    if (isReplying &&
                        replyingMessage!.imageUrl != null &&
                        replyingMessage!.imageUrl!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: 34,
                            height: 34,
                            child: CachedNetworkImage(
                              imageUrl: replyingMessage!.imageUrl!,
                              fit: BoxFit.cover,
                              errorWidget: (_, _, _) =>
                                  const Icon(Icons.image, size: 20),
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEditing
                                ? 'กำลังแก้ไขข้อความ'
                                : (replyingMessage!.isMine
                                    ? 'ตอบกลับตัวเอง'
                                    : 'กำลังตอบกลับ'),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryColor,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            isEditing
                                ? _extractActualTextMessage(editingMessage!.message)
                                : (replyingMessage!.message.isNotEmpty &&
                                        replyingMessage!.message != '📷 ส่งรูปภาพ' &&
                                        replyingMessage!.message != '[รูปภาพ]'
                                    ? _extractActualTextMessage(replyingMessage!.message)
                                    : '📷 รูปภาพ'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: const Color(0xFF9CA3AF),
                      onPressed: onCancelReplyOrEdit,
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                // Camera Icon Button
                SizedBox.square(
                  dimension: 42,
                  child: IconButton.filled(
                    key: const ValueKey('camera-button'),
                    tooltip: 'ถ่ายภาพ',
                    onPressed: onCamera,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primaryColor,
                    ),
                    icon: const Icon(Icons.camera_alt_rounded, size: 22),
                  ),
                ),
                const SizedBox(width: 6),
                // Gallery Icon Button
                SizedBox.square(
                  dimension: 42,
                  child: IconButton.filled(
                    key: const ValueKey('gallery-button'),
                    tooltip: 'เลือกรูปภาพ',
                    onPressed: onGallery,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF4F5460),
                    ),
                    icon: const Icon(Icons.photo_library_rounded, size: 22),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: const ValueKey('chat-message-field'),
                    controller: controller,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    decoration: InputDecoration(
                      hintText: isEditing
                          ? 'แก้ไขข้อความ...'
                          : (isReplying ? 'ตอบกลับข้อความ...' : 'พิมพ์ข้อความ...'),
                      hintStyle: const TextStyle(
                        color: Color(0xFF7A8090),
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 11,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox.square(
                  dimension: 44,
                  child: IconButton.filled(
                    key: const ValueKey('send-message-button'),
                    tooltip: isEditing ? 'บันทึกแก้ไข' : 'ส่งข้อความ',
                    onPressed: onSend,
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 3,
                    ),
                    icon: Icon(
                      isEditing ? Icons.check_rounded : Icons.send_rounded,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
