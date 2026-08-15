import 'package:intl/intl.dart';

import '../../domain/entities/chat_conversation.dart';

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

    final email = otherProfile?['email']?.toString().trim() ?? '';
    final emailName = email.contains('@') ? email.split('@').first : email;
    final displayName = emailName.isEmpty ? 'ผู้ใช้งาน Yuemnoi' : emailName;
    final avatarUrl = otherProfile?['user_image_url']?.toString().trim() ?? '';

    final rawLastMessage = conversation['last_message']?.toString().trim() ?? '';
    final lastMessageAtStr = conversation['last_message_at']?.toString() ??
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
      preview: rawLastMessage.isEmpty ? 'เริ่มการสนทนา' : rawLastMessage,
      timeLabel: timeLabel,
      itemId: itemId,
      itemName: itemName,
      itemImageUrl: itemImageUrl,
      itemPrice: itemPrice,
      itemRentalType: itemRentalType,
      isOnline: isOnline,
      hasUnreadMessage: hasUnreadMessage,
    );
  }

  static String formatTimeLabel(DateTime? time) {
    if (time == null) return 'ตอนนี้';
    final now = DateTime.now();

    // ถ้าเป็นข้อความของวันนี้ แสดงเป็นเวลาว่าส่งตอนกี่โมง (เช่น 14:30)
    if (now.year == time.year &&
        now.month == time.month &&
        now.day == time.day) {
      return DateFormat('HH:mm').format(time);
    } else if (now.year == time.year &&
        now.month == time.month &&
        now.day - time.day == 1) {
      return 'เมื่อวาน';
    } else if (now.year == time.year) {
      return DateFormat('d MMM', 'th').format(time);
    } else {
      return DateFormat('d/M/yy').format(time);
    }
  }
}
