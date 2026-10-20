import 'chat_cached_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/colors.dart';
import '../../../booking/domain/entities/booking_request_model.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_reply_content.dart';
import '../../domain/entities/item_inquiry_data.dart';

class ChatReplyPreview extends StatelessWidget {
  const ChatReplyPreview({
    super.key,
    required this.reply,
    required this.isMine,
    this.originalMessage,
    this.otherUserName,
    this.onTap,
  });

  final ChatReplyContent reply;
  final bool isMine;
  final ChatMessage? originalMessage;
  final String? otherUserName;
  final VoidCallback? onTap;

  static bool _isProduct(String text) =>
      text.startsWith('อุปกรณ์:') ||
      text.startsWith(BookingRequestData.bookingPayloadPrefix);

  @override
  Widget build(BuildContext context) {
    final original = originalMessage;
    final originalText = original == null
        ? ''
        : ChatReplyContent.messageText(original.message);
    final inquiry = ItemInquiryData.fromChatMessage(originalText);
    final booking = BookingRequestData.isBookingRequest(originalText)
        ? BookingRequestData.fromChatMessage(originalText)
        : null;
    final isProduct =
        inquiry != null || booking != null || _isProduct(reply.quotedText);
    final imageUrl = original == null
        ? reply.quotedImageUrl
        : ChatReplyContent.preview(original).imageUrl ?? reply.quotedImageUrl;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    final quotedText = original == null ? reply.quotedText : originalText;
    final title =
        inquiry?.itemName ??
        booking?.item.title ??
        reply.quotedText
            .replaceFirst(
              RegExp(r'^(?:📋 คำขอเช่าอุปกรณ์:?\s*)?(?:อุปกรณ์:\s*)?'),
              '',
            )
            .trim();
    final price =
        inquiry?.displayPrice ??
        (booking == null
            ? ''
            : '${NumberFormat('#,##0.##').format(booking.totalPrice)} ฿');
    final alignment = isMine
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    final label =
        '${isMine ? 'คุณ' : (otherUserName ?? 'ผู้ใช้')}ตอบกลับ${reply.target}';

    return Semantics(
      button: onTap != null,
      label: '$label ${isProduct ? title : (hasImage ? 'รูปภาพ' : quotedText)}',
      child: GestureDetector(
        key: const ValueKey('chat-reply-preview'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: alignment,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.reply_rounded,
                    size: 14,
                    color: Color(0xFF858A96),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF717784),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!isProduct && !hasImage)
              Container(
                key: const ValueKey('chat-reply-text-quote'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8EAEE),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  quotedText.isEmpty ? 'ข้อความ' : quotedText,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
              )
            else if (!isProduct)
              ClipRRect(
                key: const ValueKey('chat-reply-media-card'),
                borderRadius: BorderRadius.circular(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 176,
                    maxHeight: 136,
                  ),
                  child: _image(imageUrl, isProduct: false),
                ),
              )
            else
              Container(
                key: const ValueKey('chat-reply-media-card'),
                width: 188,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE4E6EB)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 112,
                      child: _image(imageUrl, isProduct: true),
                    ),
                    if (isProduct)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              booking != null ||
                                      reply.quotedText.startsWith(
                                        BookingRequestData.bookingPayloadPrefix,
                                      )
                                  ? 'คำขอเช่าอุปกรณ์'
                                  : 'อุปกรณ์ที่สนใจ',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF717784),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              title.isEmpty ? 'อุปกรณ์เช่า' : title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF30343B),
                                height: 1.35,
                              ),
                            ),
                            if (price.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                price,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primaryColor,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _image(String? imageUrl, {required bool isProduct}) =>
      imageUrl == null || imageUrl.isEmpty
      ? _placeholder(isProduct)
      : ChatCachedImage(
          imageUrl: imageUrl,
          fit: BoxFit.contain,
          placeholder: (_, _) => _placeholder(isProduct),
          errorWidget: (_, _, _) => _placeholder(isProduct),
        );

  Widget _placeholder(bool isProduct) => ColoredBox(
    color: isProduct ? const Color(0xFFF0F1F4) : Colors.transparent,
    child: Center(
      child: Icon(
        isProduct ? Icons.inventory_2_outlined : Icons.image_outlined,
        size: 30,
        color: const Color(0xFF969CAA),
      ),
    ),
  );
}
