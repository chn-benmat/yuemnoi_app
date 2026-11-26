import 'package:intl/intl.dart';

import '../../domain/entities/chat_conversation.dart';
import '../../domain/entities/item_inquiry_data.dart';
import '../../domain/entities/rental_queue_card_data.dart';

abstract final class ChatConversationModel {
  static ChatConversation fromRecords({
    required Map<String, dynamic> conversation,
    required Map<String, dynamic>? otherProfile,
    required Map<String, dynamic>? item,
    required String currentUserId,
    bool hasUnreadMessage = false,
  }) {
    final id = conversation['id'].toString();
    final renterId = conversation['renter_id']?.toString() ?? '';
    final ownerId = conversation['owner_id']?.toString() ?? '';
    final isUserRenter = currentUserId == renterId;
    final otherUserId = isUserRenter ? ownerId : renterId;

    final role = isUserRenter
        ? ChatParticipantRole.owner
        : ChatParticipantRole.renter;

    final rawDisplayName =
        otherProfile?['display_name']?.toString().trim() ?? '';
    final email = otherProfile?['email']?.toString().trim() ?? '';
    final emailName = email.contains('@') ? email.split('@').first : email;
    final displayName = rawDisplayName.isNotEmpty
        ? rawDisplayName
        : (emailName.isNotEmpty ? emailName : 'ผู้ใช้งาน Yuemnoi');
    final avatarUrl = otherProfile?['user_image_url']?.toString().trim() ?? '';

    final rawLastMessage =
        conversation['last_message']?.toString().trim() ?? '';
    final queue = RentalQueueCardData.fromMessage(rawLastMessage);
    final String cleanPreview;
    if (rawLastMessage.isEmpty) {
      cleanPreview = 'เริ่มการสนทนา';
    } else if (queue != null) {
      cleanPreview = 'คิวเช่าต่อ · ${queue.name}';
    } else if (rawLastMessage.contains('[BOOKING_DATA:')) {
      cleanPreview = '📋 คำขอเช่าอุปกรณ์';
    } else if (ItemInquiryData.isInquiry(rawLastMessage)) {
      final inquiry = ItemInquiryData.fromChatMessage(rawLastMessage);
      cleanPreview = inquiry != null && inquiry.itemName.isNotEmpty
          ? '💬 สนใจเช่า: ${inquiry.itemName}'
          : '💬 สนใจเช่าอุปกรณ์';
    } else if (rawLastMessage.startsWith('↩ ตอบกลับ:') ||
        rawLastMessage.startsWith('💬 ตอบกลับ') ||
        rawLastMessage.startsWith('↪ ตอบกลับ')) {
      final newlineIdx = rawLastMessage.indexOf('\n');
      if (newlineIdx != -1) {
        cleanPreview = rawLastMessage.substring(newlineIdx + 1).trim();
      } else {
        final pipeParts = rawLastMessage.split('|');
        if (pipeParts.length >= 2) {
          cleanPreview = pipeParts[1].trim();
        } else {
          cleanPreview = rawLastMessage;
        }
      }
    } else {
      cleanPreview = rawLastMessage;
    }

    final lastMessageAtStr =
        conversation['last_message_at']?.toString() ??
        conversation['created_at']?.toString();
    final lastMessageAt = lastMessageAtStr != null
        ? DateTime.tryParse(lastMessageAtStr)?.toLocal()
        : null;

    final timeLabel = formatTimeLabel(lastMessageAt);

    int? itemId;
    if (conversation['item_id'] != null) {
      itemId = conversation['item_id'] is num
          ? (conversation['item_id'] as num).toInt()
          : int.tryParse(conversation['item_id'].toString());
    }

    String? itemName;
    String? itemImageUrl;
    int? itemPrice;
    String? itemRentalType;

    if (item != null) {
      itemName = item['item_name']?.toString().trim();
      final rawImages = item['item_image_url'];
      if (rawImages is List && rawImages.isNotEmpty) {
        itemImageUrl = rawImages.first.toString();
      } else if (rawImages is String && rawImages.isNotEmpty) {
        itemImageUrl = rawImages;
      }
      if (item['price'] != null) {
        itemPrice = item['price'] is num
            ? (item['price'] as num).toInt()
            : int.tryParse(item['price'].toString());
      }
      itemRentalType = item['type']?.toString().trim();
    }

    // คำนวณสถานะออนไลน์ (เขียว เมื่อ active ภายใน 2 นาที และ is_online = true, ค่าเริ่มต้นเทาเมื่อ offline)
    bool isOnline = false;
    if (otherProfile != null) {
      final isOnlineFlag = otherProfile['is_online'] == true;
      final lastSeenAtStr = otherProfile['last_seen_at']?.toString();
      if (lastSeenAtStr != null) {
        final lastSeenAt = DateTime.tryParse(lastSeenAtStr)?.toUtc();
        if (lastSeenAt != null) {
          final diff = DateTime.now().toUtc().difference(lastSeenAt);
          isOnline = isOnlineFlag && diff.inMinutes < 2;
        } else {
          isOnline = isOnlineFlag;
        }
      } else {
        isOnline = isOnlineFlag;
      }
    }

    return ChatConversation(
      id: id,
      otherUserId: otherUserId,
      name: displayName,
      role: role,
      avatarAsset: avatarUrl.isEmpty ? 'assets/images/user.png' : avatarUrl,
      preview: cleanPreview,
      timeLabel: timeLabel,
      lastMessageAt: lastMessageAt,
      itemId: itemId,
      itemName: itemName,
      itemImageUrl: itemImageUrl,
      itemPrice: itemPrice,
      itemRentalType: itemRentalType,
      isOnline: isOnline,
      hasUnreadMessage: hasUnreadMessage,
    );
  }

  static const List<String> _thaiShortMonths = [
    'ม.ค.',
    'ก.พ.',
    'มี.ค.',
    'เม.ย.',
    'พ.ค.',
    'มิ.ย.',
    'ก.ค.',
    'ส.ค.',
    'ก.ย.',
    'ต.ค.',
    'พ.ย.',
    'ธ.ค.',
  ];

  static String formatTimeLabel(DateTime? time) {
    if (time == null) return 'ตอนนี้';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final targetDay = DateTime(time.year, time.month, time.day);
    final diffDays = today.difference(targetDay).inDays;

    // ถ้าเป็นข้อความของวันนี้ แสดงเป็นเวลาว่าส่งตอนกี่โมง (เช่น 14:30)
    if (diffDays == 0) {
      final minuteStr = time.minute.toString().padLeft(2, '0');
      final hourStr = time.hour.toString().padLeft(2, '0');
      return '$hourStr:$minuteStr';
    } else if (diffDays == 1) {
      return 'เมื่อวาน';
    } else if (now.year == time.year) {
      try {
        return DateFormat('d MMM', 'th').format(time);
      } catch (_) {
        final month = (time.month >= 1 && time.month <= 12)
            ? _thaiShortMonths[time.month - 1]
            : '${time.month}';
        return '${time.day} $month';
      }
    } else {
      return '${time.day}/${time.month}/${time.year % 100}';
    }
  }
}
