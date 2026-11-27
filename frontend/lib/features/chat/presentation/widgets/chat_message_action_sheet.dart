import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/services/media_download_service.dart';
import '../../../booking/domain/entities/booking_request_model.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/item_inquiry_data.dart';
import 'chat_toast.dart';

String _extractActualTextMessage(String raw) {
  var text = raw.trim();
  if (text.contains(ItemInquiryData.metaStartTag)) {
    final idx = text.indexOf(ItemInquiryData.metaStartTag);
    text = text.substring(0, idx).trim();
  }
  if (text.contains(BookingRequestData.metaStartTag)) {
    final idx = text.indexOf(BookingRequestData.metaStartTag);
    text = text.substring(0, idx).trim();
  }
  if (text.contains(BookingRequestData.customerRequestMetaTag)) {
    final idx = text.indexOf(BookingRequestData.customerRequestMetaTag);
    text = text.substring(0, idx).trim();
  }
  if (text.startsWith('↩ ตอบกลับ:') ||
      text.startsWith('💬 ตอบกลับ') ||
      text.startsWith('↪ ตอบกลับ')) {
    final newlineIdx = text.indexOf('\n');
    if (newlineIdx != -1) {
      return text.substring(newlineIdx + 1).trim();
    }
    final parts = text.split('|');
    if (parts.length >= 2) {
      return parts.last.trim();
    }
    final colonIdx = text.indexOf(':');
    if (colonIdx != -1) {
      return text.substring(colonIdx + 1).trim();
    }
  }
  return text;
}

/// เมนูกดค้างที่ข้อความ (Message Action Sheet) ตามสไตล์ Messenger
class ChatMessageActionSheet extends StatelessWidget {
  const ChatMessageActionSheet({
    super.key,
    required this.message,
    this.imageUrls = const [],
    required this.onReply,
    required this.onCopy,
    this.onEdit,
    required this.onDelete,
    this.onSaveImage,
  });

  final ChatMessage message;
  final List<String> imageUrls;
  final VoidCallback? onReply;
  final VoidCallback onCopy;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onSaveImage;

  static Future<void> show(
    BuildContext context, {
    required ChatMessage message,
    List<String> imageUrls = const [],
    required VoidCallback? onReply,
    VoidCallback? onEdit,
    required VoidCallback onDelete,
    VoidCallback? onSaveImage,
  }) {
    final effectiveImages = imageUrls.isNotEmpty
        ? imageUrls
        : (message.imageUrl != null && message.imageUrl!.isNotEmpty
              ? [message.imageUrl!]
              : <String>[]);

    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (modalContext) => ChatMessageActionSheet(
        message: message,
        imageUrls: effectiveImages,
        onReply: onReply == null
            ? null
            : () {
                Navigator.of(modalContext).pop();
                onReply();
              },
        onCopy: () {
          Navigator.of(modalContext).pop();
          final textToCopy = _extractActualTextMessage(message.message);
          if (textToCopy.isNotEmpty &&
              textToCopy != '📷 ส่งรูปภาพ' &&
              textToCopy != '[รูปภาพ]') {
            Clipboard.setData(ClipboardData(text: textToCopy));
            ChatToast.show(context, message: 'คัดลอกแล้ว');
          }
        },
        onEdit: onEdit != null
            ? () {
                Navigator.of(modalContext).pop();
                onEdit();
              }
            : null,
        onDelete: () {
          Navigator.of(modalContext).pop();
          _confirmDelete(context, onDelete);
        },
        onSaveImage: () async {
          Navigator.of(modalContext).pop();
          if (onSaveImage != null) {
            onSaveImage();
            return;
          }
          if (effectiveImages.isNotEmpty) {
            final count = await MediaDownloadService.instance
                .saveMultipleImagesFromUrls(effectiveImages);
            if (context.mounted) {
              ChatToast.show(
                context,
                message: count > 1
                    ? 'บันทึก $count รูปภาพแล้ว'
                    : 'บันทึกรูปภาพแล้ว',
              );
            }
          }
        },
      ),
    );
  }

  static void _confirmDelete(BuildContext context, VoidCallback onConfirm) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'ยกเลิกการส่งข้อความนี้หรือไม่?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'ข้อความนี้จะถูกลบออกจากห้องแชทสำหรับทุกคน',
          style: TextStyle(fontSize: 14, color: Color(0xFF4A4D52)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(
              'ยกเลิก',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onConfirm();
            },
            child: const Text('ลบสำหรับทุกคน'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveImages = imageUrls.isNotEmpty
        ? imageUrls
        : (message.imageUrl != null && message.imageUrl!.isNotEmpty
              ? [message.imageUrl!]
              : <String>[]);
    final hasImages = effectiveImages.isNotEmpty;

    final actualText = _extractActualTextMessage(message.message);
    final isTextMessage =
        actualText.isNotEmpty &&
        actualText != '📷 ส่งรูปภาพ' &&
        actualText != '[รูปภาพ]';

    final isSpecialCard =
        ItemInquiryData.isInquiry(message.message) ||
        BookingRequestData.isBookingRequest(message.message);
    final canEdit =
        message.isMine && isTextMessage && !isSpecialCard && onEdit != null;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      decoration: BoxDecoration(
        color: const Color(0xFF26262A),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            if (onReply != null)
              _ActionButton(
                icon: Icons.reply_rounded,
                label: 'ตอบกลับ',
                color: Colors.white,
                onTap: onReply!,
              ),
            if (hasImages)
              _ActionButton(
                icon: Icons.download_rounded,
                label: 'บันทึกภาพ',
                color: Colors.white,
                onTap: onSaveImage ?? () {},
              ),
            if (isTextMessage)
              _ActionButton(
                icon: Icons.content_copy_rounded,
                label: 'คัดลอก',
                color: Colors.white,
                onTap: onCopy,
              ),
            if (canEdit)
              _ActionButton(
                icon: Icons.edit_rounded,
                label: 'แก้ไข',
                color: Colors.white,
                onTap: onEdit!,
              ),
            if (!message.message.contains(
              BookingRequestData.customerRequestMetaTag,
            ))
              _ActionButton(
                icon: Icons.delete_outline_rounded,
                label: 'ลบ',
                color: const Color(0xFFF43F5E),
                onTap: onDelete,
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
