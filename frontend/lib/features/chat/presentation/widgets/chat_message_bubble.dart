import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../../booking/domain/entities/booking_request_model.dart';
import '../../../item_detail/presentation/widgets/full_screen_image_viewer.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/item_inquiry_data.dart';
import 'booking_request_bubble_card.dart';
import 'chat_avatar.dart';
import 'chat_message_action_sheet.dart';
import 'chat_stacked_image_card.dart';
import 'item_inquiry_bubble_card.dart';
import 'stacked_images_grid_screen.dart';
import 'swipe_to_reply.dart';

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

class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.message,
    this.imageUrls = const [],
    this.otherAvatarAsset,
    this.otherUserName,
    this.isOwner,
    this.showAvatar = false,
    this.deliveryStatus,
    this.isRead = false,
    this.showDeliveryStatus = false,
    this.isFailed = false,
    this.isHighlighted = false,
    this.onRetry,
    this.onReply,
    this.onEdit,
    this.onDelete,
    this.onQuotedTap,
  });

  final ChatMessage message;
  final List<String> imageUrls;
  final String? otherAvatarAsset;
  final String? otherUserName;
  final bool? isOwner;
  final bool showAvatar;
  final String? deliveryStatus;
  final bool isRead;
  final bool showDeliveryStatus;
  final bool isFailed;
  final bool isHighlighted;
  final VoidCallback? onRetry;
  final ValueChanged<ChatMessage>? onReply;
  final ValueChanged<ChatMessage>? onEdit;
  final ValueChanged<ChatMessage>? onDelete;
  final ValueChanged<String>? onQuotedTap;

  static ({
    String? replyHeader,
    String? quotedText,
    String? quotedImageUrl,
    String? quotedMessageId,
    String actualText,
  }) _parseReplyContent(String raw) {
    if (raw.startsWith('↩ ตอบกลับ:')) {
      final newlineIdx = raw.indexOf('\n');
      if (newlineIdx != -1) {
        final headerPart = raw.substring('↩ ตอบกลับ:'.length, newlineIdx).trim();
        final actual = raw.substring(newlineIdx + 1);

        String target = '';
        String quote = '';
        String? msgId;
        String? imgUrl;

        if (headerPart.contains('|')) {
          final parts = headerPart.split('|');
          target = parts.isNotEmpty ? parts[0].trim() : '';
          quote = parts.length > 1 ? parts[1].trim() : '';
          msgId = parts.length > 2 && parts[2].trim().isNotEmpty ? parts[2].trim() : null;
          if (parts.length > 3 && parts[3].trim().isNotEmpty) {
            imgUrl = parts.sublist(3).join('|').trim();
          }
        } else if (headerPart.contains(':')) {
          final colonIdx = headerPart.indexOf(':');
          target = headerPart.substring(0, colonIdx).trim();
          quote = headerPart.substring(colonIdx + 1).replaceAll('"', '').trim();
        } else {
          target = headerPart;
        }

        // Clean up quote if it contains trailing URLs or Supabase URLs
        if (quote.contains('http://') || quote.contains('https://')) {
          final httpIdx = quote.indexOf('http');
          final urlCandidate = quote.substring(httpIdx).trim();
          imgUrl ??= urlCandidate;
          quote = quote.substring(0, httpIdx).replaceAll('|', '').trim();
        }

        // If quote still contains pipes or legacy IDs (e.g. "ทำไร|136|", "นกยก|133|")
        if (quote.contains('|')) {
          final subParts = quote.split('|');
          quote = subParts.first.trim();
          if (msgId == null && subParts.length > 1 && subParts[1].trim().isNotEmpty) {
            msgId = subParts[1].trim();
          }
          if (imgUrl == null && subParts.length > 2 && subParts[2].trim().startsWith('http')) {
            imgUrl = subParts.sublist(2).join('|').trim();
          }
        }

        if (quote.startsWith('↩ ตอบกลับ:')) {
          quote = _extractActualTextMessage(quote);
        }

        if (quote == '📷 ส่งรูปภาพ' || quote == '[รูปภาพ]') {
          quote = '📷 รูปภาพ';
        }

        if (quote.isEmpty && imgUrl != null && imgUrl.isNotEmpty) {
          quote = '📷 รูปภาพ';
        }

        return (
          replyHeader: 'คุณตอบกลับ$target',
          quotedText: quote.isNotEmpty ? quote : (imgUrl != null ? '📷 รูปภาพ' : null),
          quotedImageUrl: (imgUrl != null && (imgUrl.startsWith('http://') || imgUrl.startsWith('https://'))) ? imgUrl : null,
          quotedMessageId: msgId,
          actualText: actual,
        );
      }
    } else if (raw.startsWith('💬 ตอบกลับ')) {
      final newlineIdx = raw.indexOf('\n');
      if (newlineIdx != -1) {
        final headerPart = raw
            .substring(0, newlineIdx)
            .replaceFirst('💬 ตอบกลับ', '')
            .replaceAll('"', '')
            .replaceFirst(':', '')
            .trim();
        final actual = raw.substring(newlineIdx + 1);
        return (
          replyHeader: 'คุณตอบกลับ$headerPart',
          quotedText: null,
          quotedImageUrl: null,
          quotedMessageId: null,
          actualText: actual,
        );
      }
    }
    return (
      replyHeader: null,
      quotedText: null,
      quotedImageUrl: null,
      quotedMessageId: null,
      actualText: raw,
    );
  }

  void _showActions(BuildContext context) {
    final effectiveImages = imageUrls.isNotEmpty
        ? imageUrls
        : (message.imageUrl != null && message.imageUrl!.isNotEmpty
            ? [message.imageUrl!]
            : <String>[]);

    ChatMessageActionSheet.show(
      context,
      message: message,
      imageUrls: effectiveImages,
      onReply: () => onReply?.call(message),
      onEdit: onEdit != null ? () => onEdit?.call(message) : null,
      onDelete: () => onDelete?.call(message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMine = message.isMine;

    final isBooking = BookingRequestData.isBookingRequest(message.message);
    if (isBooking) {
      final bookingData = BookingRequestData.fromChatMessage(
        message.message,
        imageUrl: message.imageUrl,
        messageId: message.id,
      );

      if (bookingData != null) {
        final bookingCard = GestureDetector(
          onLongPress: () => _showActions(context),
          child: BookingRequestBubbleCard(
            message: message,
            bookingData: bookingData,
            senderName: otherUserName,
            isOwner: isOwner,
          ),
        );

        final statusFailedWidget = isFailed
            ? GestureDetector(
                onTap: onRetry,
                child: const Padding(
                  padding: EdgeInsets.only(right: 6, bottom: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline_rounded,
                          color: Color(0xFFEF4444), size: 15),
                      SizedBox(width: 3),
                      Text(
                        'ส่งไม่สำเร็จ',
                        key: ValueKey('chat-message-failed-status'),
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFFEF4444),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : null;

        final statusTextWidget = (isMine && showDeliveryStatus && !isRead)
            ? Padding(
                padding: const EdgeInsets.only(right: 6, bottom: 4),
                child: Text(
                  deliveryStatus ?? 'ส่งแล้ว',
                  key: const ValueKey('chat-message-delivery-status'),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8A8E92),
                    fontWeight: FontWeight.w400,
                  ),
                ),
              )
            : null;

        final avatarStatusWidget = (isMine && showDeliveryStatus && isRead)
            ? Container(
                key: const ValueKey('chat-message-delivery-status'),
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                ),
                child: ChatAvatar(
                  asset: otherAvatarAsset ?? 'assets/images/user.png',
                  size: 16,
                  showStatus: false,
                ),
              )
            : null;

        final body = isMine
            ? Row(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ?statusFailedWidget,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      bookingCard,
                      if (statusTextWidget != null)
                        Padding(
                          padding:
                              const EdgeInsets.only(top: 3, right: 6, bottom: 2),
                          child: statusTextWidget,
                        ),
                      if (avatarStatusWidget != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2, right: 2),
                          child: avatarStatusWidget,
                        ),
                    ],
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (showAvatar)
                    Padding(
                      padding: const EdgeInsets.only(right: 8, bottom: 2),
                      child: ChatAvatar(
                        asset: otherAvatarAsset ?? 'assets/images/user1.png',
                        size: 28,
                        showStatus: false,
                      ),
                    )
                  else
                    const SizedBox(width: 36),
                  Flexible(child: bookingCard),
                ],
              );

        final bubbleContainer = AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            color: isHighlighted
                ? AppColors.primaryColor.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: body,
        );

        return SwipeToReply(
          isMine: isMine,
          onReply: () => onReply?.call(message),
          child: bubbleContainer,
        );
      }
    }

    final isInquiry = ItemInquiryData.isInquiry(message.message);
    if (isInquiry) {
      final inquiryData = ItemInquiryData.fromChatMessage(
        message.message,
        imageUrl: message.imageUrl,
      );

      if (inquiryData != null) {
        final inquiryCard = GestureDetector(
          onLongPress: () => _showActions(context),
          child: ItemInquiryBubbleCard(
            message: message,
            inquiryData: inquiryData,
          ),
        );

        final statusFailedWidget = isFailed
            ? GestureDetector(
                onTap: onRetry,
                child: const Padding(
                  padding: EdgeInsets.only(right: 6, bottom: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline_rounded,
                          color: Color(0xFFEF4444), size: 15),
                      SizedBox(width: 3),
                      Text(
                        'ส่งไม่สำเร็จ',
                        key: ValueKey('chat-message-failed-status'),
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFFEF4444),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : null;

        final statusTextWidget = (isMine && showDeliveryStatus && !isRead)
            ? Padding(
                padding: const EdgeInsets.only(right: 6, bottom: 4),
                child: Text(
                  deliveryStatus ?? 'ส่งแล้ว',
                  key: const ValueKey('chat-message-delivery-status'),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8A8E92),
                    fontWeight: FontWeight.w400,
                  ),
                ),
              )
            : null;

        final avatarStatusWidget = (isMine && showDeliveryStatus && isRead)
            ? Container(
                key: const ValueKey('chat-message-delivery-status'),
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                ),
                child: ChatAvatar(
                  asset: otherAvatarAsset ?? 'assets/images/user.png',
                  size: 16,
                  showStatus: false,
                ),
              )
            : null;

        final body = isMine
            ? Row(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ?statusFailedWidget,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      inquiryCard,
                      if (statusTextWidget != null)
                        Padding(
                          padding:
                              const EdgeInsets.only(top: 3, right: 6, bottom: 2),
                          child: statusTextWidget,
                        ),
                      if (avatarStatusWidget != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2, right: 2),
                          child: avatarStatusWidget,
                        ),
                    ],
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (showAvatar)
                    Padding(
                      padding: const EdgeInsets.only(right: 8, bottom: 2),
                      child: ChatAvatar(
                        asset: otherAvatarAsset ?? 'assets/images/user1.png',
                        size: 28,
                        showStatus: false,
                      ),
                    )
                  else
                    const SizedBox(width: 36),
                  Flexible(child: inquiryCard),
                ],
              );

        final bubbleContainer = AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            color: isHighlighted
                ? AppColors.primaryColor.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: body,
        );

        return SwipeToReply(
          isMine: isMine,
          onReply: () => onReply?.call(message),
          child: bubbleContainer,
        );
      }
    }

    final effectiveImages = imageUrls.isNotEmpty
        ? imageUrls
        : (message.imageUrl != null && message.imageUrl!.isNotEmpty
            ? [message.imageUrl!]
            : <String>[]);
    final hasImage = effectiveImages.isNotEmpty;
    final hasText = message.message.isNotEmpty &&
        message.message != '📷 ส่งรูปภาพ' &&
        message.message != '[รูปภาพ]';

    final statusFailedWidget = isFailed
        ? GestureDetector(
            onTap: onRetry,
            child: const Padding(
              padding: EdgeInsets.only(right: 6, bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 15),
                  SizedBox(width: 3),
                  Text(
                    'ส่งไม่สำเร็จ',
                    key: ValueKey('chat-message-failed-status'),
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFFEF4444),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          )
        : null;

    final statusTextWidget = (isMine && showDeliveryStatus && !isRead)
        ? Text(
            deliveryStatus ?? 'ส่งแล้ว',
            key: const ValueKey('chat-message-delivery-status'),
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF8A8E92),
              fontWeight: FontWeight.w400,
            ),
          )
        : null;

    final avatarStatusWidget = (isMine && showDeliveryStatus && isRead)
        ? Container(
            key: const ValueKey('chat-message-delivery-status'),
            width: 16,
            height: 16,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
            ),
            child: ChatAvatar(
              asset: otherAvatarAsset ?? 'assets/images/user.png',
              size: 16,
              showStatus: false,
            ),
          )
        : null;

    // ถ้ามีรูปภาพอย่างเดียว (หรือชุดรูปภาพหลายรูปที่ซ้อนกัน) -> แสดงเป็นการ์ดรูปภาพซ้อนกัน 3D Deck of Cards
    if (hasImage && !hasText) {
      final imageCard = ChatStackedImageCard(
        imageUrls: effectiveImages,
        isMine: isMine,
        onLongPress: () => _showActions(context),
        onTap: () {
          if (effectiveImages.length > 1) {
            StackedImagesGridScreen.open(
              context,
              imageUrls: effectiveImages,
            );
          } else {
            FullScreenImageViewer.open(
              context,
              imageUrls: effectiveImages,
              initialIndex: 0,
            );
          }
        },
      );

      final body = isMine
          ? Row(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ?statusFailedWidget,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    imageCard,
                    if (statusTextWidget != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3, right: 6, bottom: 2),
                        child: statusTextWidget,
                      ),
                    if (avatarStatusWidget != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2, right: 2),
                        child: avatarStatusWidget,
                      ),
                  ],
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (showAvatar)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 2),
                    child: ChatAvatar(
                      asset: otherAvatarAsset ?? 'assets/images/user1.png',
                      size: 28,
                      showStatus: false,
                    ),
                  )
                else
                  const SizedBox(width: 36),
                Flexible(child: imageCard),
              ],
            );

      final bubbleContainer = AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: isHighlighted
              ? AppColors.primaryColor.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: body,
      );

      return SwipeToReply(
        isMine: isMine,
        onReply: () => onReply?.call(message),
        child: bubbleContainer,
      );
    }

    final replyData = _parseReplyContent(message.message);

    final bubbleContent = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.72,
      ),
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: isMine ? AppColors.primaryColor : const Color(0xFFE4E6EB),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(isMine ? 20 : 4),
          bottomRight: Radius.circular(isMine ? 4 : 20),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (hasImage)
            GestureDetector(
              onTap: () {
                if (effectiveImages.length > 1) {
                  StackedImagesGridScreen.open(
                    context,
                    imageUrls: effectiveImages,
                  );
                } else {
                  FullScreenImageViewer.open(
                    context,
                    imageUrls: effectiveImages,
                    initialIndex: 0,
                  );
                }
              },
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.72,
                  maxHeight: 300,
                ),
                child: CachedNetworkImage(
                  imageUrl: effectiveImages.first,
                  fit: BoxFit.contain,
                  placeholder: (context, url) => Container(
                    width: 220,
                    height: 180,
                    color: Colors.black12,
                    child: const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primaryColor,
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    width: 220,
                    height: 140,
                    color: Colors.black12,
                    child: const Icon(
                      Icons.broken_image_rounded,
                      size: 40,
                    ),
                  ),
                ),
              ),
            ),
          if (hasText)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              child: Text(
                replyData.actualText,
                style: TextStyle(
                  color: isMine ? Colors.white : const Color(0xFF1C1E21),
                  fontSize: 15,
                  height: 1.35,
                ),
              ),
            ),
        ],
      ),
    );

    final bubble = GestureDetector(
      onLongPress: () => _showActions(context),
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // 1. Reply Header: ↩ คุณตอบกลับตัวเอง / chn.benmat
          if (replyData.replyHeader != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 6, right: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.reply_rounded,
                    size: 13,
                    color: Color(0xFF8A8E92),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    replyData.replyHeader!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8A8E92),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

          // 2. Messenger-style Quoted Media / Text
          if (replyData.replyHeader != null &&
              replyData.quotedImageUrl != null &&
              replyData.quotedImageUrl!.isNotEmpty)
            // Quoted Image Preview with overlapping reply bubble at bottom-right
            GestureDetector(
              onTap: () {
                if (replyData.quotedMessageId != null) {
                  onQuotedTap?.call(replyData.quotedMessageId!);
                }
              },
              child: Stack(
                clipBehavior: Clip.none,
                alignment: isMine ? Alignment.bottomRight : Alignment.bottomLeft,
                children: [
                  Container(
                    width: 220,
                    height: 140,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: CachedNetworkImage(
                      imageUrl: replyData.quotedImageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(
                        color: Colors.black26,
                        child: const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primaryColor,
                          ),
                        ),
                      ),
                      errorWidget: (_, _, _) => Container(
                        color: Colors.black26,
                        child: const Icon(
                          Icons.broken_image_rounded,
                          size: 36,
                          color: Colors.white54,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: isMine ? 0 : null,
                    left: isMine ? null : 0,
                    child: bubbleContent,
                  ),
                ],
              ),
            )
          else if (replyData.replyHeader != null &&
              replyData.quotedText != null &&
              replyData.quotedText!.isNotEmpty)
            // Quoted Text bubble with reply bubble directly below it
            Column(
              crossAxisAlignment:
                  isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () {
                    if (replyData.quotedMessageId != null) {
                      onQuotedTap?.call(replyData.quotedMessageId!);
                    }
                  },
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * 0.70,
                    ),
                    margin: const EdgeInsets.only(bottom: 3),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2C2D35).withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      replyData.quotedText!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ),
                bubbleContent,
              ],
            )
          else
            bubbleContent,
        ],
      ),
    );

    final body = isMine
        ? Row(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ?statusFailedWidget,
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    bubble,
                    if (statusTextWidget != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3, right: 6, bottom: 2),
                        child: statusTextWidget,
                      ),
                    if (avatarStatusWidget != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2, right: 2),
                        child: avatarStatusWidget,
                      ),
                  ],
                ),
              ),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (showAvatar)
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 2),
                  child: ChatAvatar(
                    asset: otherAvatarAsset ?? 'assets/images/user1.png',
                    size: 28,
                    showStatus: false,
                  ),
                )
              else
                const SizedBox(width: 36),
              Flexible(child: bubble),
            ],
          );

    final bubbleContainer = AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: isHighlighted
            ? AppColors.primaryColor.withValues(alpha: 0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: body,
    );

    return SwipeToReply(
      isMine: isMine,
      onReply: () => onReply?.call(message),
      child: bubbleContainer,
    );
  }
}
